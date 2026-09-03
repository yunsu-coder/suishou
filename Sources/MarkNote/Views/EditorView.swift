import SwiftUI
import AppKit
import AVKit
import UniformTypeIdentifiers

/// 视图模式：仅编辑 / 分屏 / 仅预览
enum EditorMode: String, CaseIterable {
    case editor, split, preview
}

/// 分屏编辑器：标题 + [源码编辑器 | 实时预览] + 状态栏
struct EditorView: View {
    @Environment(NotesStore.self) private var store
    @Binding var showVersions: Bool
    @State private var textViewRef: NSTextView?
    @State private var currentLine = 1
    @State private var currentColumn = 0
    @State private var zoomImage: ZoomTarget?
    // VS Code 式查找/替换（⌘F / ⇧⌘F）
    @State private var showFind = false
    @State private var findQuery = ""
    @State private var findReplace = ""
    @State private var showFindReplace = false
    @State private var findCount = 0
    @State private var findCurrent = 0
    @FocusState private var findFocused: Bool
    @AppStorage("editorMode") private var mode = EditorMode.split.rawValue
    // 字体/字号/缩放直接用 @AppStorage（与设置窗口同键）：UserDefaults 变更即时触发本视图重渲
    // （store.editorFontSize 这类经 store 计算的属性不追踪 UserDefaults —— 设置窗口改完主窗口不动）
    @AppStorage("editorFontSize") private var editorFontSize = 13.0
    @AppStorage("editorFontFamily") private var editorFontFamily = "mono"
    @AppStorage("previewFontScale") private var previewFontScale = 1.0
    @AppStorage("previewFont") private var previewFontSetting = "system"
    @AppStorage(Glass.key) private var windowGlass = 0.0

    struct ZoomTarget: Identifiable {
        let url: URL
        var id: String { url.path }
    }
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // 以"真正装载"或"媒体查看"为显示条件：单击仅选中不闪空编辑器；装载后显示
        Group {
        if store.loadedNoteID == nil && store.previewMedium == nil {
            EmptyStateView()
                .frame(minWidth: 520)
        } else {
            VStack(spacing: 0) {
                header
                Group {
                    switch EditorMode(rawValue: mode) ?? .split {
                    case .editor:
                        editorPane
                            // 动画① 触发点：过渡挂分支视图本身；compositingGroup 离屏栅格化防卡
                            .compositingGroup()
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 8)),
                                removal: .opacity
                            ))
                    case .preview:
                        previewPane
                            .compositingGroup()
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 8)),
                                removal: .opacity
                            ))
                    case .split:
                        HSplitView {
                            editorPane.frame(minWidth: 320, idealWidth: 560)
                            previewPane.frame(minWidth: 320, idealWidth: 720)
                        }
                        .compositingGroup()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 8)),
                            removal: .opacity
                        ))
                    }
                }
                .layoutPriority(1)
                .animation(.timingCurve(0.25, 1, 0.4, 1, duration: 0.18), value: mode)
                statusBar
            }
            // 动画② 触发点（笔记切换 6pt + fade 0.12s）：整块内容随 loadedNoteID 换档（防卡：轻量） 
            .id("doc-\(store.loadedNoteID ?? "none")")
            .compositingGroup()
            .transition(.opacity.combined(with: .offset(y: 6)))
            .animation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.12), value: store.loadedNoteID)
            // 「插入」菜单 → 光标处插入 Markdown 语法
            .onReceive(NotificationCenter.default.publisher(for: .insertMarkdown)) { note in
                if let kind = note.object as? InsertKind {
                    insertMarkdown(kind)
                }
            }
            // ⌘F / ⇧⌘F 查找替换（VS Code 浮条）
            .onReceive(NotificationCenter.default.publisher(for: .findReplaceRequested)) { note in
                showFind = true
                showFindReplace = (note.object as? String) == "replace"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { findFocused = true }
            }
            // 编辑器内 ⌘⌫/⌘⌦ → 删除选中文件（进回收站）
            .onReceive(NotificationCenter.default.publisher(for: .deleteNoteRequested)) { _ in
                _ = store.deleteSelection()
            }
            // 命令面板转发：附件面板 / 版本历史
            .onReceive(NotificationCenter.default.publisher(for: .requestVersions)) { _ in
                showVersions = true
            }
            // 仅"真正装载了文件"才聚焦编辑器（双击打开后；单击多选时焦点留在列表 → ⇧/⌘ 可用）
            .onChange(of: store.loadedNoteID) { _, newID in
                guard let newID else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    if store.loadedNoteID == newID {
                        textViewRef?.window?.makeFirstResponder(textViewRef)
                    }
                }
            }
            // C-04：外部修改冲突 —— 三选处理（不可点击遮罩关闭，避免误判）
            .sheet(isPresented: Binding(
                get: { store.externalConflict },
                set: { _ in }
            )) {
                ExternalConflictView()
                    .environment(store)
                    .interactiveDismissDisabled()
            }
            .sheet(isPresented: $showVersions) {
                if let id = store.selectedNoteID {
                    VersionsView(noteID: id)
                        .environment(store)
                }
            }
            // AI：选中文本快捷操作（快捷键 / 命令面板 / 右键菜单）/ 插入结果
            .onReceive(NotificationCenter.default.publisher(for: .aiQuickActionRequested)) { note in
                if let action = note.object as? AIQuickAction {
                    runQuickAction(action)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .aiInsertResult)) { note in
                if let text = note.object as? String {
                    insertAIText(text)
                }
            }
            .sheet(item: $zoomImage) { target in
                ImageZoomView(url: target.url)
            }
        }
        }

    }

    // MARK: - 标题

    private var header: some View {
        HStack(spacing: 8) {
            // 侧栏显隐按钮（最左侧；⌘B 等效）
            Button {
                NotificationCenter.default.post(name: .toggleSidebarRequested, object: nil)
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(_LL("显示 / 隐藏资源管理器（⌘B）", "Show / Hide Explorer (⌘B)"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(store.openTabs, id: \.self) { id in
                        tabItem(id)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
        .padding(.horizontal, 10)
        .padding(.top, 26)
        .padding(.bottom, 4)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// 单个 Tab：标题按钮（点击切换）+ 关闭按钮；当前 Tab 高亮
    private func tabItem(_ id: String) -> some View {
        let active = store.loadedNoteID == id
        return HStack(spacing: 5) {
            Button {
                store.openNote(id)
            } label: {
                Text(store.tabTitle(id))
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 140)
                    .foregroundStyle(active ? Color.primary : Color.secondary)
            }
            .buttonStyle(.plain)

            Button {
                store.closeTab(id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(2)
                    .background(Color(nsColor: .quaternaryLabelColor).opacity(0.25), in: Circle())
            }
            .buttonStyle(.plain)
            .help(_LL("关闭标签页 (⌘W)", "Close Tab (⌘W)"))
        }
        .padding(.leading, 8).padding(.trailing, 5)
        .padding(.vertical, 3)
        .background(active ? Color.accentColor.opacity(0.14) : Color.clear, in: Capsule())
    }

    // MARK: - 左：源码编辑器 / 右：预览

    private var editorPane: some View {
        MarkdownEditorView(
            text: store.workingText,
            fontSize: editorFontSize,
            onChange: { new in store.textChanged(new) },
            onLineChange: { line, col in
                currentLine = line
                currentColumn = col
            },
            onImage: { data, ext in
                guard let id = store.selectedNoteID else { return nil }
                return store.saveImage(data, ext: ext, noteID: id)
            },
            onAttachment: { data, name in
                guard let id = store.selectedNoteID else { return nil }
                return store.saveAttachment(data, fileName: name, noteID: id)
            },
            revision: store.documentRevision,
            textViewRef: $textViewRef
        )
        .overlay(alignment: .topTrailing) {
            if store.dirty {
                Text("●")
                    .foregroundStyle(.tertiary)
                    .padding(8)
                    .help("有未保存修改")
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            importFromDrop(providers)
        }
    }

    private var previewPane: some View {
        switch store.previewMedium {
        case .image(let url):
            return AnyView(ImageZoomView(url: url))
        case .video(let url):
            return AnyView(InlineVideoView(url: url))
        case nil:
            break
        }
        _ = store.prepareImageRegistry(store.workingText)
        return AnyView(PreviewView(
            liveText: store.workingText,
            renderMode: renderMode,
            basePath: basePath,
            fontScale: previewFontScale,
            dark: effectiveDark,
            resetToken: store.selectedNoteID ?? "",
            theme: currentTheme.dataTheme,
            onOpenImage: { raw in
                if let url = URL(string: raw), url.isFileURL {
                    zoomImage = ZoomTarget(url: url)
                } else if let url = URL(string: raw), let scheme = url.scheme, scheme != "file" {
                    if let cached = store.remoteCachedFileURL(for: raw) {
                        zoomImage = ZoomTarget(url: cached)
                    } else {
                        NSWorkspace.shared.open(url)
                    }
                }
            },
            onOpenFile: { url in
                NSWorkspace.shared.open(url)
            },
            headingTarget: nil,
            imageCacheVersion: store.imageCacheVersion,
            imageRegistry: store.imageRegistry,
            imageRegistryVersion: store.imageRegistryVersion,
            fontRegistry: store.fontRegistry,
            fontRegistryVersion: store.fontRegistryVersion,
            glass: windowGlass,
            previewFont: previewFontFamily
        ))
    }

    /// 图片相对路径解析基准 = 文件目录（相对于笔记库根）
    private var basePath: String {
        var pct = store.notesDir.standardizedFileURL.absoluteString
        if !pct.hasSuffix("/") { pct += "/" }
        return pct
    }

    /// 渲染模式：md=Markdown；其他扩展名=纯代码高亮
    private var renderMode: String {
        let ext = (store.selectedNoteID as NSString?)?.pathExtension.lowercased() ?? ""
        return (ext.isEmpty || ["md", "markdown", "mdown", "txt"].contains(ext)) ? "md" : "code"
    }

    /// 预览字体（设置页选择；空 = 系统）
    private var previewFontFamily: String {
        switch UserDefaults.standard.string(forKey: "previewFont") ?? "" {
        case "pingfang": return "'PingFang SC', -apple-system, sans-serif"
        case "kaiti": return "'Kaiti SC', 'KaiTi', serif"
        case "songti": return "'Songti SC', serif"
        case "mono": return "'SF Mono', Menlo, monospace"
        default: return ""
        }
    }

    /// 预览深色：主题强制的深浅优先，其次系统外观
    private var effectiveDark: Bool {
        currentTheme == .night
    }

    private func insertMarkdown(_ kind: InsertKind) {
        guard let tv = textViewRef, let window = tv.window else { return }
        window.makeFirstResponder(tv)
        let sel = tv.selectedRange()
        let selected = (tv.string as NSString).substring(with: sel)
        let snippet: String
        switch kind {
        case .link:
            let label = selected.isEmpty ? _L("链接文字", "Link text") : selected
            snippet = "[\(label)](https://)"
        case .code:
            snippet = "`" + (selected.isEmpty ? "code" : selected) + "`"
        case .codeBlock:
            snippet = "```\n" + (selected.isEmpty ? "code" : selected) + "\n```"
        case .math:
            snippet = "$$" + (selected.isEmpty ? _L("公式", "Formula") : selected) + "$$"
        case .table:
            snippet = _L("| 列1 | 列2 | 列3 |\n| --- | --- | --- |\n| 　 | 　 | 　 |", "| Col 1 | Col 2 | Col 3 |\n| --- | --- | --- |\n| 　 | 　 | 　 |")
        case .attachment:
            // 附件面板：图片/任意文件通吃，自动分类存储
            let panel = NSOpenPanel()
            panel.message = _L("选择要插入的图片或文件（可多选）", "Choose an image or file to insert (multiple selection allowed)")
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            panel.allowedContentTypes = [] // 不限制：图片/PDF/文本/压缩包均可
            guard panel.runModal() == .OK, let id = store.selectedNoteID else {
                window.makeFirstResponder(tv)
                return
            }
            let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff"]
            var inserted = 0
            for url in panel.urls {
                guard let data = try? Data(contentsOf: url) else { continue }
                let ext = url.pathExtension.lowercased()
                let displayName = url.lastPathComponent
                if imageExts.contains(ext) {
                    if let rel = store.saveImage(data, ext: ext == "jpeg" ? "jpg" : (ext.isEmpty ? "png" : ext), noteID: id) {
                        tv.insertText("![\(displayName)](\(rel))\n", replacementRange: tv.selectedRange())
                        inserted += 1
                    }
                } else {
                    if let rel = store.saveAttachment(data, fileName: displayName, noteID: id) {
                        // @ 前缀 = 附件卡语义（预览渲染为卡，任意类型；与普通链接区分）
                        tv.insertText("@[\(displayName)](\(rel))\n", replacementRange: tv.selectedRange())
                        inserted += 1
                    }
                }
            }
            if inserted == 0 {
                let alert = NSAlert(error: NSError(domain: "MarkNote", code: -1,
                                                   userInfo: [NSLocalizedDescriptionKey: _L("附件保存失败，请检查文件是否可读", "Failed to save attachment. Check that the file is readable")]))
                alert.runModal()
            }
            window.makeFirstResponder(tv)
            return
        }
        tv.insertText(snippet, replacementRange: sel)
        // 插入后光标落位：无选中时预选「占位词」（打字即替换，不用删除操作）；
        // 有选中时（包裹模式）：代码块光标落在包裹内容末尾，继续写代码不打断
        switch kind {
        case .codeBlock:
            if selected.isEmpty {
                tv.setSelectedRange(NSRange(location: sel.location + 4, length: 4)) // 预选 code
            } else {
                tv.setSelectedRange(NSRange(location: sel.location + 4 + (selected as NSString).length, length: 0))
            }
        case .code:
            if selected.isEmpty { tv.setSelectedRange(NSRange(location: sel.location + 1, length: 4)) } // 预选 code
        case .math:
            if selected.isEmpty { tv.setSelectedRange(NSRange(location: sel.location + 2, length: (_L("公式", "Formula") as NSString).length)) } // 预选 公式
        case .link:
            if selected.isEmpty { tv.setSelectedRange(NSRange(location: sel.location + 1, length: (_L("链接文字", "Link text") as NSString).length)) } // 预选 链接文字
        default:
            break
        }
        window.makeFirstResponder(tv)
    }

    /// AI 快捷操作：翻译 / 改写 / 润色（替换选区，走撤销栈）
    private func runQuickAction(_ action: AIQuickAction) {
        guard FeatureModules.isEnabled(FeatureModules.aiQuickActions) else {
            store.showHint(_L("AI 快捷操作已在设置中关闭", "AI quick actions are disabled in Settings"))
            return
        }
        guard let tv = textViewRef else { return }
        let sel = tv.selectedRange()
        guard sel.length > 0 else {
            store.showHint(_L("请先选中文本，再执行 AI \(action.title)", "Select text first, then run AI \(action.title)"))
            return
        }
        let selected = (tv.string as NSString).substring(with: sel)
        store.showHint(_L("AI \(action.title) 中…", "AI \(action.title) in progress…"))
        Task {
            do {
                let result = try await LLM.complete(system: action.systemPrompt,
                                                    user: selected,
                                                    temperature: action.temperature)
                guard !result.isEmpty else {
                    store.showHint(_L("AI 返回为空，请重试", "AI returned an empty result, please retry"))
                    return
                }
                tv.insertText(result, replacementRange: sel)
                store.showHint(_L("AI \(action.title) 完成（替换选中内容，可 ⌘Z 撤销）", "AI \(action.title) done (replaced selection, press ⌘Z to undo)"))
            } catch {
                store.showHint(_L("AI \(action.title) 失败：\(error.localizedDescription)", "AI \(action.title) failed: \(error.localizedDescription)"))
            }
        }
    }

    /// 把 AI 面板的回答插入当前光标处
    private func insertAIText(_ text: String) {
        guard let tv = textViewRef else { return }
        tv.window?.makeFirstResponder(tv)
        tv.insertText(text, replacementRange: tv.selectedRange())
    }

    /// 拖拽 .md/.txt 文件到编辑器 → 导入为新文件
    private func importFromDrop(_ providers: [NSItemProvider]) -> Bool {
        var ok = false
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                p.loadObject(ofClass: NSURL.self) { obj, _ in
                    if let url = obj as? URL {
                        DispatchQueue.main.async {
                            // 文本→导入；非文本（MP4/PDF）→原始放入当前文件夹
                            let category = store.index.first { $0.id == store.selectedNoteID }?.category ?? nil
                            if store.importDroppedFile(from: url, into: category) == nil {
                                store.showHint(_L("无法导入：\(url.lastPathComponent)", "Cannot import: \(url.lastPathComponent)"))
                            }
                        }
                    }
                }
                ok = true
            }
        }
        return ok
    }

    // MARK: - 状态栏

    private var statusBar: some View {
        HStack(spacing: 14) {
            if store.loadedNoteID != nil {
                Text("LF · Markdown")
                    .foregroundStyle(.tertiary)
            }
            if store.selectedNoteID != nil {
                Text(_L("\(store.workingText.count) 字符", "\(store.workingText.count) characters"))
                    .monospacedDigit()
                Text(_L("行 \(currentLine) · 列 \(currentColumn + 1)", "Line \(currentLine) · Col \(currentColumn + 1)"))
                    .monospacedDigit()
                Text(_L("共 \(store.workingText.split(separator: "\n").count + 1) 行", "\(store.workingText.split(separator: "\n").count + 1) lines total"))
                    .monospacedDigit()
            }
            Spacer()
            saveState
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private var saveState: some View {
        if store.conflictHandled {
            Button {
                store.reopenConflictPrompt()
            } label: {
                Text(_LL("⚠ 外部已修改：处理", "⚠ Externally modified: Handle"))
            }
            .buttonStyle(.link)
            .foregroundStyle(.orange)
            Divider().frame(height: 10)
        }
        if store.dirty {
            Text(_LL("● 未保存", "● Unsaved")).foregroundStyle(.orange)
        } else if let t = store.lastSavedAt {
            HStack(spacing: 4) {
                AnimatedCheckmark(progress: drawn ? 1.0 : 0.0)
                    .frame(width: 13, height: 13)
                Text(_L("已保存 \(t.formatted(date: .omitted, time: .shortened))", "Saved \(t.formatted(date: .omitted, time: .shortened))"))
            }
            .onChange(of: store.lastSavedAt) { _, _ in
                // 每次保存：对勾重新描线（easeInOutCubic 0.3s）
                drawn = false
                withAnimation(.easeInOut(duration: 0.3)) { drawn = true }
            }
        } else {
            Text(_LL("已保存", "Saved"))
        }
        Button(_LL("版本", "Versions")) { showVersions = true }
            .buttonStyle(.link)
            .font(.caption)
            .disabled(store.selectedNoteID == nil)
    }

    @State private var drawn = true
}

/// 对勾描线（trim 动画；S 级动画 ③ 保存反馈）
struct AnimatedCheckmark: View {
    var progress: CGFloat

    var body: some View {
        Shape()
            .trim(from: 0, to: progress)
            .stroke(Color.green.opacity(0.9), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
    }

    struct Shape: SwiftUI.Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addQuadCurve(to: CGPoint(x: rect.width * 0.42, y: rect.height * 0.78),
                           control: CGPoint(x: rect.minX + 3, y: rect.midY + 4))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + 1),
                           control: CGPoint(x: rect.width * 0.62, y: rect.maxY * 0.95))
            return p
        }
    }
}


/// 预览面板内直接查看图片（单击树中图片文件 → 软缩放 + 双击弹大图）
private struct InlineImageViewer: View {
    let url: URL
    @State private var zoomed = false

    var body: some View {
        if let img = NSImage(contentsOf: url) {
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(minWidth: 320)
                    .padding(20)
            }
            .onTapGesture(count: 2) {
                zoomed = true
            }
            .sheet(isPresented: $zoomed) {
                ImageZoomView(url: url)
            }
        } else {
            Text(_L("图片加载失败：\(url.lastPathComponent)", "Failed to load image: \(url.lastPathComponent)"))
                .foregroundStyle(.secondary)
                .padding()
        }
    }
}

/// 预览面板内嵌视频播放器（单击树中视频文件 → 直接可播）
/// 注意：SwiftUI VideoPlayer 在 macOS 上不稳定（click mp4 即崩：type metadata fatal）——
/// 必须走 AppKit 正统 AVPlayerView（NSViewRepresentable）。
private struct InlineVideoView: View {
    let url: URL

    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            AVPlayerBox(url: url)
                .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// AppKit AVPlayerView 封装（macOS 稳定的本地播放器；自动播放、内置控件）
private struct AVPlayerBox: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = .inline
        v.player = AVPlayer(url: url)
        v.player?.play()
        return v
    }

    func updateNSView(_ v: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ v: AVPlayerView, coordinator: ()) {
        v.player?.pause()
        v.player = nil
    }
}

/// C-04：外部修改冲突提示（三选；由 NotesStore.resolveExternalConflict 落盘决策）
struct ExternalConflictView: View {
    @Environment(NotesStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(_LL("文件已被外部修改", "File was modified externally"))
                    .font(.headline)
                Spacer()
            }
            .padding(16)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text(_LL("正在编辑的文件在磁盘上已被其他应用修改（另外的应用 / 另一实例 / Finder）。为避免覆盖，自动保存已暂停。", "The file you are editing has been modified on disk by another app (another app / another instance / Finder). To avoid overwriting, auto-save has been paused."))
                Text(_LL("如何处理已有内容？", "How to handle the existing content?"))
                    .fontWeight(.medium)
                Text(_LL("「重新载入」会把你的当前改动写入历史版本；「保留我的内容」会把外部版本写入历史版本后覆盖。", "'Reload' will write your current changes to version history; 'Keep My Content' will write the external version to history and then overwrite."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            Divider()
            HStack {
                Button(_LL("稍后处理", "Later")) { store.resolveExternalConflict(.later) }
                Spacer()
                Button(_LL("保留我的内容", "Keep My Content")) { store.resolveExternalConflict(.keepMine) }
                    .buttonStyle(.bordered)
                Button(_LL("重新载入外部版本", "Reload External Version")) { store.resolveExternalConflict(.reload) }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 500, height: 240)
    }
}

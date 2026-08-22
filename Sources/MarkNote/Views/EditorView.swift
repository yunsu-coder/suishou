import SwiftUI
import AppKit
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
    @State private var showImages = false
    @State private var zoomImage: ZoomTarget?
    @AppStorage("editorMode") private var mode = EditorMode.split.rawValue

    struct ZoomTarget: Identifiable {
        let url: URL
        var id: String { url.path }
    }
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if store.selectedNoteID == nil {
            EmptyStateView()
                .frame(minWidth: 520)
        } else {
            VStack(spacing: 0) {
                header
                Group {
                    switch EditorMode(rawValue: mode) ?? .split {
                    case .editor:
                        editorPane
                    case .preview:
                        previewPane
                    case .split:
                        HSplitView {
                            editorPane.frame(minWidth: 320, idealWidth: 560)
                            previewPane.frame(minWidth: 320, idealWidth: 720)
                        }
                    }
                }
                .layoutPriority(1)
                statusBar
            }
            .navigationTitle(store.currentTitle.isEmpty ? "随手" : store.currentTitle)
            // 「插入」菜单 → 光标处插入 Markdown 语法
            .onReceive(NotificationCenter.default.publisher(for: .insertMarkdown)) { note in
                if let kind = note.object as? InsertKind {
                    insertMarkdown(kind)
                }
            }
            // 编辑器内 ⌘⌫/⌘⌦ → 删除选中笔记（进回收站）
            .onReceive(NotificationCenter.default.publisher(for: .deleteNoteRequested)) { _ in
                _ = store.deleteSelection()
            }
            // 命令面板转发：附件面板 / 版本历史
            .onReceive(NotificationCenter.default.publisher(for: .requestAttachments)) { _ in
                showImages = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestVersions)) { _ in
                showVersions = true
            }
            // 切换笔记：新笔记聚焦编辑器（聚焦不改光标位置）
            .onChange(of: store.selectedNoteID) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    if store.selectedNoteID != nil {
                        textViewRef?.window?.makeFirstResponder(textViewRef)
                    }
                }
            }
            .sheet(isPresented: $showVersions) {
                if let id = store.selectedNoteID {
                    VersionsView(noteID: id)
                        .environment(store)
                }
            }
            .sheet(isPresented: $showImages) {
                if let id = store.selectedNoteID {
                    AttachmentsView(noteID: id)
                        .environment(store)
                }
            }
            .sheet(item: $zoomImage) { target in
                ImageZoomView(url: target.url)
            }
        }
    }

    // MARK: - 标题

    private var header: some View {
        HStack(spacing: 10) {
            TextField("无标题", text: Binding(
                get: { store.currentTitle },
                set: { store.renameCurrentTo($0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 17, weight: .semibold))
            .onSubmit { store.saveCurrent() }
            .frame(maxWidth: .infinity)

            Button {
                showImages = true
            } label: {
                Label("附件", systemImage: "paperclip")
                    .labelStyle(.titleAndIcon)
                    .font(.callout)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("管理当前笔记的附件（图片/文件）")
            // 注：分类归属不进标题栏（"未分类"概念已从资源管理器根除）——
            //     移动分类走 行右键 → 移动到分类 / 文件夹拖放。
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - 左：源码编辑器 / 右：预览

    private var editorPane: some View {
        MarkdownEditorView(
            text: store.workingText,
            fontSize: store.editorFontSize,
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
        PreviewView(
            liveText: store.inlinePreviewImages(store.workingText),
            basePath: basePath,
            fontScale: store.previewFontScale,
            dark: effectiveDark,
            resetToken: store.selectedNoteID ?? "",
            theme: currentTheme.dataTheme,
            onOpenImage: { url in zoomImage = ZoomTarget(url: url) },
            onOpenFile: { url in
                // 相对路径（attachments/…）解析到笔记目录；markdown-it 编码过的路径需先还原。
                // 注意：appendingPathComponent 不能接收以 "/" 开头的串（会组装错），先去前导斜杠。
                let rawPath = url.path.removingPercentEncoding ?? url.path
                let rel = rawPath.hasPrefix("/") ? String(rawPath.dropFirst()) : rawPath
                let resolved = url.isFileURL ? url : store.notesDir.appendingPathComponent(rel)
                if FileManager.default.fileExists(atPath: resolved.path) {
                    NSWorkspace.shared.open(resolved)
                } else {
                    store.showHint("附件文件不存在：\(rel)")
                }
            },
            headingTarget: nil,   // 预览滚动跟随已随光标设计一并取消
            imageCacheVersion: store.imageCacheVersion,
            previewFont: previewFontFamily
        )
        .overlay(alignment: .topLeading) {
            Text("预览")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Color.bgOpacity, in: Capsule())
                .padding(10)
                .allowsHitTesting(false)
        }
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
        switch currentTheme {
        case .system: return colorScheme == .dark
        case .dawn: return false
        default: return true
        }
    }

    private var basePath: String {
        // 图片相对路径解析基准 = 笔记目录（与 start 的 files 目录惯例一致）
        var pct = store.notesDir.standardizedFileURL.absoluteString
        if !pct.hasSuffix("/") { pct += "/" }
        return pct
    }

    /// 光标处插入 Markdown 语法（选中文本作为内容主体）
    private func insertMarkdown(_ kind: InsertKind) {
        guard let tv = textViewRef, let window = tv.window else { return }
        window.makeFirstResponder(tv)
        let sel = tv.selectedRange()
        let selected = (tv.string as NSString).substring(with: sel)
        let snippet: String
        switch kind {
        case .link:
            let label = selected.isEmpty ? "链接文字" : selected
            snippet = "[\(label)](https://)"
        case .code:
            snippet = "`" + (selected.isEmpty ? "code" : selected) + "`"
        case .codeBlock:
            snippet = "```\n" + (selected.isEmpty ? "code" : selected) + "\n```"
        case .math:
            snippet = "$$" + (selected.isEmpty ? "公式" : selected) + "$$"
        case .table:
            snippet = "| 列1 | 列2 | 列3 |\n| --- | --- | --- |\n| 　 | 　 | 　 |"
        case .attachment:
            // 附件面板：图片/任意文件通吃，自动分类存储
            let panel = NSOpenPanel()
            panel.message = "选择要插入的图片或文件（可多选）"
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
                        tv.insertText("[\(displayName)](\(rel))\n", replacementRange: tv.selectedRange())
                        inserted += 1
                    }
                }
            }
            if inserted == 0 {
                let alert = NSAlert(error: NSError(domain: "MarkNote", code: -1,
                                                   userInfo: [NSLocalizedDescriptionKey: "附件保存失败，请检查文件是否可读"]))
                alert.runModal()
            }
            window.makeFirstResponder(tv)
            return
        }
        tv.insertText(snippet, replacementRange: sel)
        window.makeFirstResponder(tv)
    }

    /// 拖拽 .md/.txt 文件到编辑器 → 导入为新笔记
    private func importFromDrop(_ providers: [NSItemProvider]) -> Bool {
        var ok = false
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                p.loadObject(ofClass: NSURL.self) { obj, _ in
                    if let url = obj as? URL {
                        DispatchQueue.main.async {
                            _ = store.importNote(from: url)
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
            if store.selectedNoteID != nil {
                Text("\(store.workingText.count) 字符")
                    .monospacedDigit()
                Text("行 \(currentLine) · 列 \(currentColumn + 1)")
                    .monospacedDigit()
                Text("共 \(store.workingText.split(separator: "\n").count + 1) 行")
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
        if store.dirty {
            Text("● 未保存").foregroundStyle(.orange)
        } else if let t = store.lastSavedAt {
            Text("已保存 \(t.formatted(date: .omitted, time: .shortened))")
        } else {
            Text("已保存")
        }
        Button("版本") { showVersions = true }
            .buttonStyle(.link)
            .font(.caption)
            .disabled(store.selectedNoteID == nil)
    }
}

private extension Color {
    /// 预览右上角小标签的悬浮底色
    static let bgOpacity = Color(nsColor: .labelColor).opacity(0.12)
}

import AppKit
import SwiftUI

/// 流程图 —— 视图插件 `flowchart` 的内置渲染器。
///
/// 规则（见 docs/05-内置插件库.md）：
/// · 作用域：只读写**当前工作台**的 `source/flowchart/*.json`；不碰别的工作台；
/// · 图形 / 连线的颜色允许用户自选（流程图专属例外）；界面外壳仍取主题变量；
/// · 卸载即干净：删掉 `source/flowchart/` 即可，产物是普通 JSON + 导出的 PNG。
struct FlowchartView: View {
    let spec: PluginView

    @Environment(NotesStore.self) private var store
    @State private var editor: FlowchartEditor?
    @State private var docs: [FCDocRef] = []
    @State private var alertMessage: String?

    private var root: URL { store.notesDir }

    var body: some View {
        let theme = FlowchartTheme.current
        Group {
            if let editor {
                FlowchartEditorHost(editor: editor,
                                    theme: theme,
                                    docs: docs,
                                    root: root,
                                    onOpen: open(_:),
                                    onNew: createNew,
                                    onRename: renameCurrent,
                                    onDelete: deleteCurrent)
                    .id(editor.url.path)
            } else {
                FlowchartEmptyState(theme: theme, onCreate: createNew)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: root.path) { reloadWorkspace(autoOpen: true) }
        .onChange(of: store.notesDir.path) { _, _ in
            // 切换工作台：先落盘旧工作台的未保存改动，再彻底换掉编辑器实例
            // （否则旧工作台的图会挂在新工作台里显示，甚至保存回旧路径）
            if let current = editor, current.dirty { current.save() }
            editor = nil
            reloadWorkspace(autoOpen: true)
        }
        .alert(_L("无法打开", "Cannot open"), isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button(_L("好", "OK"), role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: 文档管理

    private func reloadWorkspace(autoOpen: Bool) {
        docs = FlowchartStore.list(root: root)
        if autoOpen, editor == nil {
            if let first = docs.first, let loaded = FlowchartStore.load(url: first.url) {
                editor = FlowchartEditor(doc: loaded, url: first.url)
            }
        }
    }

    private func createNew() {
        // 先落盘当前图的未保存改动，避免"改完立刻新建 → 改动丢失"
        if let current = editor, current.dirty { current.save() }
        let url = FlowchartStore.uniqueURL(root: root, name: _L("未命名流程图", "Untitled"))
        // 新图从空白画布开始：形状不带默认文字，左边挑框直接画
        let doc = FCDocument(name: url.deletingPathExtension().lastPathComponent)
        FlowchartStore.save(doc, url: url)
        docs = FlowchartStore.list(root: root)
        editor = FlowchartEditor(doc: doc, url: url)
        store.reloadIndex()
    }

    private func open(_ ref: FCDocRef) {
        if let current = editor, current.url.path == ref.url.path { return }
        if let current = editor, current.dirty { current.save() }
        guard let doc = FlowchartStore.load(url: ref.url) else {
            alertMessage = _L("文件读不出来，可能不是流程图 JSON：\n\(ref.url.lastPathComponent)",
                              "Not a flowchart JSON: \(ref.url.lastPathComponent)")
            return
        }
        editor = FlowchartEditor(doc: doc, url: ref.url)
    }

    private func renameCurrent() {
        guard let current = editor else { return }
        let field = NSTextField(string: current.doc.name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        let alert = NSAlert()
        alert.messageText = _L("重命名流程图", "Rename flowchart")
        alert.accessoryView = field
        alert.addButton(withTitle: _L("好", "OK"))
        alert.addButton(withTitle: _L("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = FlowchartStore.sanitize(field.stringValue)
        let target = FlowchartStore.dir(root: root).appendingPathComponent(name + ".json")
        guard target.path != current.url.path else { return }
        var candidate = target
        var i = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = FlowchartStore.dir(root: root).appendingPathComponent("\(name) \(i).json")
            i += 1
        }
        guard (try? FileManager.default.moveItem(at: current.url, to: candidate)) != nil else { return }
        var doc = current.doc
        doc.name = candidate.deletingPathExtension().lastPathComponent
        FlowchartStore.save(doc, url: candidate)
        docs = FlowchartStore.list(root: root)
        editor = FlowchartEditor(doc: doc, url: candidate)
        store.reloadIndex()
    }

    private func deleteCurrent() {
        guard let current = editor else { return }
        let alert = NSAlert()
        alert.messageText = _LF("删除「%@」？", "Delete \"%@\"?", current.doc.name)
        alert.informativeText = _L("文件会移到废纸篓，可以随时恢复。",
                                   "The file moves to the Trash and can be recovered.")
        alert.addButton(withTitle: _L("删除", "Delete"))
        alert.addButton(withTitle: _L("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? FileManager.default.trashItem(at: current.url, resultingItemURL: nil)
        docs = FlowchartStore.list(root: root)
        if let next = docs.first, let doc = FlowchartStore.load(url: next.url) {
            editor = FlowchartEditor(doc: doc, url: next.url)
        } else {
            editor = nil
        }
        store.reloadIndex()
    }
}

/// 无图时的空状态
private struct FlowchartEmptyState: View {
    let theme: FlowchartTheme
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "flowchart")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color(nsColor: theme.secondary))
            Text(_L("还没有流程图", "No flowcharts yet"))
                .font(theme.font(size: 15, bold: true, display: true))
                .foregroundStyle(Color(nsColor: theme.text))
            Text(_L("图会存在当前工作台的 source/flowchart/，导出 PNG 后即可插进笔记。",
                    "Charts are stored in this workspace at source/flowchart/."))
                .font(theme.font(size: 12))
                .foregroundStyle(Color(nsColor: theme.secondary))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button(action: onCreate) {
                Label(_L("新建流程图", "New Flowchart"), systemImage: "plus")
            }
            .controlSize(.large)
            .tint(Color(nsColor: theme.accent))
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 主界面（工具栏 + 画布 + 检查器）

/// 左侧形状库：只把**画流程图真正要用的四个框**摆在最显眼处
/// （开始 / 执行 / 判断 / 结束），其余形状与工具收进「更多」。
/// 点击选中工具、拖到画布直接放置。
private struct FlowchartToolPalette: View {
    @ObservedObject var editor: FlowchartEditor
    let theme: FlowchartTheme

    /// 四件套：开始 → 执行 → 判断 → 结束
    private let boxTools: [FCTool] = [.start, .rect, .diamond, .end]
    /// 常用工具
    private let tools: [FCTool] = [.select, .edge, .text]
    /// 其余形状（折叠，不干扰）
    private let moreShapes: [FCTool] = [.roundedRect, .ellipse, .parallelogram,
                                        .cylinder, .note, .group]

    @State private var showMore = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(_L("框", "Boxes"))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(boxTools, id: \.self) { tool in
                        boxCard(tool)
                    }
                }
                sectionTitle(_L("工具", "Tools"))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(tools, id: \.self) { tool in
                        card(tool)
                    }
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { showMore.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showMore ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text(_L("更多形状", "More shapes"))
                            .font(theme.font(size: 11))
                        Spacer()
                    }
                    .foregroundStyle(Color(nsColor: theme.secondary))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if showMore {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                        GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(moreShapes, id: \.self) { tool in
                            card(tool)
                        }
                    }
                }
                Text(_L("拖到画布放置，或点选后拖画。连第一个框时点「连线」：点起点 → 点终点。",
                        "Drag onto the canvas, or pick then drag-draw. To connect: pick Connect and click start → end."))
                    .font(theme.font(size: 10))
                    .foregroundStyle(Color(nsColor: theme.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .padding(10)
        }
        .background(Color(nsColor: theme.surface))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(theme.font(size: 11, bold: true))
            .foregroundStyle(Color(nsColor: theme.secondary))
    }

    /// 四个主框：卡片画的是**真实形状预览**，不是图标字
    private func boxCard(_ tool: FCTool) -> some View {
        let active = editor.tool == tool
        return Button {
            editor.tool = tool
        } label: {
            VStack(spacing: 5) {
                FCShapePreview(kind: tool.shape ?? .rect,
                               fill: theme.defaultFill(), stroke: theme.accent)
                    .frame(height: 30)
                Text(tool.label)
                    .font(theme.font(size: 11))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(Color(nsColor: theme.text))
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(active ? Color(nsColor: theme.accent).opacity(0.14)
                             : Color(nsColor: theme.background)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: active ? theme.accent : theme.border),
                        lineWidth: active ? 1.6 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .draggable(tool.rawValue)
        .help(tool.label)
    }

    private func card(_ tool: FCTool) -> some View {
        let active = editor.tool == tool
        return Button {
            editor.tool = tool
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tool.symbol)
                    .font(theme.font(size: 11, bold: true))
                    .font(.system(size: 15))
                    .frame(height: 20)
                Text(tool.label)
                    .font(theme.font(size: 9))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .foregroundStyle(Color(nsColor: active ? theme.background : theme.text))
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(active ? Color(nsColor: theme.accent) : Color(nsColor: theme.background)))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: active ? theme.accent : theme.border), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .draggable(tool.rawValue)   // 拖到画布直接放置（draw.io 习惯）
        .help(tool.label)
    }
}

/// 形状预览（形状库卡片 / 全局样式预览共用）
struct FCShapePreview: View {
    let kind: FCShapeKind
    var fill: NSColor?
    var stroke: NSColor
    var corner: Double = 8
    var lineWidth: Double = 1.6

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 2
            let rect = CGRect(x: inset, y: inset,
                              width: max(4, geo.size.width - inset * 2),
                              height: max(4, geo.size.height - inset * 2))
            let path = FCShape.path(kind: kind, rect: rect, corner: corner)
            if let fill {
                path.fill(Color(nsColor: fill))
            }
            path.stroke(Color(nsColor: stroke), lineWidth: lineWidth)
        }
    }
}

/// 主界面（工具栏 + 画布 + 检查器）。internal 以便测试直接渲染整屏。
struct FlowchartEditorHost: View {
    @ObservedObject var editor: FlowchartEditor
    let theme: FlowchartTheme
    let docs: [FCDocRef]
    let root: URL
    let onOpen: (FCDocRef) -> Void
    let onNew: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @Environment(NotesStore.self) private var store
    @State private var showExport = false
    @State private var showStyle = false
    @State private var exportBackground = 0
    @State private var exportScale = 2.0
    @State private var keyMonitor: Any?
    @State private var saveTask: Task<Void, Never>?
    @State private var lastSavedName = ""
    /// 本界面所在的窗口（sheet / 主窗口）。键盘监听只认这个窗口 ——
    /// 否则导出弹层、重命名弹窗等子窗口里的按键会被画布吞掉
    /// （方向键挪图形、退格删元素）。
    @State private var hostWindow: NSWindow?

    var body: some View {
        // draw.io 式三栏：左侧形状库（卡片网格）· 中间画布 · 右侧属性（选中时）
        HStack(spacing: 0) {
            FlowchartToolPalette(editor: editor, theme: theme)
                .frame(width: 152)
            Rectangle().fill(Color(nsColor: theme.border)).frame(width: 1)
            VStack(spacing: 0) {
                toolbar
                Rectangle().fill(Color(nsColor: theme.border)).frame(height: 1)
                HStack(spacing: 0) {
                    FlowchartCanvas(editor: editor, theme: theme)
                        .frame(minWidth: 320)
                    if editor.hasSelection {
                        Rectangle().fill(Color(nsColor: theme.border)).frame(width: 1)
                        FlowchartInspector(editor: editor, theme: theme)
                            .frame(width: 232)
                    }
                }
            }
        }
        .background(Color(nsColor: theme.background))
        .background(FCWindowReporter { hostWindow = $0 })
        .onAppear {
            installKeyMonitor()
            lastSavedName = editor.doc.name
            if editor.zoom == 1, editor.offset == .zero {
                // 首次打开：内容居中显示
                DispatchQueue.main.async {
                    if editor.canvasSize.width > 10 { editor.fit(in: editor.canvasSize) }
                }
            }
        }
        .onDisappear {
            if let m = keyMonitor { NSEvent.removeMonitor(m) }
            keyMonitor = nil
            saveTask?.cancel()
            if editor.dirty { editor.save(); store.reloadIndex() }
        }
        .onChange(of: editor.doc) { _, _ in scheduleAutoSave() }
        .onChange(of: editor.doc.name) { _, name in
            if name != lastSavedName {
                lastSavedName = name
                store.reloadIndex()
            }
        }
    }

    // MARK: 工具栏

    private var toolbar: some View {
        HStack(spacing: 8) {
            docMenu
            divider
            iconButton("arrow.uturn.backward", _L("撤销", "Undo"), enabled: editor.canUndo) { editor.undo() }
            iconButton("arrow.uturn.forward", _L("重做", "Redo"), enabled: editor.canRedo) { editor.redo() }
            divider
            iconButton("list.number", _L("自动编号", "Auto number"), enabled: !editor.doc.nodes.isEmpty) {
                editor.autoNumber()
            }
            iconButton("arrow.up.left.and.arrow.down.right",
                       _L("适应窗口", "Fit"), enabled: true) {
                editor.fit(in: editor.canvasSize)
            }
            zoomLabel
            Spacer(minLength: 4)
            Button {
                showStyle = true
            } label: {
                Label(_L("样式", "Style"), systemImage: "paintbrush")
            }
            .popover(isPresented: $showStyle, arrowEdge: .bottom) { stylePopover }
            Button {
                showExport = true
            } label: {
                Label(_L("导出 PNG", "Export PNG"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(nsColor: theme.accent))
            .popover(isPresented: $showExport, arrowEdge: .bottom) { exportPopover }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: theme.surface))
    }

    private var divider: some View {
        Rectangle().fill(Color(nsColor: theme.border)).frame(width: 1, height: 18)
    }

    private var docMenu: some View {
        Menu {
            Section(_L("新建", "New")) {
                Button(_L("新建流程图", "New Flowchart"), action: onNew)
            }
            if !docs.isEmpty {
                Section(_L("打开", "Open")) {
                    ForEach(docs) { ref in
                        Button {
                            onOpen(ref)
                        } label: {
                            if ref.url.path == editor.url.path {
                                Label(ref.name, systemImage: "checkmark")
                            } else {
                                Text(ref.name)
                            }
                        }
                    }
                }
            }
            Section {
                Button(_L("重命名…", "Rename…"), action: onRename)
                Button(_L("在访达中显示", "Reveal in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([editor.url])
                }
                Button(_L("删除…", "Delete…"), action: onDelete)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "flowchart")
                Text(editor.doc.name)
                    .font(theme.font(size: 12, bold: true))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(Color(nsColor: theme.text))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: theme.background)))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func iconButton(_ symbol: String, _ title: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 24, height: 22)
                .foregroundStyle(Color(nsColor: enabled ? theme.text : theme.secondary.withAlphaComponent(0.5)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(title)
    }

    private var zoomLabel: some View {
        Menu {
            Button("50%") { editor.zoom = 0.5 }
            Button("100%") { editor.resetZoom() }
            Button("150%") { editor.zoom = 1.5 }
            Button("200%") { editor.zoom = 2 }
            Divider()
            Button(_L("适应窗口", "Fit"), action: { editor.fit(in: editor.canvasSize) })
        } label: {
            Text("\(Int((editor.zoom * 100).rounded()))%")
                .font(theme.font(size: 11))
                .foregroundStyle(Color(nsColor: theme.secondary))
                .frame(width: 44)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: 导出

    private var exportPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(_L("导出 PNG", "Export PNG"))
                .font(theme.font(size: 13, bold: true))
            Picker(_L("背景", "Background"), selection: $exportBackground) {
                Text(_L("主题纸色", "Theme paper")).tag(0)
                Text(_L("白色", "White")).tag(1)
                Text(_L("透明", "Transparent")).tag(2)
            }
            .pickerStyle(.radioGroup)
            Picker(_L("倍率", "Scale"), selection: $exportScale) {
                Text("1x").tag(1.0)
                Text("2x").tag(2.0)
                Text("3x").tag(3.0)
            }
            .pickerStyle(.segmented)
            Text(_L("范围 = 全部内容（不含网格与选中框）",
                    "Exports all content, without grid or selection"))
                .font(theme.font(size: 11))
                .foregroundStyle(Color(nsColor: theme.secondary))
            Button {
                showExport = false
                exportPNG()
            } label: {
                Label(_L("导出到「下载/随手导出」", "Export"), systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(nsColor: theme.accent))
        }
        .padding(14)
        .frame(width: 250)
    }

    private func exportPNG() {
        let background: NSColor? = switch exportBackground {
        case 0: theme.background
        case 1: NSColor.white
        default: nil
        }
        let content = FlowchartExportCanvas(doc: editor.doc, theme: theme,
                                             background: background, padding: 24)
        let renderer = ImageRenderer(content: content)
        renderer.scale = exportScale
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            ExportService.presentExportError(NSError(domain: "flowchart", code: 1,
                                                     userInfo: [NSLocalizedDescriptionKey:
                                                        _L("渲染失败", "Render failed")]))
            return
        }
        ExportService.saveRendered(png, ext: "png", title: editor.doc.name)
    }

    // MARK: 自动保存

    // MARK: 全局样式（整张图一处调，不再逐个元素选填充）

    private var stylePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(_L("全局样式", "Global style"))
                .font(theme.font(size: 12, bold: true))
                .foregroundStyle(Color(nsColor: theme.text))
            Text(_L("整张图共用一种画风：换预设、改一处，所有框和线一起变。",
                    "One look for the whole chart — shapes and lines change together."))
                .font(theme.font(size: 10))
                .foregroundStyle(Color(nsColor: theme.secondary))
                .fixedSize(horizontal: false, vertical: true)

            // 预设
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(FCGlobalPreset.allCases, id: \.self) { preset in
                    Button {
                        editor.commit { $0.style.preset = preset }
                    } label: {
                        let rs = resolved(editor.doc.style, preset: preset)
                        HStack(spacing: 7) {
                            FCShapePreview(kind: .rect, fill: rs.fill, stroke: rs.stroke,
                                           corner: rs.corner, lineWidth: rs.lineWidth)
                                .frame(width: 26, height: 18)
                            Text(preset.label)
                                .font(theme.font(size: 11))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .foregroundStyle(Color(nsColor: theme.text))
                        .background(RoundedRectangle(cornerRadius: 7)
                            .fill(editor.doc.style.preset == preset
                                  ? Color(nsColor: theme.accent).opacity(0.14)
                                  : Color(nsColor: theme.background)))
                        .overlay(RoundedRectangle(cornerRadius: 7)
                            .stroke(Color(nsColor: editor.doc.style.preset == preset
                                          ? theme.accent : theme.border),
                                    lineWidth: editor.doc.style.preset == preset ? 1.6 : 1))
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }

            // 实时预览：两个框 + 一条连线
            stylePreview

            // 强调色
            HStack(spacing: 8) {
                ColorPicker("", selection: Binding(
                    get: {
                        if let hex = editor.doc.style.accent, let ns = NSColor.fcHex(hex) {
                            return Color(nsColor: ns)
                        }
                        return Color(nsColor: theme.accent)
                    },
                    set: { newColor in
                        let hex = NSColor(newColor).hexString
                        editor.commit { $0.style.accent = hex }
                    }
                ), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 32)
                Text(_L("强调色", "Accent"))
                    .font(theme.font(size: 11))
                    .foregroundStyle(Color(nsColor: theme.text))
                Spacer()
                Button(_L("跟随主题", "From theme")) {
                    editor.commit { $0.style.accent = nil }
                }
                .buttonStyle(.plain)
                .font(theme.font(size: 11))
                .foregroundStyle(Color(nsColor: theme.accent))
                .disabled(editor.doc.style.accent == nil)
            }

            globalSlider(_L("线条粗细", "Line width"), value: editor.doc.style.lineWidth,
                         range: 0.5...4) { v in
                editor.preview { $0.style.lineWidth = v }
            }
            globalSlider(_L("圆角", "Corner"), value: editor.doc.style.corner, range: 0...30) { v in
                editor.preview { $0.style.corner = v }
            }
            globalSlider(_L("字号", "Font size"), value: editor.doc.style.fontSize, range: 10...20) { v in
                editor.preview { $0.style.fontSize = v }
            }
            if editor.doc.style.preset == .soft {
                globalSlider(_L("填充浓度", "Fill"), value: editor.doc.style.fillOpacity,
                             range: 0...0.5) { v in
                    editor.preview { $0.style.fillOpacity = v }
                }
            }
            Toggle(_L("连线虚线", "Dashed lines"), isOn: Binding(
                get: { editor.doc.style.dashed },
                set: { on in editor.commit { $0.style.dashed = on } }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(theme.font(size: 11))
        }
        .padding(14)
        .frame(width: 312)
        .background(Color(nsColor: theme.surface))
    }

    /// 全局样式预览大图（按当前样式真实渲染两个框 + 一条折线）
    private var stylePreview: some View {
        let rs = editor.doc.style.resolved(theme: theme)
        return Canvas { ctx, size in
            let rect1 = CGRect(x: 12, y: size.height / 2 - 16, width: 74, height: 32)
            let rect2 = CGRect(x: size.width - 86, y: size.height / 2 - 16, width: 74, height: 32)
            let p1 = FCShape.path(kind: .capsule, rect: rect1, corner: rs.corner)
            let p2 = FCShape.path(kind: .diamond, rect: rect2, corner: rs.corner)
            if let fill = rs.fill {
                ctx.fill(p1, with: .color(Color(nsColor: fill)))
                ctx.fill(p2, with: .color(Color(nsColor: fill)))
            }
            ctx.stroke(p1, with: .color(Color(nsColor: rs.stroke)), lineWidth: rs.lineWidth)
            ctx.stroke(p2, with: .color(Color(nsColor: rs.stroke)), lineWidth: rs.lineWidth)
            var line = Path()
            let a = CGPoint(x: rect1.maxX, y: rect1.midY)
            let b = CGPoint(x: rect2.minX, y: rect2.midY)
            FCRenderer.roundedPolyline(&line, [a, CGPoint(x: (a.x + b.x) / 2, y: a.y),
                                               CGPoint(x: (a.x + b.x) / 2, y: b.y), b], radius: 5)
            ctx.stroke(line, with: .color(Color(nsColor: rs.stroke)),
                       style: StrokeStyle(lineWidth: rs.lineWidth,
                                          dash: rs.dashed ? [5, 4] : []))
            ctx.fill(FCShape.arrow(tip: b, direction: CGVector(dx: 0, dy: b.y - a.y), size: 8),
                     with: .color(Color(nsColor: rs.stroke)))
        }
        .frame(height: 62)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: theme.background)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: theme.border), lineWidth: 1))
    }

    /// 预设 + 当前参数（用于预设小方块预览，不写入文档）
    private func resolved(_ style: FCGlobalStyle, preset: FCGlobalPreset) -> FCRenderStyle {
        var copy = style
        copy.preset = preset
        return copy.resolved(theme: theme)
    }

    private func globalSlider(_ title: String, value: Double, range: ClosedRange<Double>,
                              apply: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(theme.font(size: 11))
                    .foregroundStyle(Color(nsColor: theme.text))
                Spacer()
                Text(String(format: "%.1f", value))
                    .font(theme.font(size: 10))
                    .foregroundStyle(Color(nsColor: theme.secondary))
            }
            Slider(value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) },
                                  set: { apply($0) }), in: range) { editing in
                if editing { editor.beginInteraction() } else { editor.endInteraction() }
            }
            .controlSize(.small)
        }
    }


    private func scheduleAutoSave() {
        saveTask?.cancel()
        guard editor.dirty else { return }
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            editor.save()
        }
    }

    // MARK: 快捷键

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let win = event.window, win.isKeyWindow else { return event }
            if let host = hostWindow, win !== host { return event }
            if let responder = win.firstResponder, responder is NSTextView || responder is NSTextField {
                return event   // 正在输入文字：全部放行
            }
            return handleKey(event) ? nil : event
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch event.keyCode {
        case 51, 117:   // delete / forward delete
            guard mods.isEmpty, editor.hasSelection else { return false }
            editor.deleteSelection()
            return true
        case 53:        // esc
            if editor.editingID != nil { editor.editingID = nil; return true }
            if editor.pendingEdge != nil || !editor.pendingWaypoints.isEmpty {
                editor.pendingEdge = nil
                editor.pendingWaypoints = []   // 拉线 / 断点一起取消
                return true
            }
            if mods.isEmpty, editor.hasSelection { editor.selection = []; return true }
            return false
        case 36:        // return：直接编辑选中项的文字（图形 / 文本框 / 连线标签）
            guard mods.isEmpty, editor.selection.count == 1, let id = editor.selection.first else { return false }
            editor.beginInteraction()
            editor.editingID = id
            return true
        case 123: return arrow(dx: -1, dy: 0, mods: mods)
        case 124: return arrow(dx: 1, dy: 0, mods: mods)
        case 125: return arrow(dx: 0, dy: 1, mods: mods)
        case 126: return arrow(dx: 0, dy: -1, mods: mods)
        default: break
        }
        guard mods.contains(.command) else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "z":
            if mods.contains(.shift) { editor.redo() } else { editor.undo() }
            return true
        case "a":
            editor.selection = editor.allIDs
            return true
        case "d":
            editor.duplicateSelection()
            return true
        case "c":
            editor.copySelection()
            return true
        case "x":
            editor.cutSelection()
            return true
        case "v":
            editor.pasteFromClipboard()
            return true
        case "s":
            editor.save()
            return true
        case "e":
            editor.autoNumber()
            return true
        case "0":
            editor.fit(in: editor.canvasSize)
            return true
        case "=", "+":
            editor.zoom = min(4, editor.zoom * 1.2)
            return true
        case "-":
            editor.zoom = max(0.2, editor.zoom / 1.2)
            return true
        default:
            return false
        }
    }

    private func arrow(dx: Double, dy: Double, mods: NSEvent.ModifierFlags) -> Bool {
        guard editor.hasSelection else { return false }
        let step = mods.contains(.shift) ? 10.0 : 1.0
        editor.nudge(dx: dx * step, dy: dy * step)
        return true
    }
}

// MARK: - 检查器

private struct FlowchartInspector: View {
    @ObservedObject var editor: FlowchartEditor
    let theme: FlowchartTheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let style = editor.primaryStyle {
                    if editor.hasShapeSelection { textSection(style) }
                    if editor.hasEdgeSelection { edgeSection }
                    arrangeSection
                    layerSection
                }
                canvasSection
            }
            .padding(12)
        }
        .background(Color(nsColor: theme.surface))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 11))
            Text(selectionTitle)
                .font(theme.font(size: 12, bold: true))
            Spacer()
            Button {
                editor.selection = []
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: theme.secondary))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Color(nsColor: theme.text))
    }

    private var selectionTitle: String {
        let n = editor.selection.count
        if n > 1 { return _LF("已选 %d 个元素", "%d selected", n) }
        if editor.selectedEdges.count == 1 { return _L("连线", "Connection") }
        if editor.doc.nodes.contains(where: { editor.selection.contains($0.id) }) { return _L("图形", "Shape") }
        if editor.doc.texts.contains(where: { editor.selection.contains($0.id) }) { return _L("文本框", "Text") }
        if editor.doc.groups.contains(where: { editor.selection.contains($0.id) }) { return _L("分组", "Group") }
        return _L("元素", "Element")
    }

    // MARK: 文字（逐元素只有「内容风格」；颜色/字号/线宽跟着全局样式走）

    private func textSection(_ style: FCStyle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(_L("文字", "Text"))
            HStack(spacing: 6) {
                toggleRow(_L("加粗", "Bold"), isOn: style.bold) { on in
                    editor.applyStyle { $0.bold = on }
                }
                Spacer()
                ForEach(FCTextAlign.allCases, id: \.self) { a in
                    Button {
                        editor.applyStyle { $0.align = a }
                    } label: {
                        Image(systemName: a.symbol)
                            .font(.system(size: 11))
                            .frame(width: 22, height: 20)
                            .foregroundStyle(style.align == a ? Color(nsColor: theme.accent)
                                                              : Color(nsColor: theme.secondary))
                    }
                    .buttonStyle(.plain)
                }
            }
            if editor.selection.count == 1, let id = editor.selection.first {
                Button {
                    editor.beginInteraction()
                    editor.editingID = id
                } label: {
                    Label(_L("编辑文字", "Edit text"), systemImage: "pencil")
                        .font(theme.font(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(nsColor: theme.accent))
            }
        }
    }

    private var edgeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(_L("连线", "Connection"))
            HStack(spacing: 6) {
                ForEach(FCRoute.allCases, id: \.self) { route in
                    pickChip(route.symbol, route.label, active: editor.selectedEdges.first?.route == route) {
                        editor.applyEdges { $0.route = route }
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(FCArrow.allCases, id: \.self) { arrow in
                    pickChip(arrow == .none ? "minus" : (arrow == .both ? "arrow.left.and.right" : "arrow.right"),
                             arrow.label, active: editor.selectedEdges.first?.arrow == arrow) {
                        editor.applyEdges { $0.arrow = arrow }
                    }
                }
            }
            TextField(_L("连线标签（是 / 否）", "Label"), text: Binding(
                get: { editor.selectedEdges.first?.label ?? "" },
                set: { value in editor.preview { doc in
                    let ids = editor.selection
                    for i in doc.edges.indices where ids.contains(doc.edges[i].id) { doc.edges[i].label = value }
                } }
            ))
            .textFieldStyle(.roundedBorder)
            .font(theme.font(size: 11))
            .onSubmit { editor.endInteraction() }
            // 两端接在哪条边（自动 = 按落点/位置判断；手动可精确指定，改完立刻重排）
            anchorPicker(_L("起点边", "From side"),
                         current: editor.selectedEdges.first?.fromAnchor ?? .auto) { anchor in
                editor.applyEdges { $0.fromAnchor = anchor }
            }
            anchorPicker(_L("终点边", "To side"),
                         current: editor.selectedEdges.first?.toAnchor ?? .auto) { anchor in
                editor.applyEdges { $0.toAnchor = anchor }
            }
        }
    }

    /// 连线端点接边选择器（自动 / 上 / 右 / 下 / 左）
    private func anchorPicker(_ title: String, current: FCAnchor,
                              apply: @escaping (FCAnchor) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(theme.font(size: 11))
                .foregroundStyle(Color(nsColor: theme.secondary))
            HStack(spacing: 4) {
                ForEach(FCAnchor.allCases, id: \.self) { a in
                    Button {
                        apply(a)
                    } label: {
                        Text(a == .auto ? _L("自动", "Auto") : a.label)
                            .font(theme.font(size: 10))
                            .frame(minWidth: 26)
                            .padding(.vertical, 3)
                            .foregroundStyle(Color(nsColor: current == a ? theme.background : theme.text))
                            .background(RoundedRectangle(cornerRadius: 5)
                                .fill(current == a ? Color(nsColor: theme.accent)
                                                   : Color(nsColor: theme.background)))
                            .overlay(RoundedRectangle(cornerRadius: 5)
                                .stroke(Color(nsColor: current == a ? theme.accent : theme.border),
                                        lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var arrangeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(_L("对齐", "Arrange"))
            HStack(spacing: 6) {
                ForEach(FCAlignMode.allCases, id: \.self) { mode in
                    Button {
                        let ids = editor.selection
                        editor.commit { $0.align(ids, mode) }
                    } label: {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 11))
                            .frame(width: 22, height: 20)
                            .foregroundStyle(Color(nsColor: theme.text))
                    }
                    .buttonStyle(.plain)
                    .help(mode.label)
                    .disabled(editor.selection.count < 2)
                }
            }
            HStack(spacing: 6) {
                Button(_L("水平均匀", "Distribute H")) {
                    let ids = editor.selection
                    editor.commit { $0.distribute(ids, horizontal: true) }
                }
                .disabled(editor.selection.count < 3)
                Button(_L("垂直均匀", "Distribute V")) {
                    let ids = editor.selection
                    editor.commit { $0.distribute(ids, horizontal: false) }
                }
                .disabled(editor.selection.count < 3)
            }
            .font(theme.font(size: 11))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var layerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(_L("层级与复制", "Layer"))
            HStack(spacing: 6) {
                Button(_L("置顶", "Front")) {
                    let ids = editor.selection
                    editor.commit { $0.bringToFront(ids) }
                }
                Button(_L("置底", "Back")) {
                    let ids = editor.selection
                    editor.commit { $0.sendToBack(ids) }
                }
                Button(_L("复制", "Duplicate")) { editor.duplicateSelection() }
                Button(_L("删除", "Delete"), role: .destructive) { editor.deleteSelection() }
            }
            .font(theme.font(size: 11))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var canvasSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(_L("画布", "Canvas"))
            toggleRow(_L("显示网格", "Grid"), isOn: editor.doc.showGrid) { on in
                editor.commit { $0.showGrid = on }
            }
            toggleRow(_L("对齐吸附", "Snap"), isOn: editor.doc.snap) { on in
                editor.commit { $0.snap = on }
            }
            if editor.doc.isEmpty {
                Text(_L("从工具栏挑一个图形，在画布上拖一下就开始画了。",
                        "Pick a shape and drag on the canvas to start."))
                    .font(theme.font(size: 11))
                    .foregroundStyle(Color(nsColor: theme.secondary))
            } else {
                HStack(spacing: 6) {
                    Button(_L("自动编号", "Auto number")) { editor.autoNumber() }
                    Button(_L("清空", "Clear"), role: .destructive) {
                        editor.commit { doc in
                            doc.nodes = []
                            doc.edges = []
                            doc.texts = []
                            doc.groups = []
                        }
                        editor.selection = []
                    }
                }
                .font(theme.font(size: 11))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Divider().padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 4) {
                hint(_L("拖图形边缘圆点 / 连线工具 → 拉出连线", "Drag from a node edge dot to connect"))
                hint(_L("双击图形 → 写文字", "Double-click a shape to edit text"))
                hint(_L("⌥ 拖拽 / 双指滚动 → 平移，⌘ 滚轮 → 缩放", "⌥-drag or scroll to pan, ⌘-scroll to zoom"))
                hint(_L("⌘Z 撤销 · ⌘D 复制 · ⌘E 自动编号 · 方向键微调",
                        "⌘Z undo · ⌘D duplicate · ⌘E number · arrows nudge"))
            }
        }
    }

    // MARK: 小组件

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(theme.font(size: 11, bold: true))
            .foregroundStyle(Color(nsColor: theme.secondary))
    }

    private func hint(_ text: String) -> some View {
        Text("· " + text)
            .font(theme.font(size: 11))
            .foregroundStyle(Color(nsColor: theme.secondary))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func toggleRow(_ title: String, isOn: Bool, apply: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: { apply($0) })) {
            Text(title).font(theme.font(size: 11))
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
    }

    private func pickChip(_ symbol: String, _ title: String, active: Bool,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .frame(width: 26, height: 20)
                .foregroundStyle(active ? Color(nsColor: theme.background) : Color(nsColor: theme.text))
                .background(RoundedRectangle(cornerRadius: 5)
                    .fill(active ? Color(nsColor: theme.accent) : Color(nsColor: theme.background)))
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

// MARK: - 窗口上报（键盘监听只认本界面所在窗口）

/// 把所在 NSWindow 上报给上层：sheet / 主窗口里按键要处理，
/// 导出弹层、重命名弹窗等子窗口里的按键必须放行。
private struct FCWindowReporter: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> FCWindowReportView {
        let view = FCWindowReportView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: FCWindowReportView, context: Context) {
        nsView.onChange = onChange
    }
}

private final class FCWindowReportView: NSView {
    var onChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // 延后一拍再回写 SwiftUI 状态：viewDidMoveToWindow 可能发生在布局期，
        // 布局期改状态会触发 AppKit 约束更新异常（项目里已有前车之鉴）。
        let w = window
        DispatchQueue.main.async { [weak self] in self?.onChange?(w) }
    }
}

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
        var doc = FCDocument(name: url.deletingPathExtension().lastPathComponent)
        doc.nodes = [sampleStart()]
        FlowchartStore.save(doc, url: url)
        docs = FlowchartStore.list(root: root)
        editor = FlowchartEditor(doc: doc, url: url)
        store.reloadIndex()
    }

    private func sampleStart() -> FCNode {
        var node = FCNode(kind: .capsule, origin: CGPoint(x: 120, y: 80), text: _L("开始", "Start"))
        node.style.fill = nil
        return node
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

/// 左侧形状库（draw.io 式）：卡片网格排列，点击选中工具、**拖到画布直接放置**。
private struct FlowchartToolPalette: View {
    @ObservedObject var editor: FlowchartEditor
    let theme: FlowchartTheme

    private let tools: [FCTool] = [.select, .rect, .roundedRect, .ellipse, .diamond,
                                   .parallelogram, .cylinder, .capsule, .note,
                                   .text, .group, .edge]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(_L("形状", "Shapes"))
                    .font(theme.font(size: 11, bold: true))
                    .foregroundStyle(Color(nsColor: theme.secondary))
                    .padding(.top, 4)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                    ForEach(tools, id: \.self) { tool in
                        card(tool)
                    }
                }
                Text(_L("拖到画布放置；或点选后在画布上拖画。双击空白 = 新矩形，双击图形 = 改文字。",
                        "Drag onto the canvas, or pick then drag-draw. Double-click blank = new rect; double-click a shape = edit text."))
                    .font(theme.font(size: 10))
                    .foregroundStyle(Color(nsColor: theme.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            .padding(10)
        }
        .background(Color(nsColor: theme.surface))
    }

    private func card(_ tool: FCTool) -> some View {
        let active = editor.tool == tool
        return Button {
            editor.tool = tool
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tool.symbol)
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
            if mods.isEmpty, editor.hasSelection { editor.selection = []; return true }
            return false
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
                    if editor.hasShapeSelection { colorSection(style) }
                    if editor.hasShapeSelection { strokeSection(style) }
                    textSection(style)
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

    // MARK: 颜色

    private func colorSection(_ style: FCStyle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(_L("填充", "Fill"))
            colorRow(style.fill) { value in editor.applyStyle { $0.fill = value } }
            sectionTitle(_L("边框", "Stroke"))
            colorRow(style.stroke) { value in editor.applyStyle { $0.stroke = value } }
        }
    }

    private func colorRow(_ current: String?, apply: @escaping (String?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ColorPicker("", selection: Binding(
                    get: {
                        if let hex = current, let ns = NSColor.fcHex(hex) { return Color(nsColor: ns) }
                        return Color(nsColor: theme.accent)
                    },
                    set: { apply(NSColor($0).hexString) }
                ), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 36)
                Text(current ?? _L("跟随主题", "From theme"))
                    .font(theme.font(size: 11))
                    .foregroundStyle(Color(nsColor: theme.secondary))
                Spacer()
                Button(_L("主题", "Theme")) { apply(nil) }
                    .buttonStyle(.plain)
                    .font(theme.font(size: 11))
                    .foregroundStyle(Color(nsColor: theme.accent))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(18), spacing: 4), count: 8), spacing: 4) {
                ForEach(Array(theme.palette.enumerated()), id: \.offset) { _, color in
                    Button {
                        apply(color.hexString)
                    } label: {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: color))
                            .frame(width: 18, height: 18)
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(nsColor: theme.border), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 线 / 面

    private func strokeSection(_ style: FCStyle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(_L("线条", "Line"))
            sliderRow(_L("粗细", "Width"), value: style.strokeWidth, range: 0.5...6) { value in
                editor.previewStyle { $0.strokeWidth = value }
            }
            toggleRow(_L("虚线", "Dashed"), isOn: style.dashed) { on in
                editor.applyStyle { $0.dashed = on }
            }
            toggleRow(_L("阴影", "Shadow"), isOn: style.shadow) { on in
                editor.applyStyle { $0.shadow = on }
            }
            sliderRow(_L("圆角", "Corner"), value: style.corner, range: 0...40) { value in
                editor.previewStyle { $0.corner = value }
            }
        }
    }

    private func textSection(_ style: FCStyle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(_L("文字", "Text"))
            sliderRow(_L("字号", "Size"), value: style.fontSize, range: 9...28) { value in
                editor.previewStyle { $0.fontSize = value }
            }
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
            sectionTitle(_L("文字颜色", "Text color"))
            colorRow(style.text) { value in editor.applyStyle { $0.text = value } }
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

    private func sliderRow(_ title: String, value: Double, range: ClosedRange<Double>,
                           apply: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(theme.font(size: 11))
                    .foregroundStyle(Color(nsColor: theme.text))
                Spacer()
                Text(String(format: "%.1f", value))
                    .font(theme.font(size: 10))
                    .foregroundStyle(Color(nsColor: theme.secondary))
            }
            Slider(value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) },
                                  set: { apply($0) }),
                   in: range) { editing in
                if editing { editor.beginInteraction() } else { editor.endInteraction() }
            }
            .controlSize(.small)
        }
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

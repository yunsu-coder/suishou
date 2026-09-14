import AppKit
import SwiftUI

/// 思维导图（视图插件 `mindmap`）：一张画布 + 左侧库 + 右侧检查器。
///
/// 定位和流程图同层：作用域只限**当前工作台**（`source/mindmap/*.json`），
/// 界面与画布都跟随主题；不一样的只有交互模型 ——
/// 思维导图是**键盘流**：Tab 加子节点、回车加同级、空格折叠、方向键在树里走。
struct MindMapView: View {
    let spec: PluginView
    @Environment(NotesStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var doc = MindMapDocument()
    @State private var name: String?
    @State private var entries: [MindMapEntry] = []
    @State private var selectedID: String?
    @State private var editingID: String?
    @State private var editingBackup = ""
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var undoStack: [MindMapDocument] = []
    @State private var redoStack: [MindMapDocument] = []
    @State private var dragMode: DragMode = .none
    @State private var dragNodeStart: CGPoint = .zero
    @State private var panStart: CGSize = .zero
    @State private var dropTarget: String?
    @State private var toast: String?
    @State private var keyMonitor: Any?
    @State private var scrollMonitor: Any?
    @State private var magnifyMonitor: Any?
    @State private var renameText = ""
    @State private var showRename = false

    private enum DragMode: Equatable {
        case none
        case node(String)
        case pan
    }

    // MARK: - 布局结果（文档一变就重算；量尺用画布同款字体）

    private var layout: (boxes: [MindMapBox], edges: [MindMapEdge]) {
        MindMapLayout.layout(doc.root, font: MindMapStyle.font(depth: 0), mode: doc.layoutMode)
    }

    private var selectedNode: MindMapNode? { selectedID.flatMap { doc.root.node(id: $0) } }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                canvasArea
                Divider()
                inspector
                    .frame(width: 272)
                    .background(Color(nsColor: appAppearance.surface ?? appAppearance.editorBackground))
            }
        }
        .frame(width: 1180, height: 780)
        .background(Color(nsColor: appAppearance.editorBackground))
        .overlay(alignment: .top) { toastView }
        .onAppear {
            reloadEntries()
            if let first = entries.first {
                open(first.name)
            } else {
                name = MindMapStore.create(store.notesDir, title: _L("我的第一张导图", "My first map"))
                reloadEntries()
                name.flatMap(open)
            }
            installMonitors()
            DispatchQueue.main.async { fit() }
        }
        .onDisappear { removeMonitors() }
        .alert(_L("重命名导图", "Rename map"), isPresented: $showRename) {
            TextField(_L("名字", "Name"), text: $renameText)
            Button(_L("取消", "Cancel"), role: .cancel) {}
            Button(_L("确定", "OK")) { rename(to: renameText) }
        }
    }

    // MARK: - 工具条

    private var toolbar: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(entries) { entry in
                    Button {
                        open(entry.name)
                    } label: {
                        Text("\(entry.title)（\(entry.nodeCount)）")
                    }
                }
                Divider()
                Button(_L("新建导图", "New map")) { newMap() }
                Button(_L("重命名…", "Rename…")) {
                    renameText = doc.title
                    showRename = true
                }
                Button(_L("删除这张导图", "Delete this map"), role: .destructive) { deleteCurrent() }
                Divider()
                Button(_L("从当前笔记大纲生成", "Import outline from current note")) { importOutline() }
                Button(_L("导出为 Markdown 大纲", "Export as Markdown outline")) { exportOutline() }
            } label: {
                Label(doc.title.isEmpty ? _L("未命名导图", "Untitled") : doc.title, systemImage: "chevron.down")
                    .font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Divider().frame(height: 16)

            Picker("", selection: Binding(get: { doc.layoutMode },
                                          set: { mode in mutate { $0.layoutMode = mode } })) {
                ForEach(MindMapLayoutMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 168)

            Button(_L("折叠全部", "Collapse all")) { setCollapsedAll(true) }
                .controlSize(.small)
            Button(_L("展开全部", "Expand all")) { setCollapsedAll(false) }
                .controlSize(.small)

            Divider().frame(height: 16)

            // 选中一级分支时：左右侧切换 + 分支颜色
            if let node = selectedNode, node.id != doc.root.id {
                Button {
                    mutate { $0.root.update(id: node.id) { $0.side = ($0.side == -1 ? 1 : -1) } }
                } label: {
                    Label(node.side == -1 ? _L("移到右侧", "Move right") : _L("移到左侧", "Move left"),
                          systemImage: node.side == -1 ? "arrow.right" : "arrow.left")
                }
                .controlSize(.small)
                Menu {
                    ForEach(0..<MindMapLayout.branchColorCount, id: \.self) { i in
                        Button {
                            mutate { $0.root.update(id: node.id) { $0.accent = i } }
                        } label: {
                            Label(_L("第 \(i + 1) 档", "Color \(i + 1)"), systemImage: node.accent == i ? "checkmark" : "circle")
                        }
                    }
                } label: {
                    Label(_L("分支颜色", "Branch color"), systemImage: "paintpalette")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Spacer()

            Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(undoStack.isEmpty)
                .help(_L("撤销 ⌘Z", "Undo ⌘Z"))
            Button { redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(redoStack.isEmpty)
                .help(_L("重做 ⇧⌘Z", "Redo ⇧⌘Z"))

            Divider().frame(height: 16)

            Button { zoomBy(1 / 1.2) } label: { Image(systemName: "minus.magnifyingglass") }
            Text("\(Int(zoom * 100))%")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42)
            Button { zoomBy(1.2) } label: { Image(systemName: "plus.magnifyingglass") }
            Button(_L("适应", "Fit")) { fit() }
                .controlSize(.small)

            Menu {
                Button(_L("导出 PNG（1x）", "Export PNG 1x")) { exportPNG(scale: 1, transparent: false) }
                Button(_L("导出 PNG（2x）", "Export PNG 2x")) { exportPNG(scale: 2, transparent: false) }
                Button(_L("导出 PNG（2x·透明底）", "Export PNG 2x transparent")) { exportPNG(scale: 2, transparent: true) }
            } label: {
                Label(_L("导出", "Export"), systemImage: "square.and.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                save()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - 画布

    private var canvasArea: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                MindMapCanvas(boxes: layout.boxes, edges: layout.edges,
                              selectedID: selectedID, zoom: zoom, offset: offset,
                              dropTargetID: dropTarget)
                if let editingID, let box = layout.boxes.first(where: { $0.id == editingID }) {
                    inlineEditor(box: box)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { value in
                if let box = hit(value.location) { beginEditing(box.id) }
            })
            .simultaneousGesture(SpatialTapGesture(count: 1).onEnded { value in
                commitEditing()
                if let box = hit(value.location) {
                    selectedID = box.id
                } else {
                    selectedID = doc.root.id
                }
            })
            .simultaneousGesture(MagnificationGesture().onChanged { value in
                zoom = min(3, max(0.2, value))
            })
            .overlay(alignment: .bottomLeading) {
                Text(_L("Tab 子节点 · ⏎ 同级 · 空格折叠 · 拖节点改归属 · ⌘滚轮缩放",
                        "Tab child · ⏎ sibling · Space collapse · drag to re-parent · ⌘scroll zoom"))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(10)
            }
            .onAppear { _ = geo.size }
        }
    }

    /// 双击后出现在节点位置的行内输入框
    private func inlineEditor(box: MindMapBox) -> some View {
        let rect = CGRect(x: box.rect.minX * zoom + offset.width,
                          y: box.rect.minY * zoom + offset.height,
                          width: max(box.rect.width * zoom, 120),
                          height: box.rect.height * zoom)
        return TextField("", text: Binding(get: { editingText(box.id) },
                                           set: { setEditingText($0, id: box.id) }))
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .frame(width: rect.width, height: max(rect.height, 26))
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: appAppearance.surface ?? appAppearance.editorBackground)))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: appAppearance.accentNS), lineWidth: 1.5))
            .offset(x: rect.minX, y: rect.minY)
            .onSubmit { commitEditing() }
    }

    @State private var editingText = ""

    private func editingText(_ id: String) -> String {
        doc.root.node(id: id)?.text ?? ""
    }

    private func setEditingText(_ text: String, id: String) {
        guard let current = doc.root.node(id: id) else { return }
        if editingID != id { editingID = id; editingBackup = current.text }
        editingText = text
        // 边打边改（撤销以「开始编辑」为界）
        doc.root.update(id: id) { $0.text = text }
    }

    private func beginEditing(_ id: String) {
        guard let node = doc.root.node(id: id) else { return }
        editingID = id
        editingBackup = node.text
        editingText = node.text
    }

    private func commitEditing() {
        guard let id = editingID else { return }
        editingID = nil
        doc.updated = MindMapDocument.now()
        save()
        _ = id
    }

    // MARK: - 手势

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if dragMode == .none {
                    if let box = hit(value.startLocation), box.id != doc.root.id {
                        dragMode = .node(box.id)
                        dragNodeStart = value.startLocation
                    } else {
                        dragMode = .pan
                        panStart = offset
                    }
                }
                switch dragMode {
                case .pan:
                    offset = CGSize(width: panStart.width + value.translation.width,
                                    height: panStart.height + value.translation.height)
                case .node:
                    dropTarget = hit(value.location)?.id == draggedID ? nil : hit(value.location)?.id
                case .none:
                    break
                }
            }
            .onEnded { value in
                switch dragMode {
                case .node(let id):
                    if let target = hit(value.location), target.id != id {
                        pushUndo()
                        _ = doc.root.move(id: id, toParent: target.id)
                        doc.updated = MindMapDocument.now()
                        save()
                    }
                    selectedID = id
                case .pan, .none:
                    break
                }
                dragMode = .none
                dropTarget = nil
            }
    }

    private var draggedID: String? {
        if case .node(let id) = dragMode { return id }
        return nil
    }

    /// 命中测试：屏幕坐标 → 节点
    private func hit(_ point: CGPoint) -> MindMapBox? {
        let p = CGPoint(x: (point.x - offset.width) / zoom, y: (point.y - offset.height) / zoom)
        return layout.boxes.last { $0.rect.insetBy(dx: -4, dy: -4).contains(p) }
    }

    // MARK: - 检查器

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let node = selectedNode {
                    Text(_L("节点", "Node"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(appAppearance.accent)
                    TextField(_L("文字", "Text"),
                              text: Binding(get: { node.text },
                                            set: { text in
                                                pushUndoThrottled()
                                                doc.root.update(id: node.id) { $0.text = text }
                                                scheduleSave()
                                            }))
                        .textFieldStyle(.roundedBorder)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(_L("备注（不画在图上）", "Note (not drawn)")).font(.system(size: 10)).foregroundStyle(.secondary)
                        TextEditor(text: Binding(get: { node.note ?? "" },
                                                 set: { text in
                                                     doc.root.update(id: node.id) { $0.note = text.isEmpty ? nil : text }
                                                     scheduleSave()
                                                 }))
                            .font(.system(size: 12))
                            .frame(height: 64)
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(Color(nsColor: appAppearance.editorBackground)))
                    }
                    if node.id != doc.root.id {
                        HStack(spacing: 6) {
                            Text(_L("位置", "Side")).font(.system(size: 11))
                            Picker("", selection: Binding(get: { node.side },
                                                          set: { v in
                                                              pushUndoThrottled()
                                                              doc.root.update(id: node.id) { $0.side = v }
                                                              scheduleSave()
                                                          })) {
                                Text(_L("自动", "Auto")).tag(0)
                                Text(_L("左", "Left")).tag(-1)
                                Text(_L("右", "Right")).tag(1)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 150)
                        }
                        HStack(spacing: 6) {
                            Text(_L("配色", "Color")).font(.system(size: 11))
                            ForEach(0..<MindMapLayout.branchColorCount, id: \.self) { i in
                                Circle()
                                    .fill(Color(nsColor: MindMapStyle.branchColor(i)))
                                    .frame(width: 16, height: 16)
                                    .overlay(Circle().stroke(Color.primary.opacity(node.accent == i ? 0.8 : 0),
                                                             lineWidth: 2))
                                    .onTapGesture {
                                        pushUndoThrottled()
                                        doc.root.update(id: node.id) { $0.accent = i }
                                        scheduleSave()
                                    }
                            }
                        }
                    }
                    Toggle(_L("折叠子节点", "Collapse children"),
                           isOn: Binding(get: { node.collapsed },
                                         set: { v in
                                             pushUndoThrottled()
                                             doc.root.update(id: node.id) { $0.collapsed = v }
                                             scheduleSave()
                                         }))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    HStack(spacing: 6) {
                        Button(_L("加子节点", "Add child")) { addChild(to: node.id) }
                        Button(_L("加同级", "Add sibling")) { addSibling(after: node.id) }
                            .disabled(node.id == doc.root.id)
                        Button(_L("删除", "Delete"), role: .destructive) { deleteNode(node.id) }
                            .disabled(node.id == doc.root.id)
                    }
                    .controlSize(.small)
                    Divider()
                    Text(_L("父节点：\(doc.root.parentID(of: node.id).flatMap { doc.root.node(id: $0)?.text } ?? "—")",
                            "Parent: ..."))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                } else {
                    Text(_L("没选中节点", "Nothing selected"))
                        .font(.system(size: 12, weight: .medium))
                    Text(_L("点一下节点开始编辑；画布空白处拖动可以平移整张图。",
                            "Click a node to edit; drag the background to pan."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text(_L("这张图", "This map")).font(.system(size: 11, weight: .semibold))
                    Text(_L("节点 \(doc.root.totalCount) 个 · 可见 \(doc.root.visibleCount) 个 · 深度 \(doc.root.maxDepth + 1) 层",
                            "\(doc.root.totalCount) nodes · \(doc.root.visibleCount) visible · depth \(doc.root.maxDepth + 1)"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(_L("存在 source/mindmap/\(name ?? "…").json（当前工作台）",
                            "Saved to source/mindmap/\(name ?? "…").json"))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Divider()
                Text(_L("快捷键：Tab 子节点 / ⏎ 同级 / ⇧Tab 提升一级 / ⌫ 删除 / 空格 折叠 / 方向键 在树里走 / ⌘Z 撤销 / ⌘0 适应",
                        "Keys: Tab child / ⏎ sibling / ⇧Tab outdent / ⌫ delete / Space collapse / arrows navigate / ⌘Z undo / ⌘0 fit"))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
        }
    }

    private var toastView: some View {
        Group {
            if let toast {
                Text(toast)
                    .font(.system(size: 11))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Color(nsColor: appAppearance.accentNS).opacity(0.16)))
                    .foregroundStyle(appAppearance.accent)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - 文档操作

    private func reloadEntries() { entries = MindMapStore.list(store.notesDir) }

    private func open(_ mapName: String) {
        guard let loaded = MindMapStore.load(store.notesDir, name: mapName) else { return }
        doc = loaded
        name = mapName
        selectedID = loaded.root.id
        editingID = nil
        undoStack = []; redoStack = []
        DispatchQueue.main.async { fit() }
    }

    private func newMap() {
        let created = MindMapStore.create(store.notesDir, title: _L("新导图", "New map"))
        reloadEntries()
        open(created)
    }

    private func rename(to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        pushUndo()
        doc.title = trimmed
        doc.root.update(id: doc.root.id) { if $0.text.isEmpty { $0.text = trimmed } }
        save()
        reloadEntries()
        toast = _L("已重命名", "Renamed")
    }

    private func deleteCurrent() {
        guard let name else { return }
        _ = MindMapStore.delete(store.notesDir, name: name)
        reloadEntries()
        if let first = entries.first {
            open(first.name)
        } else {
            self.name = MindMapStore.create(store.notesDir, title: _L("新导图", "New map"))
            reloadEntries()
            self.name.flatMap(open)
        }
    }

    private func save() {
        guard let name else { return }
        _ = MindMapStore.save(store.notesDir, name: name, doc: doc)
    }

    @State private var pendingSave: DispatchWorkItem?

    /// 输入框连续改字时不要每次都写盘
    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem {
            doc.updated = MindMapDocument.now()
            save()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    // MARK: - 撤销

    private func pushUndo() {
        undoStack.append(doc)
        if undoStack.count > 60 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    @State private var lastThrottle = Date.distantPast

    /// 连续输入场景：0.8 秒内的多次修改只记一次撤销点
    private func pushUndoThrottled() {
        let now = Date()
        if now.timeIntervalSince(lastThrottle) > 0.8 { pushUndo() }
        lastThrottle = now
    }

    private func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(doc)
        doc = last
        save()
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(doc)
        doc = next
        save()
    }

    /// 统一的「改 + 存 + 可撤销」
    private func mutate(_ body: (inout MindMapDocument) -> Void) {
        pushUndo()
        body(&doc)
        doc.updated = MindMapDocument.now()
        save()
    }

    // MARK: - 节点操作（键盘与菜单共用）

    private func addChild(to id: String) {
        let node = MindMapNode(text: _L("新节点", "New node"))
        mutate { $0.root.insert(node, parentID: id) }
        selectedID = node.id
    }

    private func addSibling(after id: String) {
        guard let parent = doc.root.parentID(of: id),
              let siblings = doc.root.node(id: parent)?.children,
              let index = siblings.firstIndex(where: { $0.id == id }) else { return }
        let node = MindMapNode(text: _L("新节点", "New node"))
        mutate { $0.root.insert(node, parentID: parent, at: index + 1) }
        selectedID = node.id
    }

    private func deleteNode(_ id: String) {
        guard id != doc.root.id else { return }
        let parent = doc.root.parentID(of: id)
        mutate { _ = $0.root.remove(id: id) }
        selectedID = parent ?? doc.root.id
    }

    /// 提升一级：挂到爷爷下面，排在父亲之后
    private func outdent() {
        guard let id = selectedID, id != doc.root.id,
              let parent = doc.root.parentID(of: id),
              let grand = doc.root.parentID(of: parent),
              let siblings = doc.root.node(id: grand)?.children,
              let index = siblings.firstIndex(where: { $0.id == parent }) else { return }
        mutate { _ = $0.root.move(id: id, toParent: grand, at: index + 1) }
    }

    private func setCollapsedAll(_ collapsed: Bool) {
        func apply(_ node: inout MindMapNode, isRoot: Bool) {
            if !isRoot { node.collapsed = collapsed && !node.children.isEmpty }
            for i in node.children.indices { apply(&node.children[i], isRoot: false) }
        }
        mutate { apply(&$0.root, isRoot: true) }
    }

    // MARK: - 视图缩放

    private func zoomBy(_ factor: CGFloat) {
        zoom = min(3, max(0.2, zoom * factor))
    }

    private func fit() {
        let boxes = layout.boxes
        guard !boxes.isEmpty else { return }
        let bounds = MindMapLayout.bounds(boxes).insetBy(dx: -60, dy: -60)
        let available = CGSize(width: 1180 - 272 - 40, height: 780 - 120)
        let scale = min(available.width / max(bounds.width, 1), available.height / max(bounds.height, 1))
        zoom = min(2, max(0.2, scale))
        offset = CGSize(width: (1180 - 272) / 2 - bounds.midX * zoom,
                        height: (780 - 100) / 2 - bounds.midY * zoom)
    }

    // MARK: - 与笔记互通

    private func importOutline() {
        guard let id = store.loadedNoteID,
              let text = try? String(contentsOf: store.noteURL(id), encoding: .utf8),
              let root = MindMapOutline.parse(markdown: text) else {
            toast = _L("当前笔记里没找到大纲（先写几个标题或列表）", "No outline found in the current note")
            return
        }
        mutate { $0.root = root; $0.title = store.currentTitle.isEmpty ? $0.title : store.currentTitle }
        selectedID = doc.root.id
        fit()
        toast = _L("已从当前笔记生成导图", "Imported outline from note")
    }

    private func exportOutline() {
        let md = MindMapOutline.markdown(doc.root)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(doc.title).md"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try md.write(to: url, atomically: true, encoding: .utf8)
            toast = _L("已导出大纲", "Outline exported")
        } catch {
            toast = _L("导出失败", "Export failed")
        }
    }

    // MARK: - 导出 PNG

    private func exportPNG(scale: CGFloat, transparent: Bool) {
        let content = MindMapExportCanvas(boxes: layout.boxes, edges: layout.edges)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        renderer.isOpaque = !transparent
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            toast = _L("导出失败", "Export failed")
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(doc.title).png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try png.write(to: url)
            toast = _L("已导出 PNG（\(Int(scale))x）", "PNG exported")
        } catch {
            toast = _L("导出失败", "Export failed")
        }
    }

    // MARK: - 键盘 / 滚轮

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKey(event) ? nil : event
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            // ⌘ + 滚轮 = 无极缩放；普通滚轮 = 平移
            if event.modifierFlags.contains(.command) {
                let factor = 1 + event.scrollingDeltaY * 0.01
                zoom = min(3, max(0.2, zoom * factor))
                return nil
            }
            offset = CGSize(width: offset.width - event.scrollingDeltaX,
                            height: offset.height - event.scrollingDeltaY)
            return nil
        }
        magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { event in
            zoom = min(3, max(0.2, zoom * (1 + event.magnification)))
            return nil
        }
    }

    private func removeMonitors() {
        for m in [keyMonitor, scrollMonitor, magnifyMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(m)
        }
        keyMonitor = nil; scrollMonitor = nil; magnifyMonitor = nil
    }

    /// 返回 true = 事件已被导图吃掉
    private func handleKey(_ event: NSEvent) -> Bool {
        // 正在输入框里打字 → 让输入框自己处理（除了 Esc 收工）
        if let responder = NSApp.keyWindow?.firstResponder,
           responder is NSTextView || responder is NSTextField {
            if event.keyCode == 53 { commitEditing(); return true }
            return false
        }
        let cmd = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 48:                                        // Tab
            guard let id = selectedID else { return false }
            if shift { outdent() } else { addChild(to: id) }
            return true
        case 36, 76:                                    // Return / Enter
            guard let id = selectedID else { return false }
            if id == doc.root.id { addChild(to: id) } else { addSibling(after: id) }
            return true
        case 51, 117:                                   // Delete / Forward delete
            guard let id = selectedID, id != doc.root.id else { return false }
            deleteNode(id)
            return true
        case 49:                                        // Space
            guard let id = selectedID else { return false }
            mutate { $0.root.update(id: id) { $0.collapsed.toggle() } }
            return true
        case 123, 124, 125, 126:                        // 方向键
            moveSelection(event.keyCode)
            return true
        case 29:                                        // 0
            if cmd { fit(); return true }
            return false
        case 24, 69:                                    // + / =
            if cmd { zoomBy(1.2); return true }
            return false
        case 27:                                        // -
            if cmd { zoomBy(1 / 1.2); return true }
            return false
        case 6:                                         // Z
            if cmd { shift ? redo() : undo(); return true }
            return false
        default:
            return false
        }
    }

    /// 方向键在树里走：左 = 父，右 = 第一个子，上/下 = 兄弟
    private func moveSelection(_ keyCode: UInt16) {
        guard let id = selectedID else { selectedID = doc.root.id; return }
        switch keyCode {
        case 123:
            if let parent = doc.root.parentID(of: id) { selectedID = parent }
        case 124:
            if let first = doc.root.node(id: id)?.children.first {
                if doc.root.node(id: id)?.collapsed == true {
                    mutate { $0.root.update(id: id) { $0.collapsed = false } }
                }
                selectedID = first.id
            }
        case 125, 126:
            guard let parent = doc.root.parentID(of: id),
                  let siblings = doc.root.node(id: parent)?.children,
                  let index = siblings.firstIndex(where: { $0.id == id }) else { return }
            let next = index + (keyCode == 125 ? 1 : -1)
            if siblings.indices.contains(next) { selectedID = siblings[next].id }
        default:
            break
        }
    }
}

/// 导出用画布：无网格、无选中态，按内容包围盒收紧
struct MindMapExportCanvas: View {
    let boxes: [MindMapBox]
    let edges: [MindMapEdge]

    var body: some View {
        let bounds = MindMapLayout.bounds(boxes).insetBy(dx: -48, dy: -48)
        let shift = CGSize(width: -bounds.minX, height: -bounds.minY)
        Canvas { ctx, _ in
            for edge in edges {
                var path = Path()
                let s = { (p: CGPoint) in CGPoint(x: p.x + shift.width, y: p.y + shift.height) }
                path.move(to: s(edge.from))
                path.addCurve(to: s(edge.to), control1: s(edge.control1), control2: s(edge.control2))
                ctx.stroke(path, with: .color(Color(nsColor: MindMapStyle.branchColor(edge.accent)).opacity(0.55)),
                           style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            }
            for box in boxes {
                let rect = box.rect.offsetBy(dx: shift.width, dy: shift.height)
                MindMapStyle.drawNode(&ctx, box: box, rect: rect, zoom: 1,
                                      selected: false, isDropTarget: false)
            }
        }
        .frame(width: max(bounds.width, 200), height: max(bounds.height, 120))
    }
}

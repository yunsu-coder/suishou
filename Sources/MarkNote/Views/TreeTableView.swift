import SwiftUI
import AppKit

/// 资源管理器树行模型（文件夹 / 文件两种）
enum TreeRow: Identifiable {
    case folder(NoteCategory, count: Int, isOpen: Bool, level: Int)
    case note(NoteIndexItem, level: Int)
    case creating(level: Int)   // 内联命名行（新建文件/文件夹共用）

    var id: String {
        switch self {
        case .folder(let c, _, _, _): return c.id
        case .note(let n, _): return n.id
        case .creating: return "__creating__"
        }
    }
    var isFolder: Bool { if case .folder = self { return true }; return false }
    var isCreating: Bool { if case .creating = self { return true }; return false }
    var level: Int {
        switch self { case .folder(_, _, _, let l): return l; case .note(_, let l): return l; case .creating(let l): return l }
    }
}

/// 原生 NSTableView 侧栏树 —— VS Code 资源管理器机制：
/// 行拖拽排序（同目录）、拖到文件夹行 = 移动分类、双击打开、⇧/⌘ 原生多选、右键菜单
/// 子类化：覆写 menu(for:) 让右键 100% 走我们的构建回调（绕开系统 menu 分发的不确定性）
final class MarkNoteTableView: NSTableView {
    var rowMenuBuilder: ((NSMenu, Int) -> Void)?
    var singleClickCallback: ((String) -> Void)?
    var idForRow: ((Int) -> String?)?
    /// 鼠标按下回调（选中变化是否来自鼠标 → 单击动作判定）
    var mouseDownCallback: (() -> Void)?
    /// hover 行回调（VSCode 式树行微光）
    var hoverRowCallback: ((Int?) -> Void)?

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let row = p.y >= 0 ? row(at: p) : -1
        hoverRowCallback?(row < 0 ? nil : row)
        super.mouseMoved(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        let menu = NSMenu()
        if let rowMenuBuilder {
            rowMenuBuilder(menu, row)
        }
        return menu
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownCallback?()
        super.mouseDown(with: event)
    }
}

/// 无 target-action 桥接代理：NSButton 点击 → 字典路由闭包（AppKit 无 Swift 闭包 selector）
final class ActionProxy: NSObject {
    static let shared = ActionProxy()
    private var actions: [String: () -> Void] = [:]
    func register(_ token: String, _ action: @escaping () -> Void) { actions[token] = action }
    @objc func fire(_ sender: NSButton) {
        if let t = sender.identifier?.rawValue { actions[t]?() }
    }
}

/// 树行视图：VSCode 式行状态着色（选中 = 主题橙 24%、hover = 微光 10%、拖入目标 = 橙 14%）
final class VSCodeTreeRowView: NSTableRowView {
    var hovered = false
    var isDropTarget = false

    /// 主题 accent（随 currentTheme；swift-heavy 转换后为固定色，主题切换经 .id 整体重建重设）
    private let accent = NSColor(currentTheme.accent)

    override func drawSelection(in dirtyRect: NSRect) {
        // 覆盖系统默认选中样式：统一走 drawBackground 自定义着色
        drawBackground(in: dirtyRect)
    }

    override func drawBackground(in dirtyRect: NSRect) {
        if isDropTarget {
            accent.withAlphaComponent(0.15).setFill()
            dirtyRect.fill()
        } else if isSelected {
            accent.withAlphaComponent(0.24).setFill()
            dirtyRect.fill()
        } else if hovered {
            NSColor.tertiaryLabelColor.withAlphaComponent(0.10).setFill()
            dirtyRect.fill()
        }
    }
}

struct TreeTableView: NSViewRepresentable {
    let rows: [TreeRow]
    let selected: Set<String>
    let onSelect: (Set<String>) -> Void
    let onOpen: (String) -> Void
    let onMoveToFolder: (Set<String>, String) -> Void // 拖到文件夹
    let onToggleFolder: (String) -> Void
    let onMenu: (NSMenu, String?) -> Void      // 右键（行 id 可空）
    let onImportFiles: ([URL], String?) -> Void // 外部文件拖入（folderID 可空=根）
    let onCreate: (String, [String: String]) -> Void  // 内联命名提交（名，元数据[target]）
    let onCancelCreate: () -> Void
    /// hover 行内快捷操作（VSCode 式：✎ 重命名 / 🗑 删除）
    let onRename: (String) -> Void
    let onDelete: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .clear

        let delegate = context.coordinator
        let tv = MarkNoteTableView()
        tv.usesAlternatingRowBackgroundColors = false
        tv.allowsMultipleSelection = true
        tv.allowsEmptySelection = true
        tv.rowHeight = 24 // VSCode 树行高
        tv.headerView = nil
        tv.selectionHighlightStyle = .regular
        tv.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        // 树行 hover 微光（VSCode 2% 白/黑）：表格级 trackingArea + 子类 mouseMoved
        let track = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                   owner: tv, userInfo: nil)
        tv.addTrackingArea(track)
        tv.hoverRowCallback = { [weak delegate] row in
            delegate?.setHoveredRow(row, tableView: tv)
        }

        let col = NSTableColumn(identifier: .init("tree"))
        col.resizingMask = .autoresizingMask
        tv.addTableColumn(col)

        tv.delegate = delegate
        tv.dataSource = delegate
        tv.registerForDraggedTypes([NSPasteboard.PasteboardType("com.gzhysu.marknote.row"), .fileURL])
        tv.setDraggingSourceOperationMask(.every, forLocal: true)

        // 单击即动作（selection-didChange 内驱动；mouseDown 标记鼠标来源）
        tv.target = delegate
        tv.mouseDownCallback = { [weak delegate] in
            delegate?.mouseActivated = true
        }
        // 右键菜单：builder 直接桥接构建（任意行/空白）
        tv.rowMenuBuilder = { [weak delegate] menu, row in
            let context = row >= 0 && row < (delegate?.rows.count ?? 0) ? delegate?.rows[row].id : nil
            delegate?.parent.onMenu(menu, context)
        }
        tv.menu = NSMenu()
        // 兼容旧接口引用（双击单开流程已退役）
        tv.idForRow = { [weak delegate] row in
            guard let delegate, row >= 0, row < delegate.rows.count else { return nil }
            if case .note(let n, _) = delegate.rows[row] { return n.id }
            return nil
        }
        tv.singleClickCallback = { [weak delegate] id in
            delegate?.parent.onOpen(id)
        }

        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTableView else { return }
        // 行指纹：内容未变绝不 reload（避免每帧全表重建 → 闪烁/滚动/选择丢失）
        let fingerprint = rows.map { r in r.id + "|" + String(r.level) + (r.isFolder ? "F" : "N") }.joined(separator: ";")
        context.coordinator.rows = rows
        if fingerprint != context.coordinator.lastFingerprint {
            context.coordinator.lastFingerprint = fingerprint
            let selectedRows = tv.selectedRowIndexes
            let visibleY = tv.enclosingScrollView?.contentView.bounds.origin.y
            tv.reloadData()
            // 保留旧选择（内容未变只是增删时尽量靠行号回填）
            if !selectedRows.isEmpty, selectedRows.max().map({ $0 < rows.count }) == true {
                tv.selectRowIndexes(selectedRows, byExtendingSelection: false)
            }
            if let y = visibleY {
                tv.enclosingScrollView?.contentView.scroll(to: NSPoint(x: 0, y: y))
            }
        }
        // 选择高亮重算（以外部 selection 为准；避免每次 update 全量重选）
        let wanted = Set(selected.compactMap { id in rows.firstIndex(where: { $0.id == id }) })
        if wanted != context.coordinator.lastHighlight {
            context.coordinator.lastHighlight = wanted
            tv.selectRowIndexes(IndexSet(wanted), byExtendingSelection: false)
        }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: TreeTableView
        var rows: [TreeRow] = []
        var selectedIDs: Set<String> = []
        var lastHighlight: Set<Int> = []
        var currentSelection: IndexSet?
        var lastFingerprint = ""
        /// 拖拽源行号（写入时记录）
        var draggingRows: IndexSet?
        /// 最近一次选中变化是否由鼠标引发（键盘方向键只选不开）
        var mouseActivated = false
        /// 行尾操作按钮容器（行 hover 显隐）
        var actionViews: [Int: NSStackView] = [:]

        init(_ parent: TreeTableView) {
            self.parent = parent
            super.init()
        }

        // MARK: - DataSource

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        // MARK: - Delegate

        /// 自定义行视图：VSCode 式选中（主题暖橙 24%）/ hover（微光）/ 拖入目标高亮 —— 替代系统蓝
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let v = VSCodeTreeRowView()
            v.hovered = (row == hoveredRow)
            v.isDropTarget = (row == dropTargetRow)
            return v
        }

        var hoveredRow: Int? = nil
        func setHoveredRow(_ row: Int?, tableView: NSTableView) {
            guard row != hoveredRow else { return }
            let old = hoveredRow
            hoveredRow = row
            if let old, old < rows.count, let v = tableView.rowView(atRow: old, makeIfNecessary: false) as? VSCodeTreeRowView {
                v.hovered = false
                v.needsDisplay = true
            }
            if let row, row < rows.count, let v = tableView.rowView(atRow: row, makeIfNecessary: false) as? VSCodeTreeRowView {
                v.hovered = true
                v.needsDisplay = true
            }
            // 行尾操作按钮显隐
            if let old { actionViews[old]?.alphaValue = 0 }
            if let row { actionViews[row]?.alphaValue = 1 }
        }

        /// 行尾小图标按钮（SF Symbol；target-action 桥接闭包）
        static func actionButton(_ symbol: String, help: String, action: @escaping () -> Void) -> NSButton {
            let b = NSButton()
            b.isBordered = false
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            b.imagePosition = .imageOnly
            b.toolTip = help
            let token = "\(symbol)-\(UUID().uuidString)"
            b.identifier = NSUserInterfaceItemIdentifier(token)
            b.target = ActionProxy.shared
            b.action = #selector(ActionProxy.fire(_:))
            ActionProxy.shared.register(token, action)
            return b
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < rows.count else { return nil }
            let cell = NSTableCellView()
            let content = NSStackView()
            content.orientation = .horizontal
            content.spacing = 5
            content.edgeInsets = NSEdgeInsets(top: 0, left: CGFloat(rows[row].level) * 16 + 6, bottom: 0, right: 6)
            content.alignment = .centerY

            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingMiddle
            label.font = .systemFont(ofSize: 13)

            if rows[row].isCreating {
                return makeCreateCell(row: row)
            }
            switch rows[row] {
            case .creating:
                return NSView()
            case .folder(let cat, let count, let isOpen, _):
                // VSCode：小 chevron + 彩色 folder 图标 + 名称（计数置尾、齐右）
                let chevron = NSImageView()
                chevron.image = NSImage(systemSymbolName: isOpen ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
                chevron.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .medium)
                chevron.contentTintColor = .tertiaryLabelColor
                content.addArrangedSubview(chevron)
                let folder = NSImageView()
                folder.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
                folder.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
                folder.contentTintColor = Self.colorHex(cat.color) // 分类色 → 图标着色（替代色点）
                content.addArrangedSubview(folder)
                label.stringValue = cat.name
            case .note(let n, _):
                let (iconName, tint) = Self.fileIcon(for: n.id)
                let doc = NSImageView()
                doc.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
                doc.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
                doc.contentTintColor = tint
                content.addArrangedSubview(doc)
                // VSCode 惯例：树行显示完整文件名（含扩展名）；id = 相对路径
                let displayName = n.id.isEmpty ? _L("无标题", "Untitled") : (n.id as NSString).lastPathComponent
                label.stringValue = displayName.isEmpty ? _L("无标题", "Untitled") : displayName
            }

            content.addArrangedSubview(label)
            // 计数置尾（齐右、微淡 —— VSCode 轻样式；不使用则行尾留白）
            if case .folder(_, let count, _, _) = rows[row], count > 0 {
                let c = NSTextField(labelWithString: "\(count)")
                c.font = .systemFont(ofSize: 11)
                c.textColor = .tertiaryLabelColor
                c.setContentHuggingPriority(.required, for: .horizontal)
                content.addArrangedSubview(c)
            }
            // hover 行内快捷操作（✎ / 🗑）；默认隐藏，hover 显示
            if !rows[row].isCreating {
                let actions = NSStackView()
                actions.orientation = .horizontal
                actions.spacing = 4
                actions.setHuggingPriority(.required, for: .horizontal)
                let idForAction = rows[row].id
                let renameB = Self.actionButton("pencil", help: _L("重命名", "Rename")) { [weak self] in
                    self?.parent.onRename(idForAction)
                }
                let delB = Self.actionButton("trash", help: _L("删除", "Delete")) { [weak self] in
                    self?.parent.onDelete(idForAction)
                }
                actions.addArrangedSubview(renameB)
                actions.addArrangedSubview(delB)
                actions.alphaValue = row == hoveredRow ? 1.0 : 0.0
                content.addArrangedSubview(actions)
                actionViews[row] = actions
            }
            content.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                content.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                content.heightAnchor.constraint(equalToConstant: 22),
            ])
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTableView else { return }
            currentSelection = tv.selectedRowIndexes
            let ids = Set(tv.selectedRowIndexes.compactMap { $0 < rows.count ? rows[$0].id : nil })
            parent.onSelect(ids)
            // 单击即动作（VSCode）：单选且由鼠标触发 → 文件夹折叠/展开、文件打开
            if mouseActivated, ids.count == 1, let row = tv.selectedRowIndexes.first, row < rows.count {
                switch rows[row] {
                case .folder(let cat, _, _, _):
                    parent.onToggleFolder(cat.id)
                case .note(let n, _):
                    parent.onOpen(n.id)
                case .creating:
                    break
                }
            }
            mouseActivated = false
        }

        @objc func doubleClicked(_ sender: Any?) {
            guard let tv = sender as? NSTableView else { return }
            let row = tv.clickedRow
            guard row >= 0, row < rows.count else { return }
            switch rows[row] {
            case .folder(let cat, _, let open, _):
                parent.onToggleFolder(cat.id)
            case .note(let n, _):
                parent.onOpen(n.id)
            case .creating:
                break
            }
        }

        // MARK: - 内联命名行（新建文件/文件夹）

        private func makeCreateCell(row: Int) -> NSView? {
            let cell = NSTableCellView()
            let field = CommitField(frame: .zero)
            field.placeholderString = _L("输入名称，回车创建…", "Enter a name and press Return to create…")
            field.font = .systemFont(ofSize: 13)
            field.isBezeled = true
            field.bezelStyle = .roundedBezel
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(field)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: CGFloat(rows[row].level) * 18 + 12),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                field.heightAnchor.constraint(equalToConstant: 22),
            ])
            // 提交统一走 delegate（回车/失焦=创建；Esc=取消）
            field.delegate = field
            field.onCommit = { [weak self] name in
                self?.parent.onCreate(name, [:])
            }
            field.onCancel = { [weak self] in
                self?.parent.onCancelCreate()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { field.becomeFirstResponder() }
            return cell
        }

        // MARK: - 上下文菜单

        func tableView(_ tableView: NSTableView, menuForRow row: Int) -> NSMenu? {
            let context = row >= 0 && row < rows.count ? rows[row].id : nil
            let menu = NSMenu()
            parent.onMenu(menu, context)
            return menu
        }

        // MARK: - 拖拽（VS Code 资源管理器：行本地拖拽；禁止再实现 pasteboardWriterForRow —— 它会抢占 writeRowsWith，导致 draggingRows=nil、移动静默失败）

        func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pboard: NSPasteboard) -> Bool {
            draggingRows = rowIndexes
            pboard.declareTypes([Self.rowType], owner: nil)
            let ids = rowIndexes.compactMap { $0 < rows.count ? rows[$0].id : nil }
            pboard.setPropertyList(ids, forType: Self.rowType)
            return true
        }

        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            if info.draggingPasteboard.availableType(from: [.fileURL]) != nil {
                return .copy // 外部文件拖入（文件夹行=导入；其余=根导入）
            }
            // 本地行拖拽：悬停在文件夹行 → 强制 .on 落点 + 行高亮（VSCode 文件夹叶高亮）
            if row >= 0, row < rows.count, case .folder = rows[row] {
                tableView.setDropRow(row, dropOperation: .on)
                setDropTarget(row, tableView: tableView)
                return .move
            }
            setDropTarget(nil, tableView: tableView)
            return .move
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            setDropTarget(nil, tableView: tableView)
            // 外部文件 → 按落点导入（folder 行=该分类；其余=根目录）
            if info.draggingPasteboard.availableType(from: [.fileURL]) != nil {
                let catID: String?
                if dropOperation == .on, row >= 0, row < rows.count, case .folder(let cat, _, _, _) = rows[row] {
                    catID = cat.id
                } else {
                    catID = nil
                }
                let urls = info.draggingPasteboard.readObjects(
                    forClasses: [NSURL.self],
                    options: [.urlReadingFileURLsOnly: true]
                ) as? [URL] ?? []
                parent.onImportFiles(urls, catID)
                return true
            }
            // 本地行：ids 优先取内存（writeRowsWith 写入），回退剪贴板（拖出后 delegate 重载的边界情况）
            let ids: Set<String>
            if let source = draggingRows {
                ids = Set(source.compactMap { $0 < rows.count ? rows[$0].id : nil })
                draggingRows = nil
            } else {
                ids = Set(info.draggingPasteboard.propertyList(forType: Self.rowType) as? [String] ?? [])
            }
            guard !ids.isEmpty else { return false }
            // 落点为文件夹行 → 移动（.on 与 .above 均视为移动意图）
            if row >= 0, row < rows.count, case .folder(let cat, _, _, _) = rows[row] {
                parent.onMoveToFolder(ids, cat.id)
                return true
            }
            return false
        }

        // MARK: - 落点高亮

        /// 当前作为「拖入目标」的文件夹行（vscode 式叶高亮）
        var dropTargetRow: Int? = nil

        func setDropTarget(_ row: Int?, tableView: NSTableView) {
            guard row != dropTargetRow else { return }
            let old = dropTargetRow
            dropTargetRow = row
            for r in old.map { [$0] } ?? [] {
                if let v = tableView.rowView(atRow: r, makeIfNecessary: false) as? VSCodeTreeRowView {
                    v.isDropTarget = false
                    v.needsDisplay = true
                }
            }
            if let row {
                if let v = tableView.rowView(atRow: row, makeIfNecessary: false) as? VSCodeTreeRowView {
                    v.isDropTarget = true
                    v.needsDisplay = true
                }
            }
        }

        static let rowType = NSPasteboard.PasteboardType("com.gzhysu.marknote.row")

        /// 文件扩展名 → 图标 + 主题色（SF Symbols：VSCode 式视觉分级）
        static func fileIcon(for id: String) -> (String, NSColor) {
            let ext = (id as NSString).pathExtension.lowercased()
            let tint = NSColor(named: "controlAccentColor") ?? .controlAccentColor
            func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
                NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
            }
            switch ext {
            case "md", "markdown", "mdown": return ("doc.text", c(0.45, 0.55, 0.68))
            case "txt": return ("doc.plaintext", c(0.55, 0.55, 0.60))
            case "png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff", "svg", "ico": return ("photo", c(0.30, 0.62, 0.52))
            case "pdf": return ("doc.richtext", c(0.82, 0.32, 0.30))
            case "mp4", "mov", "m4v", "mkv", "avi", "webm": return ("film", c(0.62, 0.42, 0.78))
            case "mp3", "m4a", "wav", "aac", "ogg", "flac": return ("waveform", c(0.90, 0.45, 0.62))
            case "xls", "xlsx", "csv", "numbers", "ods": return ("tablecells", c(0.28, 0.62, 0.40))
            case "ppt", "pptx", "key", "odp": return ("play.rectangle", c(0.90, 0.55, 0.25))
            case "zip", "rar", "7z", "gz", "tar", "dmg": return ("archivebox", c(0.50, 0.54, 0.66))
            case "py", "js", "ts", "swift", "rb", "go", "rs", "java", "c", "cpp", "h",
                 "cs", "php", "sh", "sql": return ("curlybraces", c(0.32, 0.50, 0.78))
            default: return ("doc", c(0.58, 0.58, 0.62))
            }
        }

        private static func colorHex(_ hex: String) -> NSColor {
            var h = hex.replacingOccurrences(of: "#", with: "")
            if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
            guard h.count == 6, let v = UInt64(h, radix: 16) else { return .controlAccentColor }
            return NSColor(calibratedRed: CGFloat((v >> 16) & 0xFF) / 255,
                           green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
    }
}

/// 内联命名输入框：**失去焦点即创建**（回车/点击别处=提交）；Esc=取消
final class CommitField: NSTextField {
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var cancelled = false

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {              // Esc → 取消
            cancelled = true
            window?.makeFirstResponder(nil)
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }
}

extension CommitField: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        // 回车与失焦都走到这里 → 统一"提交创建"（Esc 已置 cancelled 跳过）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self else { return }
            if !self.cancelled {
                let name = self.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    self.onCommit?(name)
                } else {
                    self.onCancel?()
                }
            }
            self.cancelled = false
        }
    }
}

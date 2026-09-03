import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 分类 #RRGGBB → Color（兼容 3 位色口）
private func colorFromHex(_ hex: String) -> Color {
    var h = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
    if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
    guard h.count == 6, let v = UInt64(h, radix: 16) else { return .accentColor }
    return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}

/// 侧边栏 —— VSCode 式结构：左活动条（文件/回收站）+ 右侧面板
/// 强逻辑性：一个图标一个面板；简单：收起一切次要入口
struct SidebarView: View {
    @Environment(NotesStore.self) private var store
    @Binding var showVersions: Bool

    // 文件面板状态
    @State private var renameTarget: NoteIndexItem?
    @State private var renameText = ""
    @State private var deleteTarget: NoteIndexItem?
    @State private var newCategoryText = ""
    @State private var showNewCategory = false
    @State private var categoryManageTarget: NoteCategory?
    /// 内联命名创建目标："=root" 文件 / "=category" 文件夹 / 分类 id（文件夹内文件）
    @State private var creatingTarget: String?
    @State private var dropping = false
    /// 折叠目录集：启动默认折叠 source（资源库不打扰浏览）；变更持久化
    @State private var collapsedGroups: Set<String> = []
    static let collapsKey = "foldedDirs"
    /// 「打开的编辑器」区折叠态（VSCode OPEN EDITORS）
    // 导入（目标选择 / 文件夹拖拽高亮）
    @State private var importPending: [URL] = []
    @State private var showImportTarget = false
    @State private var folderDropCandidate: String?

    /// 左侧竖向功能栏面板
    enum SidePanel: String {
        case workspace, market
    }

    @State private var panel: SidePanel = .workspace

    @State private var showMarket = false

    var body: some View {
        HStack(spacing: 0) {
            // VSCode 式竖向功能栏：工作台 / 插件市场（宽面板）/ 设置（底部）
            VStack(spacing: 3) {
                activityIcon("folder", _L("工作台", "Workspace"), active: true) {
                    // 工作台即当前面板
                }
                activityIcon("puzzlepiece.extension", _L("插件市场", "Plugin Market"), active: false) {
                    PluginManager.shared.scan(workspaceDir: store.notesDir)
                    showMarket = true
                }
                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.clear))
                }
                .buttonStyle(.plain)
                .help(_L("设置", "Settings"))
            }
            .padding(.top, 26)   // 避让交通灯（hiddenTitleBar）
            .padding(.bottom, 8)
            .frame(width: 36)
            .background(.quaternary.opacity(0.35))

            Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)

            notesPanel
                .environment(store)
        }
        .frame(minWidth: 110, idealWidth: 170, maxWidth: 420)
        // 插件市场：居中宽面板（网格 + 详情，App Store 风格）
        .sheet(isPresented: $showMarket) {
            PluginMarketView()
                .environment(store)
        }
        .onAppear {
            if let data = UserDefaults.standard.data(forKey: Self.collapsKey),
               let saved = try? JSONDecoder().decode([String].self, from: data) {
                collapsedGroups = Set(saved)
            }
            // 首次：默认折叠 source 资源库（不打扰浏览）
            if collapsedGroups.isEmpty {
                collapsedGroups = ["source"]
            }
            persistFoldState()
        }
        .onChange(of: collapsedGroups) { _, _ in
            persistFoldState()
        }
        .alert(_LL("新建文件夹", "New Folder"), isPresented: $showNewCategory) {
            TextField(_LL("文件夹名", "Folder Name"), text: $newCategoryText)
            Button(_LL("创建", "Create")) {
                if !store.createCategory(newCategoryText) {
                    store.showHint(_L("已存在同名文件夹", "A folder with the same name already exists"))
                }
                newCategoryText = ""
            }
            Button(_LL("取消", "Cancel"), role: .cancel) { newCategoryText = "" }
        } message: {
            Text(_LL("文件夹 = 分类，文件可拖入或右键移动", "Folders are categories; drag files in or right-click to move them"))
        }
        .alert(_LL("重命名文件夹", "Rename Folder"), isPresented: Binding<Bool>(
            get: { categoryManageTarget != nil },
            set: { if !$0 { categoryManageTarget = nil } }
        )) {
            TextField(_LL("文件夹名", "Folder Name"), text: $newCategoryText)
            Button(_LL("确定", "OK")) {
                if let t = categoryManageTarget {
                    if !store.renameCategory(t.id, to: newCategoryText) {
                        store.showHint(_L("已存在同名文件夹", "A folder with the same name already exists"))
                    }
                }
                categoryManageTarget = nil
            }
            Button(_LL("取消", "Cancel"), role: .cancel) { categoryManageTarget = nil }
        }
        // 命令面板转发：新建文件夹 / 导入
        .onReceive(NotificationCenter.default.publisher(for: .requestNewNote)) { _ in
            beginCreating("=root")
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestNewCategory)) { _ in
            beginCreating("=category")
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestImportFiles)) { _ in
            pickImportFiles(directories: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestImportFolder)) { _ in
            pickImportFiles(directories: true)
        }
        .sheet(isPresented: $showImportTarget) {
            ImportTargetSheet(files: importPending) {
                store.importFiles(urls: importPending, category: $0)
                importPending = []
            }
            .environment(store)
        }
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(currentTheme.accent, lineWidth: 2)
                    .padding(4)
                    .overlay {
                        Label(_LL("拖入导入为新文件", "Drop to import as new file"), systemImage: "square.and.arrow.down")
                            .font(.callout)
                            .foregroundStyle(currentTheme.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropping) { providers in
            var ok = false
            for p in providers {
                if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    p.loadObject(ofClass: NSURL.self) { obj, _ in
                        if let url = obj as? URL {
                            DispatchQueue.main.async {
                                // 文件夹 → 递归导入（子目录自动成分类）；文件 → 文本导入治理 / 非文本原始放入
                                if url.hasDirectoryPath {
                                    _ = store.importFolder(url)
                                } else {
                                    if store.importDroppedFile(from: url, into: nil) == nil {
                                        store.showHint(_L("无法导入：\(url.lastPathComponent)", "Cannot import: \(url.lastPathComponent)"))
                                    }
                                }
                            }
                        }
                    }
                    ok = true
                }
            }
            return ok
        }
        .alert(_LL("重命名文件", "Rename File"), isPresented: Binding<Bool>(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField(_LL("标题", "Title"), text: $renameText)
            Button(_LL("确定", "OK")) {
                if let t = renameTarget {
                    if !store.renameNote(t.id, to: renameText) {
                        store.showHint(_L("该文件夹下已存在同名文件", "A file with the same name already exists in this folder"))
                    }
                }
                renameTarget = nil
            }
            Button(_LL("取消", "Cancel"), role: .cancel) { renameTarget = nil }
        } message: {
            Text(_LL("修改文件标题", "Edit file title"))
        }
        .confirmationDialog(
            _LL("删除文件？", "Delete File?"),
            isPresented: Binding<Bool>(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            presenting: deleteTarget
        ) { item in
            Button(_LL("删除", "Delete"), role: .destructive) { store.deleteNote(item.id) }
            Button(_LL("取消", "Cancel"), role: .cancel) {}
        } message: { item in
            Text(_L("“\(item.title.isEmpty ? "无标题" : item.title)”将被物理删除（无法撤销）", "“\(item.title.isEmpty ? "Untitled" : item.title)” will be permanently deleted (cannot be undone)"))
        }
    }

    private var explorerSearch: some View {
        @Bindable var store = store
        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
            TextField(_L("搜索文件", "Search Files"), text: $store.searchQuery)
                .textFieldStyle(.plain)
                .font(.callout)
                .onSubmit { store.filteredIndex.first.map { store.openNote($0.id) } }
                .onKeyPress(.escape) {
                    store.searchQuery = ""
                    return .handled
                }
            if !store.searchQuery.isEmpty {
                Button {
                    store.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(_L("清空搜索 (Esc)", "Clear Search (Esc)"))
            }
        }
        .padding(.vertical, 5)
    }

    // ── 文件面板（VSCode 资源管理器：标题行 + 搜索 + 文件夹树） ──
    private var notesPanel: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 26)   // 避让交通灯（hiddenTitleBar），与活动条对齐
            viewTitleRow
            explorerSearch
            Divider()
            workspaceHeader
            explorerTree
            footer
        }
    }

    /// 视图标题行（VSCode "EXPLORER"）：小号加粗标题 + 右端 ⋯ 更多操作菜单
    private var viewTitleRow: some View {
        HStack(spacing: 6) {
            Text(_LL("资源管理器", "Explorer"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
            Spacer()
            Menu {
                Button(_L("新建文件", "New Note")) { beginCreating("=root") }
                Button(_L("新建文件夹", "New Folder")) { beginCreating("=category") }
                Divider()
                Button(_L("展开全部", "Expand All")) { collapsedGroups.removeAll() }
                Button(_L("折叠全部", "Collapse All")) { collapsedGroups = Set(store.categories.map(\.id)) }
                Divider()
                Button(_L("导入文件…", "Import Files…")) { pickImportFiles(directories: false) }
                Button(_L("导入到指定文件夹…", "Import to a Specified Folder…")) { pickImportFiles(directories: false, needsTarget: true) }
                Button(_L("导入文件夹…", "Import Folder…")) { pickImportFiles(directories: true) }
                Divider()
                Button(_L("移除空文件夹", "Remove Empty Folders")) { store.removeEmptyCategories() }
                Button(_L("在 Finder 中显示目录", "Show in Finder")) { NSWorkspace.shared.open(store.notesDir) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22, height: 18)
            .help(_L("更多操作", "More Options"))
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 5)
    }

    /// 工作区区块头（VSCode "WORKSPACE"）：chevron + 小号标题 + hover 时的行内动作（新建/折叠/刷新）
    @State private var workspaceHover = false
    private var workspaceHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            // 工作台目录名（如 origin）替代固定的"文件/File"文本
            Text(store.notesDir.lastPathComponent)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
            Spacer()
            if workspaceHover {
                Button {
                    beginCreating("=root")
                } label: {
                    Image(systemName: "doc.badge.plus")
                }
                .buttonStyle(.borderless)
                .help(_L("新建文件", "New Note"))
                Button {
                    beginCreating("=category")
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .help(_L("新建文件夹", "New Folder"))
                Button {
                    collapsedGroups = Set(store.categories.map(\.id))
                } label: {
                    Image(systemName: "square.3.layers.3d.down.right")
                }
                .buttonStyle(.borderless)
                .help(_L("折叠全部", "Collapse All"))
                Button {
                    store.reloadIndex()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help(_L("刷新", "Refresh"))
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .onHover { workspaceHover = $0 }
    }

    /// 折叠态持久化（UserDefaults JSON）
    private func persistFoldState() {
        if let data = try? JSONEncoder().encode(collapsedGroups.sorted()) {
            UserDefaults.standard.set(data, forKey: Self.collapsKey)
        }
    }

    /// 删除撤销浮动条（6 秒自动消失）
    private var undoToast: some View {
        Group {
            if store.showUndoToast {
                HStack(spacing: 8) {
                    Text(_LL("已删除", "Deleted"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(_L("撤销", "Undo")) { store.undoDelete() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(currentTheme.accent.opacity(0.10))
                .overlay(alignment: .top) { Divider() }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: store.showUndoToast)
    }


    // MARK: - 导入选择（文件/文件夹 → 可选目标）

    private func pickImportFiles(directories: Bool, needsTarget: Bool = false) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = directories
        panel.canChooseFiles = true
        panel.message = directories ? _L("选择要导入的文件夹（内部文件与子文件夹将自动入库）", "Choose a folder to import (its files and subfolders are added automatically)")
                                    : _L("选择要导入的 Markdown / 文本文件（可多选）", "Choose Markdown / text files to import (multiple selection allowed)")
        let mdType = UTType(filenameExtension: "md") ?? .plainText
        panel.allowedContentTypes = directories ? [.folder] : [mdType, .plainText]
        if panel.runModal() == .OK {
            var toImport: [URL] = []
            if directories {
                for url in panel.urls where url.hasDirectoryPath {
                    let n = store.importFolder(url)
                    store.showHint(_L("已导入 \(n) 篇（文件夹“\(url.lastPathComponent)”）", "Imported \(n) notes (folder “\(url.lastPathComponent)”)"))
                }
            } else {
                toImport = panel.urls
            }
            if !toImport.isEmpty {
                if needsTarget {
                    importPending = toImport
                    showImportTarget = true
                } else {
                    let n = store.importFiles(urls: toImport, category: nil)
                    store.showHint(_L("已导入 \(n) 篇文件", "Imported \(n) notes"))
                }
            }
        }
    }

    /// 拖拽文件到文件夹行 → 导入到该分类
    private func importDroppedToFolder(_ providers: [NSItemProvider], categoryID: String) -> Bool {
        var ok = false
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            p.loadObject(ofClass: NSURL.self) { obj, _ in
                if let url = obj as? URL {
                    DispatchQueue.main.async {
                        if url.hasDirectoryPath {
                            _ = store.importFolder(url)
                        } else {
                            // 文本→导入治理；MP4/PDF 等→原始文件放入该文件夹
                            if store.importDroppedFile(from: url, into: categoryID) == nil {
                                store.showHint(_L("无法放入文件：\(url.lastPathComponent)", "Can't place file: \(url.lastPathComponent)"))
                            }
                        }
                    }
                }
            }
            ok = true
        }
        return ok
    }

    // MARK: - 内联命名（先命名再创建，VSCode 新建文件心法）

    /// 文件夹树（VSCode 文件管理器）：
    /// - 根 = 全部文件；未归档文件直接显示在根下（无"未分类"组）
    /// - 文件夹在前、根文件在后（时间排序模式）；手动排序返回整体平铺（顺序=order.json）
    /// - 搜索时变为平铺命中结果
    private var explorerTree: some View {
        var rows = store.treeRows(openFolders: collapsedGroups)
        // 内联命名行注入（根区 = 顶部；文件夹内 = 子树顶）
        if let target = creatingTarget {
            let level = (target == "=root" || target == "=category") ? 0 : 1
            if target == "=root" || target == "=category" {
                rows.insert(.creating(level: 0), at: 0)
            } else if let i = rows.firstIndex(where: { $0.id == target }) {
                let level = rows[i].level + 1
                rows.insert(.creating(level: level), at: i + 1)
            }
        }
        let rowsSnapshot = rows // 供闭包捕获
        return TreeTableView(
            rows: rows,
            selected: store.selectedNoteIDs,
            onSelect: { store.selectedNoteIDs = $0 },
            onOpen: { store.openNote($0) },

            onMoveToFolder: { ids, catID in
                for id in ids { store.moveNoteFlat(id, to: catID) }
            },
            onToggleFolder: { id in
                if collapsedGroups.contains(id) { collapsedGroups.remove(id) }
                else { collapsedGroups.insert(id) }
            },
            onMenu: { menu, rowID in buildContextMenu(menu, rowID: rowID) },
            onImportFiles: { urls, folderID in
                guard !urls.isEmpty else { return }
                if let folderID, !folderID.isEmpty {
                    // 文件夹行：直接归入目标分类
                    store.importFiles(urls: urls, category: folderID)
                } else {
                    // 根区域：治理导入
                    for url in urls {
                        if url.hasDirectoryPath { _ = store.importFolder(url) }
                        else { _ = store.importNote(from: url) }
                    }
                }
            },
            onCreate: { name, _ in
                guard !name.isEmpty else { creatingTarget = nil; return }
                switch creatingTarget {
                case "=root":
                    _ = store.createNote(title: name, category: "")
                case "=category":
                    _ = store.createCategory(name)
                case .some(let catID):
                    _ = store.createNote(title: name, category: catID)
                case nil:
                    break
                }
                creatingTarget = nil
            },
            onCancelCreate: {
                creatingTarget = nil
            },
            onRename: { id in
                if let item = store.index.first(where: { $0.id == id }) {
                    renameTarget = item
                }
            },
            onDelete: { id in
                if let item = store.index.first(where: { $0.id == id }) {
                    deleteTarget = item
                }
            }
        )
    }

    /// 进入内联命名创建：目标 （"=root" / "=category" / 文件夹 id）
    private func beginCreating(_ target: String) {
        creatingTarget = target
        if target != "=root", target != "=category" {
            collapsedGroups.remove(target) // 目标文件夹自动展开
        }
    }

    /// SwiftUI 状态 → NSMenu（右键菜单，动作桥接回现有逻辑）
    private func buildContextMenu(_ menu: NSMenu, rowID: String?) {
        guard let rowID else {
            menu.addItem(item(_L("新建文件", "New Note"), { beginCreating("=root") }))
            menu.addItem(.separator())
            menu.addItem(item(_L("新建文件夹", "New Folder"), { beginCreating("=category") }))
            return
        }
        if let row = store.index.first(where: { $0.id == rowID }) {
            menu.addItem(item(_L("打开", "Open"), { store.openNote(rowID) }))
            menu.addItem(item(_L("AI 改标题…", "AI Retitle…"), {
                store.autoTitle(for: rowID)
            }))
            menu.addItem(.separator())
            menu.addItem(item(_L("重命名…", "Rename…"), {
                renameTarget = row
                renameText = row.title
            }))
            let moveMenu = NSMenu()
            for cat in store.categories {
                moveMenu.addItem(item(cat.name, { store.assignCategory(rowID, cat.id) }))
            }
            let moveItem = NSMenuItem(title: _L("移动到文件夹", "Move to Folder"), action: nil, keyEquivalent: "")
            moveItem.submenu = moveMenu
            menu.addItem(moveItem)
            menu.addItem(.separator())
            menu.addItem(item(_L("删除…", "Delete…"), { deleteTarget = row }))
        } else if let cat = store.categories.first(where: { $0.id == rowID }) {
            menu.addItem(item(_L("重命名文件夹…", "Rename Folder…"), { categoryManageTarget = cat }))
            menu.addItem(item(_L("新建文件到此文件夹", "New Note in This Folder"), { beginCreating(cat.id) }))
            menu.addItem(.separator())
            menu.addItem(item(_L("删除文件夹（文件移到根目录）", "Delete Folder (Files Move to Root)"), { store.deleteCategory(cat.id) }))
        }
    }

    private func item(_ title: String, _ action: @escaping () -> Void) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: #selector(MenuActionHandler.run(_:)), keyEquivalent: "")
        mi.target = MenuActionHandler.shared   // 关键：不指定 target 时菜单项按响应链找 action → 找不到即置灰
        mi.representedObject = action
        return mi
    }

/// 无 target-action 菜单桥接（NSMenuItem → 闭包）
private final class MenuActionHandler: NSObject {
    static let shared = MenuActionHandler()
    @objc func run(_ sender: NSMenuItem) {
        (sender.representedObject as? () -> Void)?()
    }
}

    // 分类弹窗（新建/重命名）挂根视图
    @ViewBuilder
    private func rowMenu(_ item: NoteIndexItem) -> some View {
        Button(_L("打开", "Open")) { store.openNote(item.id) }
        Divider()
        Button(_L("重命名…", "Rename…")) {
            renameTarget = item
            renameText = item.title
        }
        Menu(_L("移动到文件夹", "Move to Folder")) {
            ForEach(store.categories) { cat in
                Button(cat.name) {
                    if !store.assignCategory(item.id, cat.id) {
                        store.showHint(_L("该文件夹下已存在同名文件", "A file with the same name already exists in this folder"))
                    }
                }
            }
        }
        Divider()
        Button(_L("删除…", "Delete…"), role: .destructive) { deleteTarget = item }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(store.notesDir.path)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(_L("文件存储目录", "Note Storage Directory"))
            Spacer()
            if !store.searchQuery.isEmpty {
                Text(_LL("\(store.filteredIndex.count) / \(store.index.count) 匹配", "\(store.filteredIndex.count) / \(store.index.count) Matching"))
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
                    .monospacedDigit()
            } else {
                Text(_LL("\(store.filteredIndex.count) 篇", "\(store.filteredIndex.count) Notes"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .overlay(alignment: .top) { Divider() }
    }
}

/// 导入目标选择 Sheet（文件 → 根/文件夹）
struct ImportTargetSheet: View {
    @Environment(NotesStore.self) private var store
    let files: [URL]
    let onImport: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String = ""   // "" = 根目录

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(_LL("导入 \(files.count) 个文件到…", "Import \(files.count) files to…"))
                    .font(.headline)
                Spacer()
            }
            .padding(16)
            Divider()
            Picker(selection: $selected) {
                Text(_LL("根目录（未归档）", "Root (Uncategorized)")).tag("")
                ForEach(store.categories) { cat in
                    Text(cat.name).tag(cat.id)
                }
            } label: {
                Text(_LL("目标文件夹", "Target Folder"))
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .padding(16)
            Divider()
            HStack {
                Spacer()
                Button(_L("取消", "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(_L("导入", "Import")) {
                    onImport(selected.isEmpty ? nil : selected)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 420, height: 200)
    }
}

/// 单条文件行 —— 分类色点 + 标题/摘要（搜索词高亮）+ 相对时间
private struct NoteRow: View {
    @Environment(NotesStore.self) private var store
    @State private var hover = false
    let item: NoteIndexItem
    let category: NoteCategory?
    let query: String

    private var tokens: [String] {
        query.split(separator: " ").map(String.init).filter { !$0.isEmpty }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Circle()
                .fill(category.map { colorFromHex($0.color) } ?? Color(nsColor: .tertiaryLabelColor))
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    highlightText(item.title.isEmpty ? _L("无标题", "Untitled") : item.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                            if let category {
                        Text(category.name)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Text(relativeTime)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                highlightText(item.preview.isEmpty ? _L("空白文件", "Blank File") : item.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .onHover { hovering in hover = hovering }
        // 资源管理器语义：双击打开（单击仅选中 → ⇧/⌘ 连续多选）；
        .simultaneousGesture(TapGesture(count: 2).onEnded { store.openNote(item.id) })
    }

    private func highlightText(_ s: String) -> Text {
        var text = Text("")
        let lower = s.lowercased()
        var cursor = s.startIndex
        while cursor < s.endIndex {
            var found = false
            var first: (lowerBound: String.Index, upperBound: String.Index)?
            for tok in tokens {
                if let r = lower.range(of: tok.lowercased(), range: cursor..<s.endIndex) {
                    if first == nil || r.lowerBound < first!.lowerBound {
                        first = (r.lowerBound, r.upperBound)
                    }
                    found = true
                }
            }
            if found, let hit = first {
                if hit.lowerBound > cursor {
                    text = text + Text(String(s[cursor..<hit.lowerBound]))
                }
                text = text + Text(String(s[hit.lowerBound..<hit.upperBound]))
                    .foregroundStyle(Color.accentColor)
                    .fontWeight(.semibold)
                cursor = hit.upperBound
            } else {
                if cursor < s.endIndex {
                    text = text + Text(String(s[cursor..<s.endIndex]))
                }
                break
            }
        }
        return text
    }



    private var relativeTime: String {
        guard let t = ISO8601DateFormatter().date(from: item.updated) else { return "" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .short
        return f.localizedString(for: t, relativeTo: Date())
    }
}


/// 功能栏图标按钮（VSCode 风格：选中底 + 提示）
private extension SidebarView {
    func activityIcon(_ icon: String, _ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(active ? currentTheme.accent.opacity(0.16) : Color.clear)
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(active ? currentTheme.accent : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

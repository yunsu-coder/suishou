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

/// 侧边栏 —— VSCode 式结构：左活动条（笔记/回收站）+ 右侧面板
/// 强逻辑性：一个图标一个面板；简单：收起一切次要入口
struct SidebarView: View {
    enum Panel: String, CaseIterable, Identifiable {
        case notes, trash
        var id: String { rawValue }
        var title: String {
            switch self {
            case .notes: return "笔记"
            case .trash: return "回收站"
            }
        }
        var icon: String {
            switch self {
            case .notes: return "text.document"
            case .trash: return "trash"
            }
        }
    }

    @Environment(NotesStore.self) private var store
    @Binding var showVersions: Bool
    @State private var panel: Panel = .notes

    // 笔记面板状态
    @State private var renameTarget: NoteIndexItem?
    @State private var renameText = ""
    @State private var deleteTarget: NoteIndexItem?
    @State private var newCategoryText = ""
    @State private var showNewCategory = false
    @State private var categoryManageTarget: NoteCategory?
    @State private var dropping = false
    @State private var collapsedGroups: Set<String> = []
    /// 内联新建命名行："=root" 或分类 id；nil = 未在命名
    @State private var creatingInFolder: String?
    @State private var creatingName = ""
    @FocusState private var nameFieldFocused: Bool
    // 导入（目标选择 / 文件夹拖拽高亮）
    @State private var importPending: [URL] = []
    @State private var showImportTarget = false
    @State private var folderDropCandidate: String?

    var body: some View {
        HStack(spacing: 0) {
            activityBar
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
            panelContent
                .frame(minWidth: 225, idealWidth: 268, maxWidth: 320)
        }
        .frame(minWidth: 270, idealWidth: 312)
        .alert("新建文件夹", isPresented: $showNewCategory) {
            TextField("文件夹名", text: $newCategoryText)
            Button("创建") {
                if !store.createCategory(newCategoryText) {
                    store.showHint("已存在同名文件夹")
                }
                newCategoryText = ""
            }
            Button("取消", role: .cancel) { newCategoryText = "" }
        } message: {
            Text("文件夹 = 分类，笔记可拖入或右键移动")
        }
        .alert("重命名文件夹", isPresented: Binding<Bool>(
            get: { categoryManageTarget != nil },
            set: { if !$0 { categoryManageTarget = nil } }
        )) {
            TextField("文件夹名", text: $newCategoryText)
            Button("确定") {
                if let t = categoryManageTarget {
                    if !store.renameCategory(t.id, to: newCategoryText) {
                        store.showHint("已存在同名文件夹")
                    }
                }
                categoryManageTarget = nil
            }
            Button("取消", role: .cancel) { categoryManageTarget = nil }
        }
        // 命令面板转发：新建文件夹 / 导入
        .onReceive(NotificationCenter.default.publisher(for: .requestNewCategory)) { _ in
            showNewCategory = true
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
                        Label("拖入导入为新笔记", systemImage: "square.and.arrow.down")
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
                                _ = store.importNote(from: url)
                            }
                        }
                    }
                    ok = true
                }
            }
            return ok
        }
        .alert("重命名笔记", isPresented: Binding<Bool>(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("标题", text: $renameText)
            Button("确定") {
                if let t = renameTarget {
                    if !store.renameNote(t.id, to: renameText) {
                        store.showHint("该文件夹下已存在同名笔记")
                    }
                }
                renameTarget = nil
            }
            Button("取消", role: .cancel) { renameTarget = nil }
        } message: {
            Text("修改笔记标题")
        }
        .confirmationDialog(
            "删除笔记？",
            isPresented: Binding<Bool>(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            presenting: deleteTarget
        ) { item in
            Button("删除", role: .destructive) { store.deleteNote(item.id) }
            Button("取消", role: .cancel) {}
        } message: { item in
            Text("“\(item.title.isEmpty ? "无标题" : item.title)”将移入回收站")
        }
    }

    // ═══ 活动条（VSCode 风格：图标 + 选中底 + 提示） ═══
    private var activityBar: some View {
        VStack(spacing: 3) {
            ForEach(Panel.allCases) { p in
                Button {
                    panel = p
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(panel == p ? currentTheme.accent.opacity(0.16) : .clear)
                            .frame(width: 30, height: 30)
                        Image(systemName: p.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(panel == p ? currentTheme.accent : Color.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help(p.title)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .frame(width: 36)
        .background(.quaternary.opacity(0.35))
    }

    // ═══ 面板内容 ═══
    @ViewBuilder
    private var panelContent: some View {
        switch panel {
        case .notes: notesPanel
        case .trash: TrashPanel()
                .environment(store)
        }
    }

    // ── 笔记面板（VSCode 资源管理器：标题行 + 搜索 + 文件夹树） ──
    private var notesPanel: some View {
        VStack(spacing: 0) {
            explorerHeader
            Divider()
            explorerSearch
            Divider()
            explorerTree
            undoToast
            footer
        }
    }

    /// 删除撤销浮动条（6 秒自动消失）
    private var undoToast: some View {
        Group {
            if store.showUndoToast {
                HStack(spacing: 8) {
                    Text("已删除")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("撤销") { store.undoDelete() }
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

    /// 面板标题行（资源管理器式）：▼ 笔记 + 新建 / 新建文件夹 / 导入
    private var explorerHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("笔记")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("新建笔记…") { beginCreatingIn(.root) }
                Button("新建文件夹…") { showNewCategory = true }
                Button("移除空文件夹") { store.removeEmptyCategories() }
                Divider()
                Button("导入文件…") { pickImportFiles(directories: false) }
                Button("导入文件夹…") { pickImportFiles(directories: true) }
                Button("导入文件（到指定文件夹）…") { pickImportFiles(directories: false, needsTarget: true) }
            } label: {
                Image(systemName: "plus")
                    .font(.caption2.weight(.semibold))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22, height: 18)
            .help("新建 / 导入（拖拽文件到文件夹行可指定目标）")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // 标题行收窄折叠（VSCode 面板标题不可折，保持简单：不做折叠态）
    }

    // MARK: - 导入选择（文件/文件夹 → 可选目标）

    private func pickImportFiles(directories: Bool, needsTarget: Bool = false) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = directories
        panel.canChooseFiles = true
        panel.message = directories ? "选择要导入的文件夹（内部文件与子文件夹将自动入库）"
                                    : "选择要导入的 Markdown / 文本文件（可多选）"
        let mdType = UTType(filenameExtension: "md") ?? .plainText
        panel.allowedContentTypes = directories ? [.folder] : [mdType, .plainText]
        if panel.runModal() == .OK {
            var toImport: [URL] = []
            if directories {
                for url in panel.urls where url.hasDirectoryPath {
                    let n = store.importFolder(url)
                    store.showHint("已导入 \(n) 篇（文件夹“\(url.lastPathComponent)”）")
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
                    store.showHint("已导入 \(n) 篇笔记")
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
                            _ = store.importNote(from: url, category: categoryID)
                        }
                    }
                }
            }
            ok = true
        }
        return ok
    }

    // MARK: - 内联命名（先命名再创建，VSCode 新建文件心法）

    private enum CreateTarget: Equatable {
        case root
        case folder(String)
        var key: String { self == .root ? "=root" : folderID }
        var folderID: String { if case .folder(let id) = self { return id } else { return "" } }
    }

    private func beginCreatingIn(_ target: CreateTarget) {
        creatingInFolder = target.key
        creatingName = ""
        DispatchQueue.main.async { nameFieldFocused = true }
    }

    private func commitCreating() {
        let name = creatingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            creatingInFolder = nil
            return
        }
        let cat = creatingInFolder == CreateTarget.root.key ? "" : (creatingInFolder ?? "")
        // 同目录同名校验：失败弹提示，命名行保留以便改名
        if !store.createNote(title: name, category: cat) {
            store.showHint("该文件夹下已存在同名笔记，请换个名称")
            return
        }
        creatingInFolder = nil
    }

    /// 命名输入行（回车提交 / Esc 取消）
    private var creatingRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.badge.plus")
                .font(.caption)
                .foregroundStyle(currentTheme.accent)
            TextField("输入名称，回车创建…", text: $creatingName)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($nameFieldFocused)
                .onSubmit { commitCreating() }
                .onKeyPress(.escape) {
                    creatingInFolder = nil
                    return .handled
                }
            if !creatingName.isEmpty {
                Button {
                    commitCreating()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(currentTheme.accent)
                }
                .buttonStyle(.plain)
                .help("创建 (回车)")
            }
        }
        .padding(.vertical, 3)
    }

    private var explorerSearch: some View {
        @Bindable var store = store
        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
            TextField("搜索笔记", text: $store.searchQuery)
                .textFieldStyle(.plain)
                .font(.callout)
                .onSubmit { store.filteredIndex.first.map { store.selectedNoteID = $0.id } }
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
                .help("清空搜索 (Esc)")
            }
        }
        .padding(.vertical, 5)
    }

    /// 文件夹树（VSCode 文件管理器）：
    /// - 根 = 全部笔记；未归档笔记直接显示在根下（无"未分类"组）
    /// - 文件夹在前、根文件在后（时间排序模式）；手动排序返回整体平铺（顺序=order.json）
    /// - 搜索时变为平铺命中结果
    private var explorerTree: some View {
        @Bindable var store = store
        return List(selection: Binding<Set<String>>(
            get: { store.selectedNoteIDs },
            set: { store.selectedNoteIDs = $0 }
        )) {
            if creatingInFolder == CreateTarget.root.key {
                creatingRow
                    .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
            }
            if !store.searchQuery.isEmpty {
                // 搜索模式：平铺命中（标题优先）
                ForEach(store.filteredIndex) { item in
                    NoteRow(item: item,
                            category: store.categories.first { $0.id == item.category },
                            query: store.searchQuery)
                        .tag(item.id)
                        .contextMenu { rowMenu(item) }
                        .onTapGesture(count: 2) { store.openNote(item.id) }
                }
                if store.filteredIndex.isEmpty {
                    VStack(spacing: 6) {
                        Text("没有匹配结果")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                        Button("清空搜索") { store.searchQuery = "" }
                            .buttonStyle(.link)
                            .font(.callout)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
            } else {
                // 文件夹树（所有排序模式统一显示；组内/根内顺序由当前 sortMode 决定）。
                // 手动排序：filteredIndex 已按 .order.json 投射过，子项顺序即用户顺序。
                let sortedCategories = store.categories.sorted(by: {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                })
                ForEach(sortedCategories) { cat in
                    let items = store.filteredIndex.filter { $0.category == cat.id }
                    let isOpen = !collapsedGroups.contains(cat.id)
                    HStack(spacing: 6) {
                        Button {
                            if isOpen { collapsedGroups.insert(cat.id) }
                            else { collapsedGroups.remove(cat.id) }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(isOpen ? 90 : 0))
                        }
                        .buttonStyle(.plain)
                        Circle().fill(colorFromHex(cat.color)).frame(width: 7, height: 7)
                        Text(cat.name)
                            .font(.callout.weight(.medium))
                        Text("\(items.count)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                        Spacer()
                        Menu {
                            Button("重命名文件夹…") { categoryManageTarget = cat }
                            Divider()
                            Button("导入文件到此文件夹…") { pickImportFiles(directories: false, needsTarget: true) }
                            Button("新建笔记到此文件夹（先命名）") {
                                beginCreatingIn(.folder(cat.id))
                                collapsedGroups.remove(cat.id)
                            }
                            Divider()
                            Button("删除文件夹（笔记移到根目录）", role: .destructive) {
                                store.deleteCategory(cat.id)
                            }
                        } label: {
                            Image(systemName: "folder")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .menuIndicator(.hidden)
                        }
                        .menuStyle(.borderlessButton)
                    }
                    .overlay {
                        if folderDropCandidate == cat.id {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(currentTheme.accent, lineWidth: 1.5)
                                .padding(-2)
                        }
                    }
                    .onDrop(of: [UTType.fileURL.identifier], isTargeted: Binding(
                        get: { folderDropCandidate == cat.id },
                        set: { on in folderDropCandidate = on ? cat.id : folderDropCandidate }
                    )) { providers in
                        importDroppedToFolder(providers, categoryID: cat.id)
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                    // 文件夹行：显式不可选（防隐性 identity 进多选集）+ 整行点击=折叠切换
                    .tag(Optional<String>.none)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isOpen { collapsedGroups.insert(cat.id) }
                        else { collapsedGroups.remove(cat.id) }
                    }

                    if isOpen {
                        if creatingInFolder == cat.id {
                            creatingRow
                                .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 6))
                        }
                        ForEach(items) { item in
                            NoteRow(item: item,
                                    category: cat,
                                    query: "")
                                .tag(item.id)
                                .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 6))
                                .contextMenu { rowMenu(item) }
                        }
                    }
                }
                // 根文件（未归档笔记直接显示在根下，VSCode 工作区即如此）
                ForEach(store.filteredIndex.filter { $0.category.isEmpty }) { item in
                    NoteRow(item: item,
                            category: nil,
                            query: "")
                        .tag(item.id)
                        .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
                        .contextMenu { rowMenu(item) }
                }
                if store.index.isEmpty {
                    VStack(spacing: 6) {
                        Text("还没有笔记")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                        Button("新建第一篇笔记") { store.createNote() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .font(.callout)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    // 分类弹窗（新建/重命名）挂根视图
    @ViewBuilder
    private func rowMenu(_ item: NoteIndexItem) -> some View {
        Button("打开") { store.openNote(item.id) }
        Divider()
        Button("上移") { store.moveNote(item.id, delta: -1) }
        Button("下移") { store.moveNote(item.id, delta: 1) }
        Divider()
        Button("重命名…") {
            renameTarget = item
            renameText = item.title
        }
        Menu("移动到分类") {
            Button("未分类") {
                if !store.assignCategory(item.id, "") {
                    store.showHint("该文件夹下已存在同名笔记")
                }
            }
            ForEach(store.categories) { cat in
                Button(cat.name) {
                    if !store.assignCategory(item.id, cat.id) {
                        store.showHint("该文件夹下已存在同名笔记")
                    }
                }
            }
        }
        Divider()
        Button("删除…", role: .destructive) { deleteTarget = item }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(store.notesDir.path)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help("笔记存储目录")
            Spacer()
            // 排序方式（更新时间/创建时间/手动）——用户排序需求入口
            Menu {
                Picker("排序", selection: Binding<String>(
                    get: { store.sortMode.rawValue },
                    set: { store.sortMode = NotesStore.SortMode(rawValue: $0) ?? .updated }
                )) {
                    Text("按更新时间").tag(NotesStore.SortMode.updated.rawValue)
                    Text("按创建时间").tag(NotesStore.SortMode.created.rawValue)
                    Text("手动排序").tag(NotesStore.SortMode.manual.rawValue)
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.caption2)
                    .foregroundStyle(store.sortMode == .manual ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20, height: 16)
            .help("排序方式（右键笔记：上移/下移 可手排）")

            if !store.searchQuery.isEmpty {
                Text("\(store.filteredIndex.count) / \(store.index.count) 匹配")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
                    .monospacedDigit()
            } else {
                Text("\(store.filteredIndex.count) 篇 · \(store.sortMode.name)")
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
                Text("导入 \(files.count) 个文件到…")
                    .font(.headline)
                Spacer()
            }
            .padding(16)
            Divider()
            Picker(selection: $selected) {
                Text("根目录（未归档）").tag("")
                ForEach(store.categories) { cat in
                    Text(cat.name).tag(cat.id)
                }
            } label: {
                Text("目标文件夹")
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .padding(16)
            Divider()
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("导入") {
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

/// 单条笔记行 —— 分类色点 + 标题/摘要（搜索词高亮）+ 相对时间
private struct NoteRow: View {
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
                    highlightText(item.title.isEmpty ? "无标题" : item.title)
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
                highlightText(item.preview.isEmpty ? "空白笔记" : item.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
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

/// 回收站面板（内嵌侧栏，VSCode 式：列表 + 底部主操作）
private struct TrashPanel: View {
    @Environment(NotesStore.self) private var store
    @State private var items: [NotesStore.TrashItem] = []
    @State private var clearConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("回收站")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(items.count) 篇")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider()

            if items.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "trash.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("回收站是空的")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(items) { item in
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                Text(item.deletedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button("恢复") {
                                store.restoreTrash(item)
                                reload()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            Button(role: .destructive) {
                                store.purgeTrash(item)
                                reload()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)

                HStack(spacing: 10) {
                    Button {
                        for item in items {
                            _ = store.restoreTrash(item)
                        }
                        reload()
                    } label: {
                        Label("恢复全部", systemImage: "arrow.uturn.backward")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button(role: .destructive) {
                        clearConfirm = true
                    } label: {
                        Label("清空回收站", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(alignment: .top) { Divider() }
            }
        }
        .onAppear { reload() }
        .confirmationDialog("清空回收站？", isPresented: $clearConfirm) {
            Button("全部彻底删除", role: .destructive) {
                store.emptyTrash()
                reload()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("清空后无法恢复")
        }
    }

    private func reload() {
        items = store.listTrash()
    }
}

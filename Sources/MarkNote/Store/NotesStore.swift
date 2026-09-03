import Foundation
import AppKit
import Observation
import UniformTypeIdentifiers
import CryptoKit

/// 图片引用内联的正则（相对路径 → data URL，避开 WebKit file 权限）
private enum ImgInline {
    static let re: NSRegularExpression? = try? .init(pattern: #"(!\[[^\]]*\]\()(?!data:|file:|https?:)([^)\s]+)(\))"#)
    static let maxSize = 5 * 1024 * 1024
}

/// 文件数据层 —— 本机 JSON 直存：
///   <notesDir>/<id>.json            文件本体
///   <notesDir>/.versions/<id>/<ts>.json   保存前快照（最多 10 份）
///   <notesDir>/.categories.json    分类
/// 目录即库：文件本体 + 快照 + 点文件全在目录内，可整体复制/备份/迁移。
@MainActor
@Observable
final class NotesStore {

    // MARK: - 状态

    private(set) var index: [NoteIndexItem] = []
    private(set) var categories: [NoteCategory] = []
    var selectedNoteID: String?
    /// 多选（⇧/⌘+点击、⇧+方向键原生扩展）；count==1 时由视图打开文件
    var selectedNoteIDs: Set<String> = []
    var searchQuery = ""
    /// "" = 全部；"=none" = 未分类
    var categoryFilter = ""
    var dirty = false
    var lastSavedAt: Date?
    /// 轻提示（非模态；读取失败等不打断操作）
    private(set) var hintMessage: String?
    /// 外部冲突：打开的文件被其他应用（另一实例/Finder 等）修改（C-04）
    private(set) var externalConflict = false
    /// 冲突已提示但用户「稍后处理」：自动保存暂停，退出/切换时另存副本兜底
    private(set) var conflictHandled = false

    var notesDir: URL {
        didSet {
            PluginManager.shared.scan(workspaceDir: notesDir)
            UserDefaults.standard.set(notesDir.path, forKey: Self.kDirKey)
            rememberWorkspace(notesDir.path)
            flush()
            externalConflict = false
            conflictHandled = false
            loadedExternalFingerprint = nil
            reloadIndex()
            startWatch()
        }
    }

    /// 当前编辑中的文本（编辑器是唯一写入口）
    var workingText = ""
    var currentTitle = ""

    /// 图片注册表幂等缓存：上一次 prepare 的 md（同文直返；invalidate 后重扫）
    @ObservationIgnored
    private var preparedMD: String?

    /// 图片相关状态变化时作废幂等缓存（远程下载完成 / 外部 FS 变更）
    private func invalidatePreparedImages() {
        preparedMD = nil
    }

    private static let kDirKey = "notesDirURL"
    @ObservationIgnored
    private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored
    private var watchSource: DispatchSourceFileSystemObject?
    @ObservationIgnored
    private var reloadWorkItem: DispatchWorkItem?
    @ObservationIgnored
    private let ioQueue = DispatchQueue(label: "marknote.io", qos: .userInitiated)

    // MARK: - 初始化

    init() {
        let path = UserDefaults.standard.string(forKey: NotesStore.kDirKey)
        let def = Self.defaultNotesDir()
        notesDir = path.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? def
        prepareDirectory(def)
        PluginManager.shared.scan(workspaceDir: notesDir)
        // 多工作台历史载入
        if let data = UserDefaults.standard.data(forKey: Self.rootsKey),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            workspaceRoots = saved
        }
        rememberWorkspace(notesDir.path)
        reloadIndex()
        loadCategories()
        restoreTabs()
        loadCustomFontLibrary()
        startWatch()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.flush()
        }
        // 兜底：窗口激活时刷新索引（FS watch 尚未覆盖的跨应用改动）
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reloadIndex()
        }
    }

    static func defaultNotesDir() -> URL {
        // 工作台 = 桌面上的本地文件夹（VSCode 工作区语义）
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return desktop.appendingPathComponent("origin", isDirectory: true)
    }

    private func prepareDirectory(_ dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: dir.appendingPathComponent(".categories.json").path) {
            try? Data("[]".utf8).write(to: dir.appendingPathComponent(".categories.json"))
        }
        if !FileManager.default.fileExists(atPath: dir.appendingPathComponent(".versions").path) {
            try? FileManager.default.createDirectory(at: dir.appendingPathComponent(".versions"), withIntermediateDirectories: true)
        }
    }

    // MARK: - 工具

    nonisolated static func isoNow() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    nonisolated static func randomHex(_ bytes: Int) -> String {
        var buf = [UInt8](repeating: 0, count: bytes)
        for i in 0..<bytes { buf[i] = UInt8.random(in: 0...255) }
        return buf.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func newID() -> String { randomHex(8) }

    nonisolated static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }

    func parseTime(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }

    /// id = 工作台相对路径（含扩展名）
    func noteURL(_ id: String) -> URL { notesDir.appendingPathComponent(id) }

    // MARK: - 导入守卫（修复：MP4 拖入被按文本导入 → .md 化 + 崩溃）

    /// 可按文本导入的扩展名（其余走原始文件放置）
    /// 拖入可按文本导入的扩展名 = 全部可编辑文本类型
    static let importableTextExts: Set<String> = Workspace.textExtensions
    private static let maxTextImportBytes = 8 * 1024 * 1024

    /// 二进制嗅探：超大文件 / 前 2KB 含 NUL → 非文本
    private func isTextFile(_ url: URL) -> Bool {
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > Self.maxTextImportBytes {
            return false
        }
        if let handle = try? FileHandle(forReadingFrom: url) {
            let head = (try? handle.read(upToCount: 2048)) ?? Data()
            try? handle.close()
            if head.contains(0) { return false }
        }
        return true
    }

    /// 拖拽统一入口：文本 → 导入治理；其他（MP4/PDF/图片…）→ 原始文件放入目标文件夹
    @discardableResult
    func importDroppedFile(from url: URL, into cat: String?) -> String? {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty || !Self.importableTextExts.contains(ext) {
            return importRawFile(url, into: cat ?? "")
        }
        return importNote(from: url, category: cat)
    }

    /// 原始文件放入工作台文件夹（外部=复制不动原件；工作台内=移动，Finder 语义）；
    /// 保留原文件名与扩展名（同名自动加序号）。返回相对 id，失败 nil。
    @discardableResult
    func importRawFile(_ url: URL, into cat: String) -> String? {
        let folder = cat.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let target = folder.isEmpty ? notesDir : notesDir.appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let name = Workspace.uniqueName(in: target, fileName: url.lastPathComponent)
        let dst = target.appendingPathComponent(name)
        let inside = url.standardizedFileURL.path.hasPrefix(notesDir.standardizedFileURL.path + "/")
        do {
            if inside {
                try? FileManager.default.moveItem(at: url, to: dst)
            } else {
                try? FileManager.default.copyItem(at: url, to: dst)
            }
        } catch {}
        guard FileManager.default.fileExists(atPath: dst.path) else { return nil }
        reloadIndex()
        return Workspace.relativeID(dst, root: notesDir)
    }

    // MARK: - 索引 / 列表

    /// 后台读目录建立索引（所有 IO 走串行队列，主线程只收结果）。
    /// 竞态保护：每次请求携带令牌，主线程回调仅应用"最新一次"请求的结果
    /// （否则 init 期排队的过期快照会在 openNote 之后到达，误删打开状态——README 期病）。
    @ObservationIgnored
    private var reloadToken = 0

    func reloadIndex() {
        reloadToken += 1
        let token = reloadToken
        let dir = notesDir
        invalidatePreparedImages() // 外部 FS 变更 → 图片 mtime 可能变化，作废幂等缓存
        // 排序固定按更新时间（排序模块已按产品决策移除）
        // C-04：捕获当前已加载文件 id（后台扫描时同步指纹，主线程比对冲突）
        let loadedID = loadedNoteID
        ioQueue.async { [weak self] in
            guard let self else { return }
            var items: [NoteIndexItem] = []
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
                DispatchQueue.main.async {
                    guard token == self.reloadToken else { return }
                    self.index = []
                }
                return
            }
            // 工作台：遍历全部文件；内存优化——媒体/二进制绝不整读（仅文本类进全文缓存，≤512KB）
            var loadedDiskFingerprint: String? = nil
            let textExts = Workspace.textExtensions
            for f in Workspace.walk(dir) {
                let attrs = try? FileManager.default.attributesOfItem(atPath: f.path)
                let created = (attrs?[.creationDate] as? Date).map(Self.iso) ?? Self.isoNow()
                let updated = (attrs?[.modificationDate] as? Date).map(Self.iso) ?? Self.isoNow()
                let ext = f.pathExtension.lowercased()
                var previewData = Data()
                if ext.isEmpty || textExts.contains(ext) {   // 无扩展名 = 文本笔记（不再强制 .md）
                    if let handle = try? FileHandle(forReadingFrom: f) {
                        previewData = (try? handle.read(upToCount: 2000)) ?? Data()
                        try? handle.close()
                    }
                }
                items.append(NoteIndexItem(id: Workspace.relativeID(f, root: dir),
                                           title: Workspace.title(for: f),
                                           // lossy 解码：2KB 字节截断可能切断多字节字符，绝不产生空摘要
                                           preview: String(String(decoding: previewData, as: UTF8.self).prefix(80)),
                                           created: created,
                                           updated: updated, category: Workspace.folderLabel(for: f, root: dir)))
                // 全文缓存：仅文本类且 ≤512KB（工作台媒体库绝不进内存）
                if (ext.isEmpty || textExts.contains(ext)),
                   (attrs?[.size] as? NSNumber)?.uint64Value ?? 0 <= 512 * 1024 {
                    if let data = try? Data(contentsOf: f), self.fullTextCache[items.last!.id] != data {
                        self.fullTextCache[items.last!.id] = data
                    }
                }
                // C-04：已加载文件的磁盘指纹（外部改动比对）—— 仅算当前文件
                if let lID = loadedID, Workspace.relativeID(f, root: dir) == lID {
                    loadedDiskFingerprint = Self.md5hex((try? Data(contentsOf: f)) ?? Data())
                }
            }
            // 排序：更新时间 / 创建时间 / 手动（notes/.order.json 持久化）
            items.sort(by: { (self.parseTime($0.updated) ?? .distantPast) > (self.parseTime($1.updated) ?? .distantPast) })
            DispatchQueue.main.async {
                guard token == self.reloadToken else { return } // 过期请求丢弃
                self.loadCategories() // 与索引一起刷新（含外部修改）
                if let sel = self.selectedNoteID, !items.contains(where: { $0.id == sel }) {
                    // 当前文件已被外部删除：退出编辑
                    self.selectedNoteID = nil
                    self.loadedNoteID = nil
                    self.workingText = ""
                    self.externalConflict = false
                    self.conflictHandled = false
                    self.loadedExternalFingerprint = nil
                }
                self.index = items
                self.detectExternalConflict(diskFingerprint: loadedDiskFingerprint)
            }
        }
    }

    /// 全文检索缓存：id → 原始数据（刷新索引时更新；用于正文搜索）
    @ObservationIgnored
    private var fullTextCache: [String: Data] = [:]

    /// 统一排序（按更新时间降序；排序模块已移除，固定时间序）
    private func sortedByMode(_ items: [NoteIndexItem]) -> [NoteIndexItem] {
        items.sorted(by: { (parseTime($0.updated) ?? .distantPast) > (parseTime($1.updated) ?? .distantPast) })
    }

    /// 写操作后同步索引（重名拦截与测试/列表即时可见性依赖它）
    private func syncInsertIndex(_ note: Note) {
        var items = index.filter { $0.id != note.id }
        items.append(NoteIndexItem(id: note.id, title: note.title,
                                   preview: String(note.content.prefix(80)),
                                   created: note.created, updated: note.updated,
                                   category: note.category))
        index = sortedByMode(items)
    }

    func loadCategories() {
        // 工作台语义：文件夹 = 分类（通用递归目录树；source/ 与普通目录同等）
        var out: [NoteCategory] = []
        func walkDir(_ dir: URL) {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
            for u in items where !u.lastPathComponent.hasPrefix(".") {
                guard let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory, isDir
                else { continue }
                out.append(NoteCategory(id: Workspace.relativeID(u, root: notesDir),
                                        name: u.lastPathComponent,
                                        color: Self.stableColor(u.lastPathComponent)))
                walkDir(u)
            }
        }
        walkDir(notesDir)
        categories = out
    }

    /// 文件夹名 → 稳定配色（哈希取色板）
    private static func stableColor(_ name: String) -> String {
        let palette = ["#6d8bff", "#e0a44c", "#5aa66e", "#c96aa8", "#63a3c4", "#c47b4a", "#9a7fd0", "#b8b06a"]
        var h = 0
        for b in name.utf8 { h = (h &* 31 &+ Int(b)) & 0xffff }
        return palette[h % palette.count]
    }

    // MARK: - 文件级 IO（同步、串行队列）

    /// 文件级读取（工作台语义：笔记 = 纯文本文件，任意格式皆可）
    private func readNote(_ id: String) -> Note? {
        let url = noteURL(id)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Note(id: id, title: Workspace.title(for: url),
                    content: content, category: Workspace.folderLabel(for: url, root: notesDir))
    }

    private func writeNote(_ note: Note) {
        let fm = FileManager.default
        try? fm.createDirectory(at: noteURL(note.id).deletingLastPathComponent(), withIntermediateDirectories: true)
        try? note.content.write(to: noteURL(note.id), atomically: true, encoding: .utf8)
    }

    private func snapshotNote(_ id: String) {
        let src = noteURL(id)
        guard FileManager.default.fileExists(atPath: src.path) else { return }
        let safeID = id.replacingOccurrences(of: "/", with: "__")
        let verDir = notesDir.appendingPathComponent(".versions/\(safeID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: verDir, withIntermediateDirectories: true)
        let ts = String(Int(Date().timeIntervalSince1970 * 1000))
        let dest = verDir.appendingPathComponent(ts + ".md")
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: src, to: dest)
        pruneVersions(verDir)
    }

    /// 快照目录只保留最近 10 份
    private func pruneVersions(_ verDir: URL) {
        let vers = (try? FileManager.default.contentsOfDirectory(at: verDir, includingPropertiesForKeys: nil)) ?? []
        var versFiles = vers.filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        while versFiles.count > 10, let oldest = versFiles.first {
            try? FileManager.default.removeItem(at: oldest)
            versFiles.removeFirst()
        }
    }

    // MARK: - 读取 / 保存

    /// 已装载内容的文件（与"选中态"分离 —— 修复点击列表无法切换的致命 bug：
    /// List(selection:) 先写 selectedNoteID，onChange→openNote 时旧 guard
    /// 因 id==selectedNoteID 恒等而被永远拦截）
    private(set) var loadedNoteID: String?

    // MARK: - 浏览器式标签页（打开即建 tab；点击上方切换；⌘W 关闭）

    private(set) var openTabs: [String] = []

    private func restoreTabs() {
        guard let data = UserDefaults.standard.data(forKey: "openTabs"),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return }
        let valid = ids.filter { id in index.contains(where: { $0.id == id }) }
        openTabs = valid
    }


    // MARK: - 树行投影（UI 供 NSTableView 使用）

    /// 文件夹树行序列：文件夹行（可折叠）+ 其内文件 + 根文件；搜索时平铺
    func treeRows(openFolders folded: Set<String>) -> [TreeRow] {
        // 搜索态：平铺命中（标题优先已由 filteredIndex 保证）
        if !searchQuery.isEmpty {
            return filteredIndex.map { .note($0, level: 0) }
        }
        // 工作台语义：通用递归目录树（source/ 及嵌套资源目录与普通文件夹同等渲染）
        var out: [TreeRow] = []
        let folderSet = Set(categories.map(\.id))
        let itemsByFolder = Dictionary(grouping: filteredIndex, by: { $0.category })

        func directChildren(_ folder: String) -> [NoteIndexItem] {
            let items = itemsByFolder[folder] ?? []
            return items.filter {
                let rest = folder.isEmpty
                    ? $0.id
                    : ($0.id.hasPrefix(folder + "/") ? String($0.id.dropFirst(folder.count + 1)) : $0.id)
                return !rest.contains("/")
            }
        }
        func addFolder(_ id: String, level: Int) {
            guard let cat = categories.first(where: { $0.id == id }) else { return }
            let isOpen = !folded.contains(id)
            out.append(.folder(cat, count: directChildren(id).count, isOpen: isOpen, level: level))
            guard isOpen else { return }
            let kids = folderSet
                .filter { $0.hasPrefix(id + "/") && !$0.dropFirst(id.count + 1).contains("/") }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            for k in kids { addFolder(k, level: level + 1) }
            for it in directChildren(id) { out.append(.note(it, level: level + 1)) }
        }
        // 顶层 = 所有一级目录（含 source）+ 根目录文件
        let tops = folderSet.filter { !$0.contains("/") }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        for t in tops { addFolder(t, level: 0) }
        for it in directChildren("") { out.append(.note(it, level: 0)) }
        return out
    }

    private func persistTabs() {
        if let data = try? JSONEncoder().encode(openTabs) {
            UserDefaults.standard.set(data, forKey: "openTabs")
        }
    }

    func closeTab(_ id: String) {
        guard let i = openTabs.firstIndex(of: id) else { return }
        openTabs.remove(at: i)
        if loadedNoteID == id {
            let neighbor = openTabs.isEmpty ? nil : openTabs[min(max(i - 1, 0), openTabs.count - 1)]
            if let neighbor, let note = ioQueue.sync(execute: { self.readNote(neighbor) }) {
                loadedNoteID = neighbor
                selectedNoteID = neighbor
                workingText = note.content
                currentTitle = note.title
                dirty = false
            } else {
                loadedNoteID = nil
                selectedNoteID = nil
                workingText = ""
            }
        }
        persistTabs()
    }

    /// Tab 标题：当前装载的直接用内存标题（改名即时），其余从索引取
    /// 被拖拽中的文件 id（瞬态；DropDelegate 读取）
    private(set) var draggingNoteID: String?
    func beginDrag(_ id: String) { draggingNoteID = id }
    /// 拖到文件夹行 → 移动分类
    func moveNoteFlat(_ id: String, to catID: String) {
        assignCategory(id, catID)
        endDrag()
    }

    func endDrag() { draggingNoteID = nil }



    func tabTitle(_ id: String) -> String {
        if id == loadedNoteID {
            return currentTitle.isEmpty ? _L("无标题", "Untitled") : currentTitle
        }
        return index.first { $0.id == id }?.title ?? _L("无标题", "Untitled")
    }

    func closeCurrentTab() {
        if let id = loadedNoteID { closeTab(id) }
    }
    /// 文档内容版本号：每次"程序性换文档"（打开/恢复/导入）递增。
    /// 编辑器据此区分"主动切换"（store→视图）与"用户输入领先"（视图→store 回填，禁止反写）。
    @ObservationIgnored
    private(set) var documentRevision = 1
    /// 打开文件的磁盘指纹（MD5(文件数据)），外部改动检测基准（C-04）
    @ObservationIgnored
    private var loadedExternalFingerprint: String?

    /// 预览面板直接展示的媒体（单击树中的图片/视频 → 内嵌查看；不用系统默认程序）
    enum PreviewMedium: Equatable {
        case image(URL)
        case video(URL)
    }
    private(set) var previewMedium: PreviewMedium?

    func openNote(_ id: String) {
        // 文件管理器语义：文本类文件在 app 内编辑；图片/视频 → 预览面板直接展示；其余 → 系统默认程序
        let ext = (id as NSString).pathExtension.lowercased()
        let textual = Workspace.textExtensions
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp", "svg"]
        let videoExts: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv", "avi"]
        previewMedium = nil
        if imageExts.contains(ext) {
            previewMedium = .image(noteURL(id))
            currentTitle = Workspace.title(for: noteURL(id))
            return
        }
        if videoExts.contains(ext) {
            previewMedium = .video(noteURL(id))
            currentTitle = Workspace.title(for: noteURL(id))
            return
        }
        if !textual.contains(ext) && !ext.isEmpty {
            // 有扩展名但不属于文本类（图片/视频走前面；其余交给系统）
            NSWorkspace.shared.open(noteURL(id))
            return
        }
        // 无扩展名（用户按「不自动补全 .md」创建）→ 按文本编辑
        guard loadedNoteID != id else { return } // 已装载同一篇 → 幂等返回
        flush()
        guard let note = ioQueue.sync(execute: { readNote(id) }) else {
            // 轻提示（不阻塞）；自愈：清选中 + 手动序幽灵 + 刷新列表
            showHint(_L("读取失败：文件不存在（可能已被删除）", "Failed to read: the file does not exist (it may have been deleted)"))
            selectedNoteIDs.remove(id)

            reloadIndex()
            return
        }
        loadedNoteID = id
        selectedNoteID = id // 与列表状态汇合（幂等）
        if !openTabs.contains(id) { openTabs.append(id); persistTabs() }
        workingText = note.content
        currentTitle = note.title
        dirty = false
        documentRevision += 1
        // C-04：记录磁盘指纹供外部改动检测；换文档即清冲突
        loadedExternalFingerprint = currentFileFingerprint(id)
        externalConflict = false
        conflictHandled = false
        // 注意：不再重排列表 —— 打开文件不改变用户排序
    }

    /// 编辑器内容变化入口（NSTextView onTextChange 回调用）
    func textChanged(_ text: String) {
        workingText = text
        markDirty()
    }

    private func markDirty() {
        dirty = true
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.saveCurrent()
        }
    }

    /// 立即保存当前文件（自动保存 500ms 防抖、切换文件、退出前调用）
    func saveCurrent() {
        guard let id = selectedNoteID else { return }
        // C-04：外部冲突未处理时禁止自动落盘（避免覆盖外部修改）
        if externalConflict || conflictHandled {
            return
        }
        var title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty && workingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // 全新空文件：延迟到首次有内容再落地
            if !FileManager.default.fileExists(atPath: noteURL(id).path) { return }
        }
        // 同目录同名校验：冲突时回退标题并提示
        if let item = index.first(where: { $0.id == id }),
           hasDuplicateTitle(title, category: item.category, excluding: id) {
            currentTitle = item.title
            showHint(_L("该文件夹下已存在同名文件（标题已还原）", "A file with the same name already exists in this folder (title has been reverted)"))
            return
        }
        let content = workingText
        ioQueue.sync {
            var note = readNote(id) ?? Note(id: id, title: title)
            note.title = title
            note.content = content
            note.updated = Self.isoNow()
            snapshotNote(id)  // 保存前快照（.versions/<id>/）
            writeNote(note)   // 原子写文件（工作台语义）
        }
        dirty = false
        lastSavedAt = Date()
        // C-04：自身写入后刷新指纹（否则 FS watch 回流会被误判为外部冲突）
        loadedExternalFingerprint = currentFileFingerprint(id)
        updateIndexAfterSave(id)  // 性能：增量更新当前条目（不再全工作台重扫；FS watch 仍兜底异步全量）
    }

    /// 保存后索引增量更新：只重读本条（摘录 2KB + 属性），库再大每次保存也不再全目录 walk
    private func updateIndexAfterSave(_ id: String) {
        let url = noteURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { reloadIndex(); return }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        var preview = ""
        if let handle = try? FileHandle(forReadingFrom: url) {
            let data = (try? handle.read(upToCount: 2000)) ?? Data()
            try? handle.close()
            preview = String(String(decoding: data, as: UTF8.self).prefix(80))
        }
        let item = NoteIndexItem(id: id, title: Workspace.title(for: url), preview: preview,
                                 created: (attrs?[.creationDate] as? Date).map(Self.iso) ?? Self.isoNow(),
                                 updated: (attrs?[.modificationDate] as? Date).map(Self.iso) ?? Self.isoNow(),
                                 category: Workspace.folderLabel(for: url, root: notesDir))
        index.removeAll { $0.id == id }
        index.append(item)
        index.sort(by: { (parseTime($0.updated) ?? .distantPast) > (parseTime($1.updated) ?? .distantPast) })
        // 全文缓存同步（≤512KB 文本）
        if let text = try? String(contentsOf: url, encoding: .utf8), text.utf8.count <= 512 * 1024 {
            fullTextCache[id] = Data(text.utf8)
        }
    }

    /// 用户显式保存（⌘S/菜单）：冲突时提醒并打开处理入口
    func saveNow() {
        if externalConflict || conflictHandled {
            showHint(_L("文件已被外部修改：请先处理冲突（自动保存已暂停）", "File was modified externally: please resolve the conflict first (autosave is paused)"))
            reopenConflictPrompt()
            return
        }
        saveCurrent()
    }

    /// 强制落盘（切换目录/退出前）
    func flush() {
        autosaveTask?.cancel()
        autosaveTask = nil
        if dirty {
            if externalConflict || conflictHandled {
                // C-04：不覆盖外部版本 —— 当前内容另存为新文件，绝不静默丢失
                saveConflictCopy()
            } else {
                saveCurrent()
            }
        }
        // 同步等待写盘完成，避免旧内容覆盖新目录
        ioQueue.sync {}
    }

    /// 冲突期间的兜底落盘：当前内容另存为新文件（标题加后缀）
    private func saveConflictCopy() {
        guard let id = selectedNoteID else { return }
        let base = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = base.isEmpty ? _L("无标题（冲突副本）", "Untitled (Conflict Copy)") : _L("\(base)（冲突副本）", "\(base) (Conflict Copy)")
        let cat = index.first { $0.id == id }?.category ?? ""
        let copyID = cat.isEmpty ? (title + ".md") : (cat + "/" + title + ".md")
        ioQueue.sync {
            let url = noteURL(copyID)
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try workingText.write(to: url, atomically: true, encoding: .utf8)
            } catch {}
        }
        reloadIndex()
        conflictHandled = false
        dirty = false
        showHint(_L("检测到外部修改：当前内容已另存为「\(title)」", "External change detected: current content has been saved as \"\(title)\""))
    }

    // MARK: - 导入

    /// 弹出面板批量导入 .md/.txt 文件
    func showImportPanel() {
        flush()
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        let mdType = UTType(filenameExtension: "md") ?? .plainText
        panel.allowedContentTypes = [mdType, .plainText]
        panel.message = _L("选择要导入的 Markdown / 文本文件（每个文件成为一篇文件）", "Choose Markdown / text files to import (each file becomes a note)")
        if panel.runModal() == .OK {
            var last: String?
            for url in panel.urls {
                last = importNote(from: url)
            }
            if let last { openNote(last) }
        }
    }

    /// 把外部 .md/.txt 文件导入为新文件（带回格式治理）；返回文件 id
    @discardableResult
    func importNote(from url: URL) -> String? {
        importNote(from: url, category: nil)
    }

    /// 带目标分类的导入（category = 分类 id 或 nil=根目录）
    @discardableResult
    func importNote(from url: URL, category cat: String?) -> String? {
        // 修复：MP4/PDF/图片等二进制绝不按文本导入（.md 化 + 解码崩溃）
        let ext = url.pathExtension.lowercased()
        guard (ext.isEmpty || Self.importableTextExts.contains(ext)), isTextFile(url) else { return nil }
        var content = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .isoLatin1)) ?? ""
        // 1) BOM 剥离（用户常见的 Windows/编辑器头部乱码）
        if content.hasPrefix("\u{FEFF}") { content.removeFirst() }
        // 2) 换行规整 CRLF/CR → LF（导入前 VSCode/Windows 写法普遍）
        content = content.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        // 3) YAML front matter：解析 title，并整体移除
        var title = url.deletingPathExtension().lastPathComponent.isEmpty
            ? _L("导入文件", "Imported File") : url.deletingPathExtension().lastPathComponent
        if content.hasPrefix("---\n") {
            let bodyStart = content.index(content.startIndex, offsetBy: 4)
            if let close = content[bodyStart...].range(of: "\n---") {
                let fm = String(content[bodyStart..<close.lowerBound])
                for line in fm.split(separator: "\n") where line.hasPrefix("title:") {
                    let t = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                    let cleaned = t.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                    if !cleaned.isEmpty { title = cleaned }
                }
                content = String(content[close.upperBound...])
                if content.hasPrefix("\n") { content.removeFirst() }
            }
        }
        // 4) 正文首行 `# 标题` → 提升为文件标题并移除（避免导入后标题重复）
        let firstLine = String(content.split(separator: "\n", maxSplits: 1).first ?? "")
        if firstLine.hasPrefix("# ") {
            let t = String(firstLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { title = t }
            let rest = content.dropFirst(firstLine.count)
            content = rest.hasPrefix("\n") ? String(rest.dropFirst()) : String(rest)
        }
        // 同目录同名导入自动加序号（磁盘实查：索引异步刷新有滞后，去重必须同步成立）
        // 保留原扩展名（c/cpp/js/… 不再被强行写成 .md）
        let base = title
        let catID = cat ?? ""
        let srcExt = url.pathExtension.lowercased()
        let writeExt = srcExt.isEmpty ? "" : "." + srcExt
        var n = 2
        func targetExists(_ t: String) -> Bool {
            let id = catID.isEmpty ? (t + writeExt) : (catID + "/" + t + writeExt)
            return FileManager.default.fileExists(atPath: notesDir.appendingPathComponent(id).path)
        }
        while targetExists(title) {
            title = "\(base) \(n)"; n += 1
        }
        let id = catID.isEmpty ? (title + writeExt) : (catID + "/" + title + writeExt)
        ioQueue.sync {
            let url = noteURL(id)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
        reloadIndex()
        return id
    }

    // MARK: - 导入增强（批量 / 指定文件夹 / 递归文件夹）

    /// 批量导入一批文件到指定分类（nil=根目录）；返回成功数量
    @discardableResult
    func importFiles(urls: [URL], category: String?) -> Int {
        var count = 0
        for url in urls {
            if url.hasDirectoryPath {
                count += importFolder(url)   // 面板里也能选文件夹
            } else if importNote(from: url, category: category) != nil {
                count += 1
            }
        }
        return count
    }

    /// 递归导入文件夹：直接文件归"文件夹名"分类（同名复用）；
    /// 子文件夹各自成为分类（取其文件夹名）并递归其内容
    @discardableResult
    func importFolder(_ root: URL) -> Int {
        // 文件夹导入 → 在工作台内建目录树（子目录=分类），文件按类型落位（md→同树、其余→source/<type>）
        let fm = FileManager.default
        var count = 0
        func walk(_ dir: URL, relFolder: String) {
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
            for e in entries {
                if e.hasDirectoryPath {
                    let sub = relFolder.isEmpty ? e.lastPathComponent : (relFolder + "/" + e.lastPathComponent)
                    walk(e, relFolder: sub)
                } else {
                    let ext = e.pathExtension.lowercased()
                    if ["md", "markdown", "txt"].contains(ext) {
                        if importNote(from: e, category: relFolder.isEmpty ? nil : relFolder) != nil { count += 1 }
                    } else {
                        count += importResourceFile(e) ? 1 : 0
                    }
                }
            }
        }
        walk(root, relFolder: "")
        return count
    }

    /// 任意资源文件拷入工作台 source/<type>/（唯一命名），返回是否成功
    private func importResourceFile(_ src: URL) -> Bool {
        let dir = Workspace.ensureSourceDir(notesDir, ext: src.pathExtension)
        let dest = dir.appendingPathComponent(Workspace.uniqueName(in: dir, fileName: src.lastPathComponent))
        do {
            try FileManager.default.copyItem(at: src, to: dest)
            return true
        } catch {
            return false
        }
    }

    // MARK: - 资源库（source/<type> 自动归类）

    /// 图片目录：工作台/source/image/
    func imagesDir(_ noteID: String) -> URL {
        notesDir.appendingPathComponent("source/image", isDirectory: true)
    }

    /// 保存图片数据 → 返回 markdown 可引用的相对路径（相对 notesDir）
    @discardableResult
    func saveImage(_ data: Data, ext: String, noteID: String) -> String? {
        let dir = Workspace.ensureSourceDir(notesDir, ext: ext)
        let name = "\(Int(Date().timeIntervalSince1970 * 1000))-\(Self.randomHex(3)).\(ext)"
        do {
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
            return "source/image/\(name)"
        } catch {
            return nil
        }
    }

    /// 当前文件的附件图片列表（按时间倒序）
    func images(for noteID: String) -> [URL] {
        let dir = imagesDir(noteID)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        let exts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"]
        return files.filter { exts.contains($0.pathExtension.lowercased()) }
            .sorted { a, b in
                let ta = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let tb = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return ta > tb
            }
    }

    func deleteImage(_ url: URL, noteID: String) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - 通用文件附件（attachments/<noteId>/）

    func attachmentsDir(_ noteID: String) -> URL {
        noteID.isEmpty
            ? notesDir.appendingPathComponent("source", isDirectory: true)
            : Workspace.ensureSourceDir(notesDir, ext: noteID)
    }

    /// 保存任意文件附件；自动按扩展名归类到 source/<type>/
    @discardableResult
    func saveAttachment(_ data: Data, fileName: String, noteID: String) -> String? {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let type = Workspace.sourceFolder(for: ext)
        let dir = Workspace.ensureSourceDir(notesDir, ext: ext)
        var name = Workspace.uniqueName(in: dir, fileName: fileName)
        do {
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
            return "source/\(type)/\(name)"
        } catch {
            return nil
        }
    }

    struct AttachmentItem: Identifiable, Equatable {
        var id: String { url.path }
        let url: URL
        let name: String
        let size: Int
        let isImage: Bool
        let mtime: Date
    }

    /// 当前文件全部附件：图片（images/ 兼容旧库）+ 文件（attachments/）
    func listAttachments(for noteID: String) -> [AttachmentItem] {
        // 工作台语义：附件面板 = 全工作台资源库扫描（source/<type>/ 全部资源，按修改时间倒序）
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"]
        var out: [AttachmentItem] = []
        let src = notesDir.appendingPathComponent("source", isDirectory: true)
        guard let typeDirs = try? FileManager.default.contentsOfDirectory(
            at: src, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        for dir in typeDirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            if let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) {
                for url in files {
                    let s = (try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])) ?? URLResourceValues()
                    out.append(AttachmentItem(url: url, name: url.lastPathComponent,
                                              size: s.fileSize ?? 0,
                                              isImage: imageExts.contains(url.pathExtension.lowercased()),
                                              mtime: s.contentModificationDate ?? .distantPast))
                }
            }
        }
        return out.sorted { $0.mtime > $1.mtime }
    }

    func deleteAttachment(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - 新建 / 删除 / 重命名

    /// 新建文件（空名）→ 根目录“无标题.md”，随后内联命名（VSCode）
    func createNote() {
        flush()
        let note = Note(id: _L("无标题", "Untitled") + ".md", title: _L("无标题", "Untitled"))
        ioQueue.sync { writeNote(note) }
        reloadIndex()
        openNote(note.id)
        // A：新建「无标题」草稿 → AI 自动命名（若已配置；延迟等用户可能先手输）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.index.first(where: { $0.id == note.id })?.title == _L("无标题", "Untitled") else { return }
            self.autoTitle(for: note.id)
        }
    }

    /// 指定标题与目录新建（文件夹内新建）；同目录同名文件存在 → 拒绝（返回 false）
    @discardableResult
    func createNote(title: String, category: String) -> Bool {
        // 不再自动补全 .md 后缀：文件即笔记，文件名 = 输入原样（只有用户显式输入才带扩展名）
        var name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = _L("无标题", "Untitled") }
        name = name.replacingOccurrences(of: "/", with: "-")   // 防路径越级
        let dir = category.isEmpty ? notesDir : notesDir.appendingPathComponent(category, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path) else {
            return false
        }
        flush()
        let id = category.isEmpty ? name : (category + "/" + name)
        ioQueue.sync {
            let url = noteURL(id)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
        reloadIndex()
        openNote(id)
        return true
    }

    /// 同目录下是否存在同名文件（排除 exemptID）
    func hasDuplicateTitle(_ title: String, category: String, excluding exemptID: String? = nil) -> Bool {
        index.contains {
            $0.category == category && $0.title == title && $0.id != exemptID
        }
    }

    func renameCurrentTo(_ title: String) {
        currentTitle = title
        if let sel = loadedNoteID, let i = index.firstIndex(where: { $0.id == sel }) {
            index[i].title = title
        }
        markDirty()
    }

    /// 重命名文件 = 物理改名（同目录同名 → 拒绝返回 false）；当前打开的仅改标题（保存时写原名）
    @discardableResult
    func renameNote(_ id: String, to title: String) -> Bool {
        let ext = noteURL(id).pathExtension
        let newName = ext.isEmpty ? title : title + "." + ext
        let dest = noteURL(id).deletingLastPathComponent().appendingPathComponent(newName)
        guard dest.path != noteURL(id).path, !FileManager.default.fileExists(atPath: dest.path) else { return false }
        do {
            try FileManager.default.moveItem(at: noteURL(id), to: dest)
        } catch {
            return false
        }
        if id == selectedNoteID {
            loadedNoteID = Workspace.relativeID(dest, root: notesDir)
            if let i = openTabs.firstIndex(of: id) {
                openTabs[i] = Workspace.relativeID(dest, root: notesDir)
            }
            persistTabs()
            currentTitle = title
        }
        reloadIndex()
        return true
    }

    @discardableResult
    func deleteNote(_ id: String) -> Bool {
        deleteNotes(ids: [id]) > 0
    }

    /// 删除当前选择集（多选优先，兜底当前打开文件）
    @discardableResult
    func deleteSelection() -> Int {
        var ids = Array(selectedNoteIDs)
        if ids.isEmpty, let cur = selectedNoteID { ids = [cur] }

        return deleteNotes(ids: ids)
    }

    /// 批量删除 → 全部进回收站；删除后自动选中列表下一个文件（无则清空选择）；
    /// 删除集留档供"撤销"一键恢复
    @discardableResult
    func deleteNotes(ids: [String]) -> Int {
        flush()
        // 工作台语义：删除 = 物理删除（回收站机制已移除；确认弹窗在视图层）
        let before = filteredIndex
        let deletedSet = Set(ids)
        var count = 0
        for id in ids {
            do {
                try FileManager.default.removeItem(at: noteURL(id))
                count += 1
            } catch {
                showHint(_L("删除失败：\(noteURL(id).lastPathComponent)", "Failed to delete: \(noteURL(id).lastPathComponent)"))
            }
        }
        if selectedNoteID != nil, ids.contains(selectedNoteID ?? "") {
            selectedNoteID = nil
            loadedNoteID = nil
            workingText = ""
        }
        var removedAny = false
        for id in ids {
            if let i = openTabs.firstIndex(of: id) { openTabs.remove(at: i); removedAny = true }
        }
        if removedAny { persistTabs() }
        // VSCode 游标：选中被删项位置的下一个文件；后一项也被删或无 → 无选中
        if let idx = before.firstIndex(where: { deletedSet.contains($0.id) }) {
            let next = before[min(idx + 1, before.count - 1)]
            if !deletedSet.contains(next.id) {
                selectedNoteIDs = [next.id]   // onChange → 打开下一篇
            } else {
                selectedNoteIDs = []
            }
        } else {
            selectedNoteIDs = []
        }
        reloadIndex()
        return count
    }

    // MARK: - 删除撤销（浮动条）

    @ObservationIgnored
    private var lastDeleted: [TrashItem] = []
    private(set) var showUndoToast = false
    @ObservationIgnored
    private var undoTimer: Task<Void, Never>?

    private func beginUndoToast() {
        showUndoToast = true
        undoTimer?.cancel()
        undoTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.showUndoToast = false
        }
    }

    /// 撤销删除：恢复最近一次批量删除的全部文件（复用回收站恢复）
    func undoDelete() {
        showHint(_L("回收站已停用：删除即物理删除，无法撤销", "Trash is disabled: deletions are permanent and cannot be undone"))
    }

    // MARK: - 回收站（工作机制已按产品决策移除；签名保留，均为空转）

    struct TrashItem: Identifiable {
        var id: String { storedName }
        let storedName: String
        let noteID: String
        let title: String
        let deletedAt: Date
    }

    private func moveNoteToTrash(_ id: String) {
        try? FileManager.default.removeItem(at: noteURL(id))
    }

    func listTrash() -> [TrashItem] { [] }

    @discardableResult
    func restoreTrash(_ item: TrashItem) -> Bool { false }

    func purgeTrash(_ item: TrashItem) {}

    func emptyTrash() {}

    // MARK: - 索引过滤 / 选择 / 目录（文件夹）操作

    /// 搜索过滤：标题命中优先，其次正文命中（工作台语义：全文检索缓存 = 文件内容）
    var filteredIndex: [NoteIndexItem] {
        var items = index
        if !categoryFilter.isEmpty && categoryFilter != "=none" {
            items = items.filter { $0.category == categoryFilter }
        }
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        let words = q.split(separator: " ").map { String($0).lowercased() }
        var titleHits: [NoteIndexItem] = []
        var contentHits: [NoteIndexItem] = []
        for item in items {
            let titleLower = item.title.lowercased()
            let contentLower = String(data: fullTextCache[item.id] ?? Data(), encoding: .utf8)?.lowercased() ?? ""
            let allContained = words.allSatisfy { titleLower.contains($0) || contentLower.contains($0) }
            guard allContained else { continue }
            if words.allSatisfy({ titleLower.contains($0) }) {
                titleHits.append(item)
            } else {
                contentHits.append(item)
            }
        }
        return titleHits + contentHits
    }

    func moveSelection(_ delta: Int) {
        let items = filteredIndex
        guard !items.isEmpty else { return }
        let cur = selectedNoteID
        let idx = cur.flatMap { c in items.firstIndex(where: { $0.id == c }) } ?? 0
        let next = min(max(0, idx + delta), items.count - 1)
        openNote(items[next].id)
    }

    var selectedNote: NoteIndexItem? {
        index.first { $0.id == selectedNoteID }
    }

    /// 新建文件夹 = 工作台真实目录（同名拒绝）
    func createCategory(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return false }
        let dir = notesDir.appendingPathComponent(n, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: dir.path) else { return false }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch { return false }
        loadCategories()
        reloadIndex()
        return true
    }

    /// 移除空文件夹（不含 source 与点目录）
    func removeEmptyCategories() {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: notesDir, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for u in items where !u.lastPathComponent.hasPrefix(".")
            && u.lastPathComponent != "source" {
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: u.path), contents.isEmpty {
                try? FileManager.default.removeItem(at: u)
            }
        }
        loadCategories()
        reloadIndex()
    }

    /// 重命名文件夹 = 物理改名（同层同名拒绝；更新索引 id 前缀）
    func renameCategory(_ id: String, to name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return false }
        let src = notesDir.appendingPathComponent(id, isDirectory: true)
        let dest = notesDir.appendingPathComponent(n, isDirectory: true)
        guard FileManager.default.fileExists(atPath: src.path),
              !FileManager.default.fileExists(atPath: dest.path) else { return false }
        do {
            try FileManager.default.moveItem(at: src, to: dest)
        } catch { return false }
        // 重映射 openTabs/selected（id 前缀替换）
        let prefix = id + "/"
        func remap(_ old: String) -> String {
            old.hasPrefix(prefix) ? (n + "/" + old.dropFirst(prefix.count)) : old
        }
        openTabs = openTabs.map(remap)
        persistTabs()
        if let sel = selectedNoteID {
            selectedNoteID = remap(sel)
            if let loaded = loadedNoteID { loadedNoteID = remap(loaded) }
        }
        reloadIndex()
        loadCategories()
        return true
    }

    /// 删除文件夹：内容（文件/子目录）移到工作台根，随后删除空目录（与旧行为一致，避免误删数据）
    func deleteCategory(_ id: String) {
        let dir = notesDir.appendingPathComponent(id, isDirectory: true)
        if let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for u in contents {
                try? FileManager.default.moveItem(at: u, to: notesDir.appendingPathComponent(u.lastPathComponent))
            }
        }
        try? FileManager.default.removeItem(at: dir)
        if categoryFilter == id { categoryFilter = "" }
        reloadIndex()
        loadCategories()
    }

    /// 移动文件到指定目录（物理移动；id 重映射）
    func assignCategory(_ noteID: String, _ catID: String) -> Bool {
        let src = noteURL(noteID)
        guard FileManager.default.fileExists(atPath: src.path) else { return false }
        let dir = catID.isEmpty ? notesDir : notesDir.appendingPathComponent(catID, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = Workspace.uniqueName(in: dir, fileName: src.lastPathComponent)
        let dest = dir.appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: src, to: dest)
        } catch {
            return false
        }
        let newID = Workspace.relativeID(dest, root: notesDir)
        if noteID == selectedNoteID {
            loadedNoteID = newID
            if let i = openTabs.firstIndex(of: noteID) { openTabs[i] = newID }
            persistTabs()
        }
        setConflictResolved(fingerprint: currentFileFingerprint(newID))
        reloadIndex()
        return true
    }

    // MARK: - 外部修改冲突保护（C-04）

    enum ConflictResolution: Sendable {
        /// 重新载入外部版本（当前内容先写入历史快照）
        case reload
        /// 保留我的内容（外部版本先写入历史快照，再覆盖写盘）
        case keepMine
        /// 稍后处理：自动保存暂停，退出/切换时另存副本
        case later
    }

    /// 当前磁盘指纹（MD5(文件数据)）；文件缺失返回 nil
    private func currentFileFingerprint(_ id: String) -> String? {
        guard let data = try? Data(contentsOf: noteURL(id)) else { return nil }
        return Self.md5hex(data)
    }

    nonisolated static func md5hex(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// reloadIndex 收尾调用：对比已打开文件的磁盘指纹，外部改写 → 首次弹提示
    private func detectExternalConflict(diskFingerprint: String?) {
        guard let id = loadedNoteID else { return }
        guard let disk = diskFingerprint,
              let known = loadedExternalFingerprint,
              known != disk else { return }
        loadedExternalFingerprint = disk
        if !conflictHandled {
            externalConflict = true
        }
    }

    /// 用户选择后的处理入口（三选）
    func resolveExternalConflict(_ choice: ConflictResolution) {
        guard let id = loadedNoteID else {
            externalConflict = false
            conflictHandled = false
            return
        }
        switch choice {
        case .reload:
            // 我的当前内容先进快照，再载入外部版本
            snapshotWorkingVersion(id)
            if let note = ioQueue.sync(execute: { readNote(id) }) {
                workingText = note.content
                currentTitle = note.title
                documentRevision += 1
            }
            dirty = false
            setConflictResolved(fingerprint: currentFileFingerprint(id))
            reloadIndex()
        case .keepMine:
            // 外部版本先进快照，我的内容写盘（外部内容在版本中可找回）
            ioQueue.sync { snapshotNote(id) }
            let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            ioQueue.sync {
                var note = readNote(id) ?? Note(id: id, title: title)
                note.title = title
                note.content = workingText
                note.updated = Self.isoNow()
                writeNote(note)
            }
            dirty = false
            lastSavedAt = Date()
            setConflictResolved(fingerprint: currentFileFingerprint(id))
            reloadIndex()
        case .later:
            conflictHandled = true
            showHint(_L("文件已被外部修改：自动保存已暂停，请处理冲突或另存副本", "File was modified externally: autosave is paused. Please resolve the conflict or save a copy."))
        }
        externalConflict = false
    }

    /// 重新打开冲突处理弹窗（状态栏入口）
    func reopenConflictPrompt() {
        guard loadedNoteID != nil else { return }
        externalConflict = true
    }

    private func setConflictResolved(fingerprint: String?) {
        loadedExternalFingerprint = fingerprint
        externalConflict = false
        conflictHandled = false
    }

    /// 把编辑器内存中的内容写成一份快照（冲突「重新载入」前，保住用户改动）
    private func snapshotWorkingVersion(_ id: String) {
        // 内存工作文本 → .md 快照（工作台语义：未保存内容只在编辑器里）
        let safeID = id.replacingOccurrences(of: "/", with: "__")
        let verDir = notesDir.appendingPathComponent(".versions/\(safeID)", isDirectory: true)
        ioQueue.sync {
            try? FileManager.default.createDirectory(at: verDir, withIntermediateDirectories: true)
            let ts = String(Int(Date().timeIntervalSince1970 * 1000))
            let dest = verDir.appendingPathComponent(ts + ".md")
            try? FileManager.default.removeItem(at: dest)
            try? workingText.write(to: dest, atomically: true, encoding: .utf8)
            pruneVersions(verDir)
        }
    }

    /// AI 文件代理：写入后同步（打开中的文件 → 即时上屏；否则刷新索引）
    func agentDidWriteFile(_ id: String) {
        guard id == loadedNoteID else {
            reloadIndex()
            return
        }
        if let note = ioQueue.sync(execute: { readNote(id) }) {
            workingText = note.content
            currentTitle = note.title
            dirty = false
            documentRevision += 1
        }
        loadedExternalFingerprint = currentFileFingerprint(id)
        reloadIndex()
    }

    /// AI 文件代理：当前文件被改名/移动 → 编辑器切换到新路径
    func reopenAs(_ id: String) {
        guard loadedNoteID != nil else { return }
        closeTab(loadedNoteID ?? "")
        openNote(id)
    }
    // MARK: - 历史版本

    struct VersionInfo: Identifiable {
        var id: String { ts }
        let ts: String
        let updated: String
        let size: Int
    }

    func listVersions(_ noteID: String) -> [VersionInfo] {
        let safeID = noteID.replacingOccurrences(of: "/", with: "__")
        let dir = notesDir.appendingPathComponent(".versions/\(safeID)", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "md" }.compactMap { f in
            let ts = f.deletingPathExtension().lastPathComponent
            let size = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return VersionInfo(ts: ts, updated: ts, size: size)
        }.sorted { $0.ts > $1.ts }
    }

    func versionNote(_ noteID: String, _ ts: String) -> Note? {
        let safeID = noteID.replacingOccurrences(of: "/", with: "__")
        let url = notesDir.appendingPathComponent(".versions/\(safeID)/\(ts).md")
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Note(id: noteID, title: Workspace.title(for: noteURL(noteID)), content: content)
    }

    func restoreVersion(_ noteID: String, _ ts: String) {
        guard let v = versionNote(noteID, ts) else { return }
        flush()
        ioQueue.sync {
            try? FileManager.default.createDirectory(at: noteURL(noteID).deletingLastPathComponent(), withIntermediateDirectories: true)
            try? v.content.write(to: noteURL(noteID), atomically: true, encoding: .utf8)
        }
        reloadIndex()
        if selectedNoteID == noteID {
            workingText = v.content
            currentTitle = v.title
            dirty = false
            documentRevision += 1
            setConflictResolved(fingerprint: currentFileFingerprint(noteID))
        }
    }

    // MARK: - 预览图片内联

    /// 预览前把文件目录内的相对路径图片转成 data URL。
    /// WebKit 的 file:// 授权只覆盖 bundle（loadFileURL allowingReadAccessTo 范围），
    /// 跨目录读取 file:// 图片会被拦截 —— 内联一次到位且离线可用。
    private let maxInlineSize = 5 * 1024 * 1024

    /// dataURL 缓存：key=相对路径，mtime 未变则复用 —— 避免打字时每 180ms 重读大图。
    /// LRU 上限 24 张（防无界驻留 → Web Content 内存）。
    @ObservationIgnored
    private var imageInlineCache: [String: (mtime: Date?, dataURL: String)] = [:]
    @ObservationIgnored
    private var imageLRUOrder: [String] = []

    func inlinePreviewImages(_ md: String) -> String {
        guard let re = ImgInline.re, md.contains("](") else { return md }
        let ns = md as NSString
        let matches = re.matches(in: md, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return md }
        var result = md
        for m in matches.reversed() {
            let src = ns.substring(with: m.range(at: 2))
            if let dl = cachedDataURL(for: src) {
                replaceImages(src: src, dataURL: dl, result: &result)
            }
        }
        // 远程图（http/https）：命中缓存即替换，未命中的则后台下载
        return inlineRemoteImages(result)
    }

    /// 本地图片 → dataURL（mtime 缓存 + 重采样 + LRU 24）
    func cachedDataURL(for src: String) -> String? {
        guard !(src as NSString).contains(" ") else { return nil }
        let url = notesDir.appendingPathComponent(src)
        let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if let hit = imageInlineCache[src], hit.mtime == mtime { return hit.dataURL }
        if mtime == nil && !FileManager.default.fileExists(atPath: url.path) { return nil }
        guard let data = try? Data(contentsOf: url), data.count < maxInlineSize,
              let mime = Self.mimeType(for: src) else { return nil }
        let payload = Self.balancedImageData(data, mime: mime)
        let dataURL = "data:\(mime);base64,\(payload.base64EncodedString())"
        imageInlineCache[src] = (mtime, dataURL)
        imageLRUOrder.append(src)
        while imageLRUOrder.count > 24 { imageInlineCache.removeValue(forKey: imageLRUOrder.removeFirst()) }
        return dataURL
    }

    // MARK: - 图片注册表（渲染性能：文本不内联，data URL 只随版本增量下发一次）

    /// 注册表：相对路径 → dataURL（本地图 + 已缓存远程图）
    @ObservationIgnored
    private(set) var imageRegistry: [String: String] = [:]
    /// 注册表版本：变化时 PreviewView 增量下发新条目（每帧渲染只传 markdown 原文）
    private(set) var imageRegistryVersion = 0

    // MARK: - 自定义字体库（导入 / 注册表）

    /// 已导入字体（设置页列表 + 源码/预览 Picker）
    private(set) var customFonts: [CustomFonts.Entry] = []
    /// 字体注册表：家族名 → data URL（预览 @font-face；WebContent 进程读不到宿主注册的字体）
    private(set) var fontRegistry: [String: String] = [:]
    /// 注册表版本：变化时 PreviewView 增量下发（同图片注册表机制）
    private(set) var fontRegistryVersion = 0

    /// 启动时扫描字体库：注册 + 重建 data URL 注册表
    func loadCustomFontLibrary() {
        customFonts = CustomFonts.loadLibrary()
        var reg: [String: String] = [:]
        for e in customFonts {
            let url = CustomFonts.libraryDir().appendingPathComponent(e.fileName)
            if let data = try? Data(contentsOf: url) {
                reg[e.family] = "data:\(e.mime);base64," + data.base64EncodedString()
            }
        }
        if reg != fontRegistry {
            fontRegistry = reg
            fontRegistryVersion += 1
        }
    }

    /// 导入字体文件（设置页「导入字体…」）；结果以 Toast 反馈
    @discardableResult
    func importCustomFont(from url: URL) -> Bool {
        switch CustomFonts.importFont(from: url) {
        case .ok(let e):
            loadCustomFontLibrary()
            showHint(_L("已导入字体「\(e.family)」", "Imported font \"\(e.family)\""))
            return true
        case .duplicate:
            showHint(_L("字体已存在，无需重复导入", "Font already exists; no need to import it again"))
            return false
        default:
            showHint(_L("无法导入：\(url.lastPathComponent)", "Cannot import: \(url.lastPathComponent)"))
            return false
        }
    }

    /// 删除已导入字体（设置页列表）
    func removeCustomFont(_ entry: CustomFonts.Entry) {
        CustomFonts.remove(entry)
        loadCustomFontLibrary()
    }

    /// 收集当前 md 的图像到注册表；未缓存远程图触发下载。不改动文本。
    @discardableResult
    func prepareImageRegistry(_ md: String) -> Int {
        // 幂等短路（纯收益）：previewPane 每次 body 求值都调本方法 —— 同一 md 直接返回，
        // 省下整串图片正则扫描 + 每张图的磁盘 stat。所有会影响图片状态的路径都会
        // 显式 `invalidatePreparedImages()`（远程下载完成 / FS 外部变更），行为零差异。
        if preparedMD == md { return imageRegistryVersion }
        guard let re = ImgInline.re, md.contains("](") else { return imageRegistryVersion }
        preparedMD = md
        let ns = md as NSString
        let matches = re.matches(in: md, range: NSRange(location: 0, length: ns.length))
        var changed = false
        for m in matches {
            let src = ns.substring(with: m.range(at: 2))
            guard src.hasSuffix(".png") || src.hasSuffix(".jpg") || src.hasSuffix(".jpeg")
                || src.hasSuffix(".gif") || src.hasSuffix(".webp") || src.hasSuffix(".heic") || src.hasSuffix(".bmp")
                || src.hasSuffix(".tiff") || src.hasSuffix(".tif") else { continue } // 媒体/文档交给 JS 处理
            if let dl = cachedDataURL(for: src) {
                if imageRegistry[src] != dl { imageRegistry[src] = dl; changed = true }
            }
        }
        // 远程
        if let re2 = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\((https?://[^)\s]+)\)"#) {
            let ms = re2.matches(in: md, range: NSRange(location: 0, length: ns.length))
            var pending: [String] = []
            for m in ms {
                let u = ns.substring(with: m.range(at: 1))
                if let dl = remoteDataURL(for: u) {
                    if imageRegistry[u] != dl { imageRegistry[u] = dl; changed = true }
                } else {
                    pending.append(u)
                }
            }
            scheduleRemoteDownloads(pending)
        }
        if changed {
            imageRegistryVersion += 1
        }
        return imageRegistryVersion
    }

    /// 图片瘦身：宽 >1600px 时重采样到 1600（非透明转 JPEG q0.8；透明保 PNG）。
    /// 编码走 CGImageDestination；三级回退（缩略编码 → 原图编码 → 原始数据），任何环境都返回有效图像字节。
    nonisolated static func balancedImageData(_ data: Data, mime: String) -> Data {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return data }
        let maxW = 1600
        let info = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let width = (info?[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let alpha = (info?[kCGImagePropertyHasAlpha] as? Bool) ?? false

        if width > maxW {
            let opts = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxW,
            ] as CFDictionary
            if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts),
               let encoded = encodeCG(cg, jpeg: !alpha) {
                return encoded
            }
        } else if data.count > 2_500_000, !alpha {
            if let cg = CGImageSourceCreateImageAtIndex(src, 0, nil),
               let encoded = encodeCG(cg, jpeg: true) {
                return encoded
            }
        }
        // 末级：原图不允许回退丢失 → 返回原始字节
        if data.count > 0, CGImageSourceCreateImageAtIndex(src, 0, nil) != nil {
            return data
        }
        return data
    }

    /// CGImage → JPEG/PNG（CoreGraphics Destination；失败返回 nil 由调用方回退）
    nonisolated static func encodeCG(_ cg: CGImage, jpeg: Bool) -> Data? {
        let out = NSMutableData()
        let type = jpeg ? UTType.jpeg : UTType.png
        guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
        let props: [CFString: Any] = jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.8] : [:]
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out.length > 0 ? out as Data : nil
    }

    private func replaceImages(src: String, dataURL: String, result: inout String) {
        // 引用形如 ![...](src)，把 src 整体替换为 dataURL（双引号形式也在覆盖范围）。
        // title="img:<src>" 保留原始相对路径：预览点击 → JS 读 title 回传宿主打开原图（C-06）。
        result = result.replacingOccurrences(
            of: "](\(src))", with: "](\(dataURL) \"img:\(src)\")",
            options: .literal)
    }

    // MARK: - 远程图片（http(s) 引用：下载 → dataURL 缓存 → 版本号触发重渲染）

    @ObservationIgnored
    private var remoteURLData: [String: String] = [:]
    @ObservationIgnored
    private var remoteLRUOrder: [String] = []
    private(set) var imageCacheVersion = 0
    @ObservationIgnored
    private let remoteQueue = DispatchQueue(label: "marknote.remote", qos: .utility)
    private let remoteMax = 32

    private var remoteCacheDir: URL {
        notesDir.appendingPathComponent("assets/.cache", isDirectory: true)
    }

    /// 内联时对远程图：有缓存直接替换；否则发起后台下载（下载完成 → 版本号+1 → 预览自动重渲染）
    func inlineRemoteImages(_ md: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\((https?://[^)\s]+)\)"#) else { return md }
        let ns = md as NSString
        let matches = re.matches(in: md, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return md }
        var result = md
        var pending: [String] = []
        for m in matches.reversed() {
            let urlStr = ns.substring(with: m.range(at: 1))
            if let dl = remoteDataURL(for: urlStr) {
                result = result.replacingOccurrences(of: "](\(urlStr))", with: "](\(dl) \"img:\(urlStr)\")", options: .literal)
                pending.append(urlStr)
            }
        }
        scheduleRemoteDownloads(pending)
        return result
    }

    private func remoteDataURL(for urlString: String) -> String? {
        if let hit = remoteURLData[urlString] { return hit }
        let file = remoteCacheDir.appendingPathComponent(Self.md5name(urlString))
        guard let data = try? Data(contentsOf: file), data.count <= 8 * 1024 * 1024 else { return nil }
        let mime = Self.mimeType(for: urlString) ?? "image/png"
        let payload = Self.balancedImageData(data, mime: mime)
        let dl = "data:\(mime);base64,\(payload.base64EncodedString())"
        remoteURLData[urlString] = dl
        remoteLRUOrder.append(urlString)
        while remoteLRUOrder.count > 16 { remoteURLData.removeValue(forKey: remoteLRUOrder.removeFirst()) }
        return dl
    }

    private func scheduleRemoteDownloads(_ urls: [String]) {
        guard !urls.isEmpty else { return }
        var newOnes: [String] = []
        for u in urls.prefix(remoteMax) where remoteURLData[u] == nil {
            if !FileManager.default.fileExists(atPath: remoteCacheDir.appendingPathComponent(Self.md5name(u)).path) {
                newOnes.append(u)
            }
        }
        guard !newOnes.isEmpty else { return }
        remoteQueue.async { [weak self] in
            guard let self else { return }
            let semaphore = DispatchSemaphore(value: 4)
            for u in newOnes {
                semaphore.wait()
                guard let url = URL(string: u) else {
                    semaphore.signal()
                    continue
                }
                URLSession.shared.dataTask(with: url) { data, response, _ in
                    defer { semaphore.signal() }
                    guard let data, data.count <= 8 * 1024 * 1024,
                          let status = response as? HTTPURLResponse, status.statusCode == 200 else { return }
                    let mime = Self.mimeType(for: u) ?? "image/png"
                    let dl = "data:\(mime);base64,\(data.base64EncodedString())"
                    self.ioQueue.sync {
                        try? FileManager.default.createDirectory(at: self.remoteCacheDir, withIntermediateDirectories: true)
                        try? data.write(to: self.remoteCacheDir.appendingPathComponent(Self.md5name(u)), options: .atomic)
                    }
                    // 主线程登记并触发预览重渲染（本轮渲染将替换为 dataURL）；
                    // LRU：远程图最多驻留 16 张（>16 张时新图不被内联，避免无界增长）
                    DispatchQueue.main.async {
                        let payload = NotesStore.balancedImageData(data, mime: mime)
                        let slimURL = "data:\(mime);base64,\(payload.base64EncodedString())"
                        self.remoteURLData[u] = slimURL
                        self.imageCacheVersion += 1
                        self.invalidatePreparedImages() // 远程图就绪 → 下次 prepare 需重扫入库
                    }
                }.resume()
            }
        }
    }

    /// 远程图磁盘缓存文件（预览点击 remote 图 → 本端放大走缓存文件）
    func remoteCachedFileURL(for urlString: String) -> URL? {
        let f = remoteCacheDir.appendingPathComponent(Self.md5name(urlString))
        return FileManager.default.fileExists(atPath: f.path) ? f : nil
    }

    nonisolated static func md5name(_ s: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".img"
    }

    nonisolated static func mimeType(for path: String) -> String? {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
                "gif": "image/gif", "webp": "image/webp", "heic": "image/heic",
                "bmp": "image/bmp", "tiff": "image/tiff", "tif": "image/tiff"][ext]
    }

    // MARK: - 轻提示（非模态：任意点击/自动消失）
    // hintMessage 声明在顶部状态区；此处仅 token/计时。

    @ObservationIgnored
    private(set) var hintToken = 0
    @ObservationIgnored
    private var hintTask: Task<Void, Never>?

    func showHint(_ text: String) {
        hintMessage = text
        hintToken += 1
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard let self, !Task.isCancelled else { return }
            self.hintMessage = nil
        }
    }

    func hideHint() {
        hintTask?.cancel()
        hintMessage = nil
    }

    // MARK: - 主题

    /// 主题变更计数器：UserDefaults 不触发 SwiftUI，view 读它感知主题切换
    private(set) var themeVersion = 0

    /// 切换主题：持久化 + themeVersion 递增（ContentView 以 .id 整体重建，深浅/色调生效）
    func setTheme(_ t: Theme) {
        UserDefaults.standard.set(t.rawValue, forKey: "theme")
        themeVersion += 1
    }

    // MARK: - AI 自动命名（云端 API；仅当前文件、仅显式触发）

    /// 为「无标题/草稿」文件自动生成标题（新建后/手动触发）；
    /// 空内容（纯空白）静默跳过；模板词结果自动重试一次，仍不合规则静默
    func autoTitle(for id: String) {
        // 轻量开关：AI 自动命名可关闭（省 API 配额）；设置页「通用」默认开
        guard UserDefaults.standard.object(forKey: "aiAutoTitle") as? Bool ?? true else { return }

        guard LLM.configured else { return }
        let ext = (id as NSString).pathExtension.lowercased()
        // 图片 → 视觉模型命名（文字不能概括画面）
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff", "svg"]
        if imageExts.contains(ext) {
            Task { [weak self] in
                guard let self else { return }
                guard let name = await Self.visionNameImage(at: self.noteURL(id)) else {
                    self.showHint(_L("图片命名失败（带图重试 / 检查模型）", "Failed to name image (retry with the image included / check the model)"))
                    return
                }
                await MainActor.run {
                    self.applyAITitle(id, name: name)
                }
            }
            return
        }
        let content = (try? String(contentsOf: noteURL(id), encoding: .utf8)) ?? ""
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return // 空内容不命名（静默）
        }
        let baseTitle = Workspace.title(for: noteURL(id))
        Task { [weak self] in
            // 一次正规 + 黑名单命中时的二次直白重试
            var title = try? await LLM.suggestTitle(content: content)
            if let t = title, !LLM.isValidTitle(t) {
                title = try? await LLM.suggestTitleStrict(content: content)
            }
            guard let finalTitle = title, LLM.isValidTitle(finalTitle) else {
                return // 静默：不合规不打扰
            }
            await MainActor.run {
                guard let self, self.index.contains(where: { $0.id == id }) else { return }
                let current = self.index.first { $0.id == id }?.title ?? baseTitle
                guard current == "无标题" || current == baseTitle else { return }
                self.applyAITitle(id, name: finalTitle)
            }
        }
    }

    /// 图片 → 视觉模型（压缩 ≤1280px JPEG base64）→ 名称
    @MainActor
    private static func visionNameImage(at url: URL) async -> String? {
        guard let img = NSImage(contentsOf: url),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, 1280.0 / CGFloat(max(cg.width, cg.height)))
        let ctx = CGContext(data: nil, width: Int(CGFloat(cg.width) * scale), height: Int(CGFloat(cg.height) * scale),
                            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
        guard let out = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: out)
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else { return nil }
        return try? await LLM.suggestImageName(data: jpeg, mime: "image/jpeg")
    }

    /// 落名（冲突警示；成功后提示）
    @MainActor
    private func applyAITitle(_ id: String, name: String) {
        guard self.index.contains(where: { $0.id == id }) else { return }
        let pretty = LLM.sanitizeFileNameTitle(name)
        if self.renameNote(id, to: pretty) {
            self.showHint(_L("已命名为：「\(pretty)」", "Named as: \"\(pretty)\""))
        } else {
            self.showHint(_L("命名发生同名冲突，请手动调整", "A name conflict occurred; please adjust it manually"))
        }
    }

    // MARK: - 多工作台（历史目录列表：切换/移除）

    /// 历史工作台目录（首项 = 最近一次；自动去重）
    private(set) var workspaceRoots: [String] = []

    private static let rootsKey = "workspaceRoots"

    /// 记入历史（去重、置顶、持久化）
    private func rememberWorkspace(_ path: String) {
        workspaceRoots.removeAll { $0 == path }
        workspaceRoots.insert(path, at: 0)
        if workspaceRoots.count > 8 { workspaceRoots = Array(workspaceRoots.prefix(8)) }
        if let data = try? JSONEncoder().encode(workspaceRoots) {
            UserDefaults.standard.set(data, forKey: Self.rootsKey)
        }
    }

    /// 切换到历史工作台（不存在的目录自动剔除）
    func switchWorkspace(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            workspaceRoots.removeAll { $0 == path }
            showHint(_L("工作台目录不存在：\(path)", "Workspace directory does not exist: \(path)"))
            return
        }
        notesDir = URL(fileURLWithPath: path, isDirectory: true)
        loadedNoteID = nil
        selectedNoteID = nil
        workingText = ""
        currentTitle = ""
        showHint(_L("已切换工作台", "Workspace switched"))
    }

    /// 从历史移除（当前在使用中的目录不允许移除）
    func removeWorkspace(_ path: String) {
        guard path != notesDir.path else { return }
        workspaceRoots.removeAll { $0 == path }
        if let data = try? JSONEncoder().encode(workspaceRoots) {
            UserDefaults.standard.set(data, forKey: Self.rootsKey)
        }
    }

    // MARK: - 目录选择

    /// 弹出面板切换文件目录（工作台语义：历史目录记忆 + 可多工作台）
    func chooseNotesDirectory() {
        flush()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = _L("选择文件目录（可以直接选 start 项目的 notes 目录）", "Choose a folder for your files (you can directly select the notes directory of the start project)")
        panel.directoryURL = notesDir
        if panel.runModal() == .OK, let url = panel.url {
            notesDir = url
            loadCategories()
        }
    }

    // MARK: - 外部文件变更监听（start 端或 Finder 修改同一目录时即时刷新）

    /// 每 60s 心率校验 watch 是否仍有效（fd 失效时重链）
    @ObservationIgnored
    private var watchHeartbeat: Timer?

    private func startWatch() {
        watchSource?.cancel()
        // 心跳：watch fd 失效时（目录被整体移动等）每 60s 兜底重链
        watchHeartbeat?.invalidate()
        watchHeartbeat = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, let src = self.watchSource else {
                DispatchQueue.main.async { self?.reloadIndex() }
                return
            }
            if src.isCancelled {
                DispatchQueue.main.async {
                    self.startWatch()
                    self.reloadIndex()
                }
            }
        }
        let fd = open(notesDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete], queue: ioQueue)
        src.setEventHandler { [weak self] in
            self?.reloadWorkItem?.cancel()
            let item = DispatchWorkItem { self?.reloadIndex() }
            self?.reloadWorkItem = item
            self?.ioQueue.asyncAfter(deadline: .now() + 0.5, execute: item)
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watchSource = src
    }
}

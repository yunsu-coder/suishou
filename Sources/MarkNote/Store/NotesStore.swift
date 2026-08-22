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

/// 笔记数据层 —— 直接以 start 项目的 JSON 文件格式落盘：
///   <notesDir>/<id>.json            笔记本体
///   <notesDir>/.versions/<id>/<ts>.json   保存前快照（最多 10 份）
///   <notesDir>/.categories.json    分类
/// 因此笔记目录可以即指即用 start 项目的 notes/ 目录，两个应用无缝共享。
@MainActor
@Observable
final class NotesStore {

    // MARK: - 状态

    private(set) var index: [NoteIndexItem] = []
    private(set) var categories: [NoteCategory] = []
    var selectedNoteID: String?
    /// 多选（⇧/⌘+点击、⇧+方向键原生扩展）；count==1 时由视图打开笔记
    var selectedNoteIDs: Set<String> = []
    var searchQuery = ""
    /// "" = 全部；"=none" = 未分类
    var categoryFilter = ""
    var dirty = false
    var lastSavedAt: Date?
    /// 轻提示（非模态；读取失败等不打断操作）
    private(set) var hintMessage: String?

    var notesDir: URL {
        didSet {
            UserDefaults.standard.set(notesDir.path, forKey: Self.kDirKey)
            flush()
            reloadIndex()
            startWatch()
        }
    }

    /// 当前编辑中的文本（编辑器是唯一写入口）
    var workingText = ""
    var currentTitle = ""
    var editorFontSize: CGFloat {
        get { CGFloat(UserDefaults.standard.double(forKey: "editorFontSize")) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "editorFontSize") }
    }
    var previewFontScale: Double {
        get { let v = UserDefaults.standard.double(forKey: "previewFontScale"); return v == 0 ? 1.0 : v }
        set { UserDefaults.standard.set(newValue, forKey: "previewFontScale") }
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
        reloadIndex()
        loadCategories()
        loadManualOrder()
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
        let app = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return app.appendingPathComponent("MarkNote/notes", isDirectory: true)
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

    func parseTime(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }

    func noteURL(_ id: String) -> URL { notesDir.appendingPathComponent(id + ".json") }

    // MARK: - 索引 / 列表

    /// 后台读目录建立索引（所有 IO 走串行队列，主线程只收结果）。
    /// 当前打开的笔记固定排在首位 —— 自动保存刷新排序时列表不再乱跳。
    func reloadIndex() {
        let dir = notesDir
        let mode = sortMode
        let order = manualOrder
        ioQueue.async { [weak self] in
            guard let self else { return }
            var items: [NoteIndexItem] = []
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
                DispatchQueue.main.async { self.index = [] }
                return
            }
            let decoder = JSONDecoder()
            for f in files where f.pathExtension == "json" && !f.lastPathComponent.hasPrefix(".") {
                guard let data = try? Data(contentsOf: f),
                      let note = try? decoder.decode(Note.self, from: data) else { continue }
                items.append(NoteIndexItem(id: note.id, title: note.title,
                                           preview: String(note.content.prefix(80)),
                                           created: note.created,
                                           updated: note.updated, category: note.category,
                                           workId: note.workId, chapterOrder: note.chapterOrder))
                // 全文搜索缓存（后台填充；保存/删除时增量维护）
                if self.fullTextCache[note.id] != data {
                    self.fullTextCache[note.id] = data
                }
            }
            // 排序：更新时间 / 创建时间 / 手动（notes/.order.json 持久化）
            switch mode {
            case .updated:
                items.sort(by: { a, b in
                    (self.parseTime(a.updated) ?? .distantPast) > (self.parseTime(b.updated) ?? .distantPast)
                })
            case .created:
                items.sort(by: { a, b in
                    let ta = self.parseTime(a.created) ?? self.parseTime(a.updated) ?? .distantPast
                    let tb = self.parseTime(b.created) ?? self.parseTime(b.updated) ?? .distantPast
                    return ta > tb
                })
            case .manual:
                let positions = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
                items.sort(by: { a, b in
                    let ai = positions[a.id] ?? Int.max
                    let bi = positions[b.id] ?? Int.max
                    if ai == bi {
                        // 都不在自定义序中 → 按更新时间兜底
                        return (self.parseTime(a.updated) ?? .distantPast) > (self.parseTime(b.updated) ?? .distantPast)
                    }
                    return ai < bi
                })
            }
            DispatchQueue.main.async {
                self.loadCategories() // 与索引一起刷新（含外部修改）
                if let sel = self.selectedNoteID, !items.contains(where: { $0.id == sel }) {
                    // 当前笔记已被外部删除：退出编辑
                    self.selectedNoteID = nil
                    self.loadedNoteID = nil
                    self.workingText = ""
                }
                self.index = items
            }
        }
    }

    /// 全文检索缓存：id → 原始数据（刷新索引时更新；用于正文搜索）
    @ObservationIgnored
    private var fullTextCache: [String: Data] = [:]

    func loadCategories() {
        let url = notesDir.appendingPathComponent(".categories.json")
        categories = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode([NoteCategory].self, from: $0) } ?? []
    }

    // MARK: - 文件级 IO（同步、串行队列）

    private func readNote(_ id: String) -> Note? {
        guard let data = try? Data(contentsOf: noteURL(id)) else { return nil }
        return try? JSONDecoder().decode(Note.self, from: data)
    }

    private func writeNote(_ note: Note) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(note) else { return }
        try? data.write(to: noteURL(note.id), options: .atomic)
    }

    private func snapshotNote(_ id: String) {
        let src = noteURL(id)
        guard FileManager.default.fileExists(atPath: src.path) else { return }
        let verDir = notesDir.appendingPathComponent(".versions/\(id)", isDirectory: true)
        try? FileManager.default.createDirectory(at: verDir, withIntermediateDirectories: true)
        let ts = String(Int(Date().timeIntervalSince1970 * 1000))
        let dest = verDir.appendingPathComponent(ts + ".json")
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: src, to: dest)
        // 只保留最近 10 份（与 start 一致）
        let vers = (try? FileManager.default.contentsOfDirectory(at: verDir, includingPropertiesForKeys: nil)) ?? []
        var jsonFiles = vers.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        while jsonFiles.count > 10, let oldest = jsonFiles.first {
            try? FileManager.default.removeItem(at: oldest)
            jsonFiles.removeFirst()
        }
    }

    // MARK: - 读取 / 保存

    /// 已装载内容的笔记（与"选中态"分离 —— 修复点击列表无法切换的致命 bug：
    /// List(selection:) 先写 selectedNoteID，onChange→openNote 时旧 guard
    /// 因 id==selectedNoteID 恒等而被永远拦截）
    private(set) var loadedNoteID: String?
    /// 文档内容版本号：每次"程序性换文档"（打开/恢复/导入）递增。
    /// 编辑器据此区分"主动切换"（store→视图）与"用户输入领先"（视图→store 回填，禁止反写）。
    @ObservationIgnored
    private(set) var documentRevision = 1

    func openNote(_ id: String) {
        guard loadedNoteID != id else { return } // 已装载同一篇 → 幂等返回
        flush()
        guard let note = ioQueue.sync(execute: { readNote(id) }) else {
            // 轻提示（不阻塞）；自愈：清选中 + 手动序幽灵 + 刷新列表
            showHint("读取失败：笔记不存在（可能已被删除）")
            selectedNoteIDs.remove(id)
            if manualOrder.contains(id) {
                manualOrder.removeAll { $0 == id }
                saveManualOrder()
            }
            reloadIndex()
            return
        }
        loadedNoteID = id
        selectedNoteID = id // 与列表状态汇合（幂等）
        workingText = note.content
        currentTitle = note.title
        dirty = false
        documentRevision += 1
        // 注意：不再重排列表 —— 打开笔记不改变用户排序
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

    /// 立即保存当前笔记（自动保存 500ms 防抖、切换笔记、退出前调用）
    func saveCurrent() {
        guard let id = selectedNoteID else { return }
        var title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty && workingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // 全新空笔记：延迟到首次有内容再落地
            if !FileManager.default.fileExists(atPath: noteURL(id).path) { return }
        }
        // 同目录同名校验：冲突时回退标题并提示
        if let item = index.first(where: { $0.id == id }),
           hasDuplicateTitle(title, category: item.category, excluding: id) {
            currentTitle = item.title
            showHint("该文件夹下已存在同名笔记（标题已还原）")
            return
        }
        let content = workingText
        ioQueue.sync {
            var note = readNote(id) ?? Note(id: id, title: title)
            note.title = title
            note.content = content
            note.updated = Self.isoNow()
            snapshotNote(id)
            writeNote(note)
        }
        dirty = false
        lastSavedAt = Date()
        reloadIndex()
    }

    /// 强制落盘（切换目录/退出前）
    func flush() {
        autosaveTask?.cancel()
        autosaveTask = nil
        if dirty { saveCurrent() }
        // 同步等待写盘完成，避免旧内容覆盖新目录
        ioQueue.sync {}
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
        panel.message = "选择要导入的 Markdown / 文本文件（每个文件成为一篇笔记）"
        if panel.runModal() == .OK {
            var last: String?
            for url in panel.urls {
                last = importNote(from: url)
            }
            if let last { openNote(last) }
        }
    }

    /// 把外部 .md/.txt 文件导入为新笔记（带回格式治理）；返回笔记 id
    @discardableResult
    func importNote(from url: URL) -> String? {
        importNote(from: url, category: nil)
    }

    /// 带目标分类的导入（category = 分类 id 或 nil=根目录）
    @discardableResult
    func importNote(from url: URL, category cat: String?) -> String? {
        var content = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .isoLatin1)) ?? ""
        // 1) BOM 剥离（用户常见的 Windows/编辑器头部乱码）
        if content.hasPrefix("\u{FEFF}") { content.removeFirst() }
        // 2) 换行规整 CRLF/CR → LF（导入前 VSCode/Windows 写法普遍）
        content = content.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        // 3) YAML front matter：解析 title，并整体移除
        var title = url.deletingPathExtension().lastPathComponent.isEmpty
            ? "导入笔记" : url.deletingPathExtension().lastPathComponent
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
        // 4) 正文首行 `# 标题` → 提升为笔记标题并移除（避免导入后标题重复）
        let firstLine = String(content.split(separator: "\n", maxSplits: 1).first ?? "")
        if firstLine.hasPrefix("# ") {
            let t = String(firstLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { title = t }
            let rest = content.dropFirst(firstLine.count)
            content = rest.hasPrefix("\n") ? String(rest.dropFirst()) : String(rest)
        }
        // 同目录同名导入自动加序号（避免同一文件夹内重复）
        let base = title
        let catID = cat ?? ""
        var n = 2
        while index.contains(where: { $0.category == catID && $0.title == title }) {
            title = "\(base) \(n)"; n += 1
        }
        let note = Note(title: title, content: content, category: cat ?? "")
        ioQueue.sync { writeNote(note) }
        reloadIndex()
        return note.id
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
        let fm = FileManager.default
        var count = 0
        let extOK: Set<String> = ["md", "markdown", "txt"]
        func ensureCategory(_ name: String) -> String {
            if let existing = categories.first(where: { $0.name == name }) { return existing.id }
            let cat = NoteCategory(name: name)
            categories.append(cat)
            writeCategories()
            return cat.id
        }
        func walk(_ dir: URL, folderName: String) {
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
            for e in entries {
                if e.hasDirectoryPath {
                    walk(e, folderName: e.lastPathComponent)
                } else if extOK.contains(e.pathExtension.lowercased()) {
                    let catID = folderName.isEmpty ? "" : ensureCategory(folderName)
                    if importNote(from: e, category: catID.isEmpty ? nil : catID) != nil { count += 1 }
                }
            }
        }
        walk(root, folderName: root.lastPathComponent)
        return count
    }

    // MARK: - 图片附件

    /// 图片根目录：notesDir/images/<noteId>/xxx.png
    func imagesDir(_ noteID: String) -> URL {
        notesDir.appendingPathComponent("images/\(noteID)", isDirectory: true)
    }

    /// 保存图片数据 → 返回 markdown 可引用的相对路径（相对 notesDir）
    @discardableResult
    func saveImage(_ data: Data, ext: String, noteID: String) -> String? {
        let dir = imagesDir(noteID)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "\(Int(Date().timeIntervalSince1970 * 1000))-\(Self.randomHex(3)).\(ext)"
        do {
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
            return "images/\(noteID)/\(name)"
        } catch {
            return nil
        }
    }

    /// 当前笔记的附件图片列表（按时间倒序）
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
        notesDir.appendingPathComponent("attachments/\(noteID)", isDirectory: true)
    }

    /// 保存任意文件附件；返回 markdown 可引用路径 images/attachments 前缀
    @discardableResult
    func saveAttachment(_ data: Data, fileName: String, noteID: String) -> String? {
        let dir = attachmentsDir(noteID)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var name = fileName.isEmpty ? "附件" : fileName
        var n = 1
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path) {
            name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            n += 1
        }
        do {
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
            // 引用路径保持原始文件名：markdown-it 渲染时自动做 URL 规范化（encode），
            // 预览点击 → Swift 侧 removingPercentEncoding 还原文件路径
            return "attachments/\(noteID)/\(name)"
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

    /// 当前笔记全部附件：图片（images/ 兼容旧库）+ 文件（attachments/）
    func listAttachments(for noteID: String) -> [AttachmentItem] {
        var out: [AttachmentItem] = []
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"]
        for url in images(for: noteID) {
            let s = (try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]))!
            out.append(AttachmentItem(url: url, name: url.lastPathComponent, size: s.fileSize ?? 0,
                                      isImage: true, mtime: s.contentModificationDate ?? .distantPast))
        }
        let dir = attachmentsDir(noteID)
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) {
            for url in files {
                guard !imageExts.contains(url.pathExtension.lowercased()) else { continue }
                let s = (try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]))!
                out.append(AttachmentItem(url: url, name: url.lastPathComponent, size: s.fileSize ?? 0,
                                          isImage: false, mtime: s.contentModificationDate ?? .distantPast))
            }
        }
        return out.sorted { $0.mtime > $1.mtime }
    }

    func deleteAttachment(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - 新建 / 删除 / 重命名

    func createNote() {
        flush()
        let note = Note()
        ioQueue.sync { writeNote(note) }
        reloadIndex()
        openNote(note.id)
    }

    /// 先命名再创建（文件夹内新建）：指定标题与分类；
    /// 同目录下同名笔记将被拒绝（返回 false）
    @discardableResult
    func createNote(title: String, category: String) -> Bool {
        if index.contains(where: { $0.category == category && $0.title == title }) {
            return false
        }
        flush()
        let note = Note(title: title, category: category)
        ioQueue.sync { writeNote(note) }
        reloadIndex()
        openNote(note.id)
        return true
    }

    /// 同目录下是否存在同名笔记（排除 exemptID）
    func hasDuplicateTitle(_ title: String, category: String, excluding exemptID: String? = nil) -> Bool {
        index.contains {
            $0.category == category && $0.title == title && $0.id != exemptID
        }
    }

    func renameCurrentTo(_ title: String) {
        currentTitle = title
        markDirty()
    }

    /// 重命名任意笔记（侧边栏右键）；当前打开的走运行中编辑
    /// 重命名任意笔记（侧边栏右键）；若目标目录已存在同名 → 拒绝（返回 false）
    @discardableResult
    func renameNote(_ id: String, to title: String) -> Bool {
        if let item = index.first(where: { $0.id == id }) {
            if hasDuplicateTitle(title, category: item.category, excluding: id) {
                return false
            }
        }
        if id == selectedNoteID {
            renameCurrentTo(title)
            return true
        }
        ioQueue.sync {
            if var n = readNote(id) {
                n.title = title
                n.updated = Self.isoNow()
                writeNote(n)
            }
        }
        reloadIndex()
        return true
    }

    @discardableResult
    func deleteNote(_ id: String) -> Bool {
        deleteNotes(ids: [id]) > 0
    }

    /// 删除当前选择集（多选优先，兜底当前打开笔记）
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
        // 删除前快照（用于计算"下一个"）
        let before = filteredIndex
        let deletedSet = Set(ids)
        var trashItems: [TrashItem] = []
        for id in ids {
            ioQueue.sync { moveNoteToTrash(id) }
            trashItems.append(TrashItem(storedName: "", noteID: id, title: "", deletedAt: Date()))
        }
        if selectedNoteID != nil, ids.contains(selectedNoteID ?? "") {
            selectedNoteID = nil
            loadedNoteID = nil
            workingText = ""
        }
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
        // 撤销留档（按真实回收站条目重建）
        lastDeleted = listTrash().prefix(trashItems.count).map { $0 }
        beginUndoToast()
        return trashItems.count
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

    /// 撤销删除：恢复最近一次批量删除的全部笔记（复用回收站恢复）
    func undoDelete() {
        undoTimer?.cancel()
        showUndoToast = false
        let ids = Set(lastDeleted.map(\.noteID))
        lastDeleted = []
        let items = listTrash().filter { ids.contains($0.noteID) }
        var restored = 0
        for item in items {
            if restoreTrash(item) { restored += 1 }
        }
        self.showHint("已恢复 \(restored) 篇笔记")
    }

    // MARK: - 回收站（删除可逆，notes/.trash/ 目录）

    struct TrashItem: Identifiable {
        var id: String { storedName }
        let storedName: String   // "<timestamp>_<noteID>.json"
        let noteID: String
        let title: String
        let deletedAt: Date
    }

    private func moveNoteToTrash(_ id: String) {
        let trashDir = notesDir.appendingPathComponent(".trash", isDirectory: true)
        try? FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let ts = String(Int(Date().timeIntervalSince1970 * 1000))
        let notePath = noteURL(id)
        if FileManager.default.fileExists(atPath: notePath.path) {
            try? FileManager.default.moveItem(at: notePath, to: trashDir.appendingPathComponent("\(ts)_\(id).json"))
        }
        let verDir = notesDir.appendingPathComponent(".versions/\(id)", isDirectory: true)
        if FileManager.default.fileExists(atPath: verDir.path) {
            try? FileManager.default.moveItem(at: verDir, to: trashDir.appendingPathComponent("\(ts)_\(id).versions"))
        }
    }

    func listTrash() -> [TrashItem] {
        let trashDir = notesDir.appendingPathComponent(".trash", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: trashDir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { f in
            let name = f.lastPathComponent
            let parts = name.split(separator: "_", maxSplits: 1)
            guard parts.count == 2, let ts = Int(parts[0]) else { return nil }
            let noteID = String(parts[1].dropLast(5)) // 去掉 .json
            let title = (try? JSONDecoder().decode(Note.self, from: Data(contentsOf: f)))?.title ?? "无标题"
            return TrashItem(storedName: name, noteID: noteID,
                             title: title.isEmpty ? "无标题" : title,
                             deletedAt: Date(timeIntervalSince1970: TimeInterval(ts) / 1000))
        }.sorted { $0.deletedAt > $1.deletedAt }
    }

    @discardableResult
    func restoreTrash(_ item: TrashItem) -> Bool {
        var ok = false
        ioQueue.sync {
            let src = notesDir.appendingPathComponent(".trash/\(item.storedName)")

            let destID = String(item.storedName.split(separator: "_", maxSplits: 1)[1].dropLast(5))
            var finalID = destID
            var n = 1
            while FileManager.default.fileExists(atPath: noteURL(finalID).path) {
                finalID = "\(destID)_r\(n)"
                n += 1
            }
            try? FileManager.default.moveItem(at: src, to: noteURL(finalID))
            // 版本目录一并还原
            let verSrc = notesDir.appendingPathComponent(".trash/\(item.storedName.dropLast(5)).versions")
            if FileManager.default.fileExists(atPath: verSrc.path) {
                try? FileManager.default.moveItem(at: verSrc, to: notesDir.appendingPathComponent(".versions/\(finalID)", isDirectory: true))
            }
            ok = true
        }
        reloadIndex()
        return ok
    }

    func purgeTrash(_ item: TrashItem) {
        ioQueue.sync {
            let trashDir = notesDir.appendingPathComponent(".trash", isDirectory: true)
            try? FileManager.default.removeItem(at: trashDir.appendingPathComponent(item.storedName))
            try? FileManager.default.removeItem(at: trashDir.appendingPathComponent(item.storedName.dropLast(5) + ".versions"))
        }
    }

    func emptyTrash() {
        ioQueue.sync {
            let trashDir = notesDir.appendingPathComponent(".trash", isDirectory: true)
            try? FileManager.default.removeItem(at: trashDir)
        }
    }

    // MARK: - 筛选

    /// 全文搜索：标题命中优先于正文命中；空格分词全部满足才算命中
    var filteredIndex: [NoteIndexItem] {
        var items = index
        if categoryFilter == "=none" {
            items = items.filter { $0.category.isEmpty }
        } else if !categoryFilter.isEmpty {
            items = items.filter { $0.category == categoryFilter }
        }
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            let tokens = q.split(separator: " ").map(String.init).filter { !$0.isEmpty }
            if tokens.isEmpty { return items }
            var titleHits: [NoteIndexItem] = []
            var contentHits: [NoteIndexItem] = []
            for item in items {
                let inTitle = tokens.allSatisfy { item.title.localizedCaseInsensitiveContains($0) }
                if inTitle {
                    titleHits.append(item)
                    continue
                }
                let inPreview = tokens.allSatisfy { item.preview.localizedCaseInsensitiveContains($0) }
                if inPreview { contentHits.append(item); continue }
                // 正文搜索（全文缓存，增量维护）
                if let content = fullTextCache[item.id].flatMap({ String(decoding: $0, as: UTF8.self) }),
                   tokens.allSatisfy({ content.localizedCaseInsensitiveContains($0) }) {
                    contentHits.append(item)
                }
            }
            items = titleHits + contentHits
        }
        return items
    }

    // MARK: - 排序

    enum SortMode: String, CaseIterable {
        case updated, created, manual

        var name: String {
            switch self {
            case .updated: return "按更新时间"
            case .created: return "按创建时间"
            case .manual: return "手动排序"
            }
        }
    }

    var sortMode: SortMode {
        get { SortMode(rawValue: UserDefaults.standard.string(forKey: "sortMode") ?? "") ?? .updated }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "sortMode")
            reloadIndex()
        }
    }

    /// 手动排序序列（notes/.order.json；与 start 兼容的点文件，被双方忽略）
    private(set) var manualOrder: [String] = []

    private func loadManualOrder() {
        let url = notesDir.appendingPathComponent(".order.json")
        manualOrder = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
    }

    private func saveManualOrder() {
        let enc = JSONEncoder()
        if let data = try? enc.encode(manualOrder) {
            try? data.write(to: notesDir.appendingPathComponent(".order.json"), options: .atomic)
        }
    }

    /// 上移/下移（列表当前全局顺序内）；操作后自动进入手动排序
    func moveNote(_ id: String, delta: Int) {
        let items = index
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard j >= 0, j < items.count else { return }
        var ids = items.map(\.id)
        ids.swapAt(i, j)
        manualOrder = ids
        sortMode = .manual
        saveManualOrder()
        var reordered = items
        reordered.swapAt(i, j)
        index = reordered
    }

    // MARK: - 上/下篇切换（筛选视图内）

    func moveSelection(_ delta: Int) {
        let items = filteredIndex
        guard !items.isEmpty else { return }
        let currentID = selectedNoteID ?? items[0].id
        let i = items.firstIndex { $0.id == currentID } ?? 0
        let next = min(max(0, i + delta), items.count - 1)
        openNote(items[next].id)
    }

    // MARK: - 光标管理（已按用户要求取消：不记忆 / 不恢复，纯默认行为）

    var selectedNote: NoteIndexItem? {
        index.first { $0.id == selectedNoteID }
    }

    // MARK: - 分类

    private func writeCategories() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(categories) {
            try? data.write(to: notesDir.appendingPathComponent(".categories.json"), options: .atomic)
        }
    }

    /// 新建文件夹（同名存在即拒绝，返回 false）
    @discardableResult
    func createCategory(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return false }
        guard !categories.contains(where: { $0.name == n }) else { return false }
        categories.append(NoteCategory(name: n))
        writeCategories()
        return true
    }

    /// 移除没有笔记的文件夹（导入目录树等场景产生的大量空分类）
    func removeEmptyCategories() {
        let empty = categories.filter { cat in !index.contains(where: { $0.category == cat.id }) }
        categories.removeAll { cat in empty.contains(where: { $0.id == cat.id }) }
        writeCategories()
    }

    /// 重命名文件夹（同名存在即拒绝，返回 false）
    @discardableResult
    func renameCategory(_ id: String, to name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, let i = categories.firstIndex(where: { $0.id == id }) else { return false }
        guard !categories.contains(where: { $0.id != id && $0.name == n }) else { return false }
        categories[i].name = n
        writeCategories()
        return true
    }

    func deleteCategory(_ id: String) {
        categories.removeAll { $0.id == id }
        if categoryFilter == id { categoryFilter = "" }
        // 该分类下的笔记回到未分类（与 start 行为一致）
        for i in index where i.category == id {
            ioQueue.sync {
                if var note = readNote(i.id) {
                    note.category = ""
                    writeNote(note)
                }
            }
        }
        writeCategories()
        reloadIndex()
    }

    /// 移动笔记到指定分类；目标目录存在同名笔记时拒绝（返回 false）
    @discardableResult
    func assignCategory(_ noteID: String, _ catID: String) -> Bool {
        if let item = index.first(where: { $0.id == noteID }),
           hasDuplicateTitle(item.title, category: catID, excluding: noteID) {
            return false
        }
        ioQueue.sync {
            if var note = readNote(noteID) {
                note.category = catID
                note.updated = Self.isoNow()
                writeNote(note)
            }
        }
        reloadIndex()
        return true
    }

    // MARK: - 历史版本

    struct VersionInfo: Identifiable {
        var id: String { ts }
        let ts: String
        let updated: String
        let size: Int
    }

    func listVersions(_ noteID: String) -> [VersionInfo] {
        let dir = notesDir.appendingPathComponent(".versions/\(noteID)", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { f in
            let ts = f.deletingPathExtension().lastPathComponent
            let size = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let updated = versionNote(noteID, ts)?.updated ?? ts
            return VersionInfo(ts: ts, updated: updated, size: size)
        }.sorted { $0.ts > $1.ts }
    }

    func versionNote(_ noteID: String, _ ts: String) -> Note? {
        let url = notesDir.appendingPathComponent(".versions/\(noteID)/\(ts).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Note.self, from: data)
    }

    func restoreVersion(_ noteID: String, _ ts: String) {
        guard let v = versionNote(noteID, ts) else { return }
        flush()
        ioQueue.sync {
            writeNote(v)
        }
        reloadIndex()
        if selectedNoteID == noteID {
            workingText = v.content
            currentTitle = v.title
            dirty = false
            documentRevision += 1
        }
    }

    // MARK: - 预览图片内联

    /// 预览前把笔记目录内的相对路径图片转成 data URL。
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
        // 逆序替换，保持 NSRange 有效
        for m in matches.reversed() {
            let src = ns.substring(with: m.range(at: 2))
            guard !(src as NSString).contains(" ") else { continue }
            let url = notesDir.appendingPathComponent(src)
            // 1) 缓存命中（mtime 一致）
            let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            guard !(mtime == nil && !FileManager.default.fileExists(atPath: url.path)) else { continue }
            if let hit = imageInlineCache[src], hit.mtime == mtime {
                replaceImages(src: src, dataURL: hit.dataURL, result: &result)
                continue
            }
            // 2) 未命中：读盘 → 重采样（防"内存炸弹"）→ base64 → LRU 缓存
            guard let data = try? Data(contentsOf: url), data.count < maxInlineSize,
                  let mime = Self.mimeType(for: src) else { continue }
            let payload = Self.balancedImageData(data, mime: mime)
            let dataURL = "data:\(mime);base64,\(payload.base64EncodedString())"
            imageInlineCache[src] = (mtime, dataURL)
            imageLRUOrder.append(src)
            while imageLRUOrder.count > 24 { imageInlineCache.removeValue(forKey: imageLRUOrder.removeFirst()) }
            replaceImages(src: src, dataURL: dataURL, result: &result)
        }
        // 远程图（http/https）：命中缓存即替换，未命中的则后台下载
        return inlineRemoteImages(result)
    }

    /// 图片瘦身：宽 >1600px 时重采样到 1600（PNG 非透明转 JPEG q0.8；透明保 PNG）。
    /// 一张 5MB 截图 → 通常 <500KB —— 直接决定 Web Content 内存与渲染成本。
    nonisolated static func balancedImageData(_ data: Data, mime: String) -> Data {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return data }
        let maxW = 1600
        let info = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let width = (info?[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let alpha = (info?[kCGImagePropertyHasAlpha] as? Bool) ?? false
        guard width > maxW else {
            // 已小：若仍很大（如 HEIC 大 PNG >2.5MB）走一轮压 jpeg（无 alpha）
            if data.count > 2_500_000, !alpha,
               let rep = NSBitmapImageRep(data: data),
               let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                return jpg
            }
            return data
        }
        let opts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxW,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts) else { return data }
        let rep = NSBitmapImageRep(cgImage: cg)
        if !alpha,
           let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
            return jpg
        }
        return rep.representation(using: .png, properties: [:]) ?? data
    }

    private func replaceImages(src: String, dataURL: String, result: inout String) {
        // 引用形如 ![...](src)，把 src 整体替换为 dataURL（双引号形式也在覆盖范围）
        result = result.replacingOccurrences(
            of: "](\(src))", with: "](\(dataURL))",
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
                result = result.replacingOccurrences(of: "](\(urlStr))", with: "](\(dl))", options: .literal)
            } else {
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
                    }
                }.resume()
            }
        }
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

    func setTheme(_ t: Theme) {
        currentTheme = t
        themeVersion += 1
    }

    // MARK: - 目录选择

    /// 弹出面板切换笔记目录（可直接选 start 项目的 notes/ 目录）
    func chooseNotesDirectory() {
        flush()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择笔记目录（可以直接选 start 项目的 notes 目录）"
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

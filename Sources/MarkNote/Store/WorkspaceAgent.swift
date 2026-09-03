import Foundation

/// AI 文件代理执行器 —— 在 NotesStore 上执行工具调用。
/// 安全红线：只允许 notesDir 内；拒绝绝对路径/..；拒绝 .versions/.trash/.git；
/// 读 ≤200KB；写 ≤64KB；目录树 ≤500 条；删除走 .trash（dot 目录，索引忽略）且需确认。
@MainActor
final class WorkspaceAgent {
    private let store: NotesStore

    init(store: NotesStore) {
        self.store = store
    }

    enum Outcome {
        case result(String)
        case confirm(FileTools.PendingConfirm)
    }

    static let readLimit = 8000
    static let readBytesLimit = 200 * 1024
    static let writeLimit = 64 * 1024

    // MARK: - 入口

    func handle(_ call: FileTools.ParsedCall) -> Outcome {
        let args = call.argsDict
        switch call.name {
        case "list_files":
            return .result(listFiles(path: args["path"] as? String))
        case "read_file":
            return .result(readFile(path: args["path"] as? String ?? ""))
        case "write_file":
            return .result(writeFile(path: args["path"] as? String ?? "",
                                     content: args["content"] as? String ?? "",
                                     mode: args["mode"] as? String ?? "overwrite"))
        case "rename_file":
            return .result(renameFile(path: args["path"] as? String ?? "",
                                      newName: args["newName"] as? String ?? ""))
        case "move_file":
            return .result(moveFile(path: args["path"] as? String ?? "",
                                    folder: args["folder"] as? String ?? ""))
        case "delete_file":
            guard let id = resolve(args["path"] as? String ?? "") else { return .result(help(_L("路径无效或越界", "Invalid path or out of bounds"))) }
            let pending = FileTools.PendingConfirm(id: call.id, call: call,
                                                   title: _L("删除 \(id)？已移入 .trash 可从 Finder 找回", "Delete \(id)? It was moved to .trash and can be restored from Finder"))
            return .confirm(pending)
        default:
            return .result(help(_L("未知工具 \(call.name)", "Unknown tool \(call.name)")))
        }
    }

    /// 用户在面板确认删除后调用
    func performDelete(_ call: FileTools.ParsedCall) -> String {
        guard let id = resolve(call.argsDict["path"] as? String ?? "") else { return help(_L("路径无效或越界", "Invalid path or out of bounds")) }
        let fm = FileManager.default
        let src = store.noteURL(id)
        guard fm.fileExists(atPath: src.path) else { return _L("文件不存在：\(id)", "File not found: \(id)") }
        let trash = store.notesDir.appendingPathComponent(".trash", isDirectory: true)
        try? fm.createDirectory(at: trash, withIntermediateDirectories: true)
        let ts = String(Int(Date().timeIntervalSince1970 * 1000))
        let safeName = src.lastPathComponent
        let dest = trash.appendingPathComponent("\(ts)_\(safeName)")
        try? fm.moveItem(at: src, to: dest)
        if store.loadedNoteID == id {
            store.closeTab(id)
        }
        store.reloadIndex()
        return _L("已删除并移入 .trash：\(id)", "Deleted and moved to .trash: \(id)")
    }

    /// 以唯一文件名写入新文本文件（已存在则自动加序号）；返回最终文件名（失败 nil）
    func createUniqueTextFile(baseName: String, content: String) -> String? {
        guard let base = resolve(baseName + ".md") ?? resolve(baseName) else { return nil }
        guard content.count <= Self.writeLimit else { return nil }
        let parent = (base as NSString).deletingLastPathComponent
        let stem = ((base as NSString).lastPathComponent as NSString).deletingPathExtension
        let url0 = store.noteURL(base)
        let fm = FileManager.default
        var name = stem + ".md"
        var n = 2
        while fm.fileExists(atPath: url0.deletingLastPathComponent().appendingPathComponent(name).path) {
            name = stem + " \(n).md"
            n += 1
        }
        let final = parent.isEmpty ? name : parent + "/" + name
        try? fm.createDirectory(at: store.noteURL(final).deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try content.write(to: store.noteURL(final), atomically: true, encoding: .utf8)
        } catch {
            return nil
        }
        store.reloadIndex()
        return final
    }

    // MARK: - @文件引用（对话输入里的 @名称 → 工作台文件）

    /// 匹配引用：精确 id/文件名 > 前缀 > 包含（大小写不敏感）；无命中 nil
    func findReference(_ token: String) -> String? {
        let t = token.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let items = store.index
        func hit(_ s: String) -> Bool { s.caseInsensitiveCompare(t) == .orderedSame }
        // 1) 精确：相对路径 id 或文件名
        if let exact = items.first(where: { hit($0.id) || hit($0.title) }) { return exact.id }
        // 2) 前缀
        if let pre = items.first(where: { $0.id.lowercased().hasPrefix(t.lowercased()) || $0.title.lowercased().hasPrefix(t.lowercased()) }) { return pre.id }
        // 3) 包含
        if let any = items.first(where: { $0.id.localizedCaseInsensitiveContains(t) || $0.title.localizedCaseInsensitiveContains(t) }) { return any.id }
        return nil
    }

    /// 读取引用文件内容（同一套限额；失败 nil）
    func readReference(_ id: String) -> String? {
        guard let resolved = resolve(id) else { return nil }
        let url = store.noteURL(resolved)
        guard let data = try? Data(contentsOf: url), data.count <= Self.readBytesLimit else { return nil }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return String(text.prefix(Self.readLimit))
    }

    // MARK: - 路径解析与守卫

    private var hiddenPrefixes: [String] { [".versions", ".trash", ".git", ".DS_Store", ".order.json"] }

    /// 相对路径 → 工作台内绝对 URL；越界/隐藏返回 nil
    private func resolve(_ raw: String) -> String? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        // 反斜杠归正 + 规范化（展开 ..）
        let norm = (cleaned as NSString).standardizingPath
        guard !norm.hasPrefix("/"), norm != "..", !norm.hasPrefix("../") else { return nil }
        let url = store.notesDir.appendingPathComponent(norm)
        guard url.standardizedFileURL.path.hasPrefix(store.notesDir.standardizedFileURL.path + "/") else { return nil }
        let first = url.lastPathComponent
        if first.hasPrefix(".") || hiddenPrefixes.contains(where: { norm == $0 || norm.hasPrefix($0 + "/") }) {
            return nil
        }
        return norm
    }

    private func help(_ msg: String) -> String { "⚠️ " + msg }

    // MARK: - 读取

    private func listFiles(path: String?) -> String {
        let dirRel = resolve(path ?? "") ?? ""
        let dir = store.notesDir.appendingPathComponent(dirRel)
        let fm = FileManager.default
        guard var entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else {
            return help(_L("目录不存在：\(dirRel.isEmpty ? "/" : dirRel)", "Directory does not exist: \(dirRel.isEmpty ? "/" : dirRel)"))
        }
        entries = entries.filter { !$0.lastPathComponent.hasPrefix(".") }
        if entries.count > 500 { entries = Array(entries.prefix(500)) }
        var out = [_L("「\(dirRel.isEmpty ? "工作台根目录" : dirRel)」：", "「\(dirRel.isEmpty ? "Workspace root" : dirRel)」：")]
        for e in entries {
            let isDir = (try? e.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let size = (try? e.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            let rel = Workspace.relativeID(e, root: store.notesDir)
            if isDir {
                out.append("📁 \(rel)/")
            } else {
                out.append(_L("📄 \(rel)（\(fmtSize(size))）", "📄 \(rel) (\(fmtSize(size)))"))
            }
        }
        if entries.isEmpty { out.append(_L("（空目录）", "(Empty directory)")) }
        return out.joined(separator: "\n")
    }

    private func readFile(path: String) -> String {
        guard let id = resolve(path) else { return help(_L("路径无效或越界：\(path)", "Invalid path or out of bounds: \(path)")) }
        let url = store.noteURL(id)
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return help(_L("文件不存在：\(id)", "File not found: \(id)")) }
        guard let data = try? Data(contentsOf: url) else { return help(_L("读取失败：\(id)", "Failed to read: \(id)")) }
        guard data.count <= Self.readBytesLimit else { return _L("（文件 \(fmtSize(data.count)) 超过读取上限，已截断提示）", "(File \(fmtSize(data.count)) exceeds the read limit; output truncated)") }
        guard let text = String(data: data, encoding: .utf8) else { return _L("（二进制文件，无法作为文本读取：\(id)）", "(Binary file; cannot be read as text: \(id))") }
        if text.count > Self.readLimit {
            return String(text.prefix(Self.readLimit)) + "\n\n" + _L("……（内容较长，已截断前 \(Self.readLimit) 字符；共 \(text.count) 字符）", "……(Content is long; truncated to the first \(Self.readLimit) characters out of \(text.count) total)")
        }
        return text
    }

    // MARK: - 编辑与文件管理

    private func writeFile(path: String, content: String, mode: String) -> String {
        guard let id = resolve(path) else { return help(_L("路径无效或越界：\(path)", "Invalid path or out of bounds: \(path)")) }
        guard content.count <= Self.writeLimit else { return help(_L("内容超过 64KB 写入上限（\(content.count) 字符），请分段写入", "Content exceeds the 64KB write limit (\(content.count) characters); please write in smaller parts")) }
        let url = store.noteURL(id)
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            switch mode {
            case "create":
                guard !fm.fileExists(atPath: url.path) else { return help(_L("文件已存在（create 模式）：\(id)", "File already exists (create mode): \(id)")) }
                try content.write(to: url, atomically: true, encoding: .utf8)
            case "append":
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(content.utf8))
            default:
                try content.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            return help(_L("写入失败：\(error.localizedDescription)", "Write failed: \(error.localizedDescription)"))
        }
        store.agentDidWriteFile(id)
        return _L("已写入 \(id)（\(fmtSize(Data(content.utf8).count) )）", "Wrote \(id) (\(fmtSize(Data(content.utf8).count) ))")
    }

    private func renameFile(path: String, newName: String) -> String {
        guard let id = resolve(path) else { return help(_L("路径无效或越界：\(path)", "Invalid path or out of bounds: \(path)")) }
        let cleanName = newName.trimmingCharacters(in: .whitespaces)
        guard !cleanName.isEmpty, !cleanName.contains("/") else { return help(_L("新文件名无效：\(newName)", "Invalid new file name: \(newName)")) }
        let parent = (id as NSString).deletingLastPathComponent
        let newID = parent.isEmpty ? cleanName : parent + "/" + cleanName
        let src = store.noteURL(id)
        let dst = store.noteURL(newID)
        let fm = FileManager.default
        guard fm.fileExists(atPath: src.path) else { return help(_L("文件不存在：\(id)", "File not found: \(id)")) }
        guard !fm.fileExists(atPath: dst.path) else { return help(_L("目标已存在：\(newID)", "Target already exists: \(newID)")) }
        do {
            try fm.moveItem(at: src, to: dst)
        } catch {
            return help(_L("重命名失败：\(error.localizedDescription)", "Rename failed: \(error.localizedDescription)"))
        }
        if store.loadedNoteID == id { store.reopenAs(newID) }
        store.reloadIndex()
        return _L("已重命名：\(id) → \(newID)", "Renamed: \(id) → \(newID)")
    }

    private func moveFile(path: String, folder: String) -> String {
        guard let id = resolve(path) else { return help(_L("路径无效或越界：\(path)", "Invalid path or out of bounds: \(path)")) }
        let folderRel = resolve(folder) ?? folder.trimmingCharacters(in: .whitespaces)
        let newID = folderRel.isEmpty ? id : folderRel + "/" + id
        let src = store.noteURL(id)
        let dst = store.noteURL(newID)
        let fm = FileManager.default
        guard fm.fileExists(atPath: src.path) else { return help(_L("文件不存在：\(id)", "File not found: \(id)")) }
        guard !fm.fileExists(atPath: dst.path) else { return help(_L("目标已存在：\(newID)", "Target already exists: \(newID)")) }
        try? fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try fm.moveItem(at: src, to: dst)
        } catch {
            return help(_L("移动失败：\(error.localizedDescription)", "Move failed: \(error.localizedDescription)"))
        }
        if store.loadedNoteID == id { store.reopenAs(newID) }
        store.reloadIndex()
        return _L("已移动：\(id) → \(newID)", "Moved: \(id) → \(newID)")
    }

    private func fmtSize(_ n: Int) -> String {
        if n < 1024 { return "\(n) B" }
        if n < 1024 * 1024 { return String(format: "%.1f KB", Double(n) / 1024) }
        return String(format: "%.1f MB", Double(n) / 1024 / 1024)
    }
}

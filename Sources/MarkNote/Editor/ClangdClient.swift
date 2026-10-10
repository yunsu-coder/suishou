import Foundation

/// 极简 LSP 客户端（C/C++ → clangd）：Tab 语义补全 + 错误/警告诊断。
///
/// · 只实现一份 JSON-RPC（Content-Length 分帧）收发与最小握手，不引第三方依赖；
/// · clangd 随 Xcode 工具链自带（零安装），找不到时静默退化为本地补全；
/// · 工作台根变化 → 重启进程；结果统一回主线程分发；
/// · 全部状态在内部串行队列上，避免并发踩踏。
final class ClangdClient {
    static let shared = ClangdClient()
    /// clangd 诊断更新（object = 文件 uri，主线程回调）
    static let diagnosticsChanged = Notification.Name("marknote.clangd.diagnostics")

    private static let enabledKey = "cxxIntelEnabled"
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// C/C++ 家族扩展名（clangd 管辖范围）
    static func handles(_ ext: String) -> Bool {
        ["c", "cc", "cpp", "cxx", "h", "hh", "hpp", "hxx", "m", "mm"].contains(ext.lowercased())
    }

    struct Diagnostic {
        let range: NSRange
        let severity: Int      // 1 error / 2 warning / 3 info / 4 hint
        let message: String
        let line: Int          // 1-based（列表跳转用）
    }

    // MARK: - 对外状态（供主线程读；更新镜像到主线程避免 sync 阻塞）

    private var runningMirror = false
    /// 主线程可读：clangd 是否就绪（未启用/未启动 → false）
    var available: Bool { enabledFlag && runningMirror }
    private var enabledFlag: Bool { Self.enabled }

    // MARK: - 内部状态（全部在 queue 上）

    private let queue = DispatchQueue(label: "marknote.clangd")
    private var process: Process?
    private var stdin: FileHandle?
    private var stdoutBuffer = Data()
    private var nextID = 1
    private var pending: [Int: (Any?) -> Void] = [:]
    private var opened: [String: Int] = [:]                    // uri → version
    private var docTexts: [String: String] = [:]               // uri → 最新文本
    private var diagnosticsByURI: [String: [Diagnostic]] = [:]
    private var pendingOpens: [String: (path: String, text: String)] = [:]
    private var root: URL?
    private var running = false

    private let clangdPath: URL? = {
        let candidates = [
            "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clangd",
            "/Library/Developer/CommandLineTools/usr/bin/clangd",
            "/opt/homebrew/bin/clangd",
            "/usr/local/bin/clangd"
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return URL(fileURLWithPath: c)
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = ["--find", "clangd"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }()

    // MARK: - 生命周期

    /// 打开 C/C++ 文件时调用：按需拉起 clangd；根目录变化则重启
    func activate(root newRoot: URL?) {
        guard Self.enabled, let newRoot, clangdPath != nil else { return }
        queue.async { [weak self] in
            guard let self else { return }
            if self.running, self.root?.path == newRoot.path { return }
            self.stopLocked()
            self.startLocked(root: newRoot)
        }
    }

    func shutdown() {
        queue.async { [weak self] in self?.stopLocked() }
    }

    /// 文档同步：首次打开自动 didOpen；后续修改全量 didChange
    func sync(path: String, text: String, openIfNeeded: Bool) {
        guard Self.enabled else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let uri = Self.uri(path)
            if let version = self.opened[uri] {
                self.opened[uri] = version + 1
                self.docTexts[Self.canonKey(path)] = text
                self.sendLocked(["jsonrpc": "2.0", "method": "textDocument/didChange",
                                 "params": ["textDocument": ["uri": uri, "version": version + 1],
                                            "contentChanges": [["text": text]]]])
            } else if openIfNeeded {
                if self.running {
                    self.openLocked(path: path, text: text)
                } else {
                    self.pendingOpens[uri] = (path, text)
                }
            }
        }
    }

    func close(path: String) {
        queue.async { [weak self] in
            guard let self else { return }
            let uri = Self.uri(path)
            guard self.opened.removeValue(forKey: uri) != nil else { return }
            let key = Self.canonKey(path)
            self.docTexts.removeValue(forKey: key)
            self.diagnosticsByURI.removeValue(forKey: key)
            self.sendLocked(["jsonrpc": "2.0", "method": "textDocument/didClose",
                             "params": ["textDocument": ["uri": uri]]])
        }
    }

    /// 当前文件诊断（主线程可读）
    func diagnostics(forPath path: String) -> [Diagnostic] {
        queue.sync { diagnosticsByURI[Self.canonKey(path)] ?? [] }
    }

    /// 语义补全：结果在主线程回调（label 已清洗成可插入文本）
    func completion(path: String, line: Int, character: Int, handle: @escaping ([String]) -> Void) {
        queue.async { [weak self] in
            guard let self, self.running else {
                DispatchQueue.main.async { handle([]) }
                return
            }
            let params: [String: Any] = [
                "textDocument": ["uri": Self.uri(path)],
                "position": ["line": line, "character": character],
                "context": ["triggerKind": 1]
            ]
            self.requestLocked(method: "textDocument/completion", params: params) { result in
                var out: [String] = []
                let items: [[String: Any]]
                if let dict = result as? [String: Any], let list = dict["items"] as? [[String: Any]] {
                    items = list
                } else if let list = result as? [[String: Any]] {
                    items = list
                } else {
                    items = []
                }
                for it in items {
                    if let name = Self.insertableName(it) { out.append(name) }
                }
                DispatchQueue.main.async { handle(out) }
            }
        }
    }

    // MARK: - 进程管理（queue 上）

    private func startLocked(root: URL) {
        guard let bin = clangdPath else { return }
        let p = Process()
        p.executableURL = bin
        p.arguments = ["--pch-storage=memory"]
        p.currentDirectoryURL = root
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard let self, !data.isEmpty else { return }
            self.queue.async { self.feedLocked(data) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { fh in _ = fh.availableData }  // 丢弃，防管道堵塞
        p.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                self.running = false
                self.process = nil
                DispatchQueue.main.async { self.runningMirror = false }
            }
        }
        do { try p.run() } catch { return }
        process = p
        stdin = inPipe.fileHandleForWriting
        self.root = root
        stdoutBuffer.removeAll()
        opened.removeAll()
        diagnosticsByURI.removeAll()
        let params: [String: Any] = [
            "processId": ProcessInfo.processInfo.processIdentifier,
            "rootUri": Self.uri(root.path),
            "capabilities": [
                "textDocument": [
                    "synchronization": ["didSave": false],
                    "completion": ["completionItem": ["snippetSupport": false]],
                    "publishDiagnostics": [:]
                ]
            ],
            "initializationOptions": ["fallbackFlags": ["-std=c++17", "-Wall"]],
            "workspaceFolders": [["uri": Self.uri(root.path), "name": root.lastPathComponent]]
        ]
        requestLocked(method: "initialize", params: params) { [weak self] _ in
            guard let self else { return }
            self.sendLocked(["jsonrpc": "2.0", "method": "initialized", "params": [:]])
            self.running = true
            DispatchQueue.main.async { self.runningMirror = true }
            let opens = self.pendingOpens
            self.pendingOpens.removeAll()
            for (_, item) in opens { self.openLocked(path: item.path, text: item.text) }
        }
    }

    private func stopLocked() {
        running = false
        DispatchQueue.main.async { self.runningMirror = false }
        opened.removeAll()
        pending.removeAll()
        docTexts.removeAll()
        diagnosticsByURI.removeAll()
        pendingOpens.removeAll()
        stdoutBuffer.removeAll()
        stdin?.readabilityHandler = nil
        try? stdin?.close()
        stdin = nil
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        root = nil
    }

    private func openLocked(path: String, text: String) {
        let uri = Self.uri(path)
        opened[uri] = 1
        docTexts[Self.canonKey(path)] = text
        sendLocked(["jsonrpc": "2.0", "method": "textDocument/didOpen",
                    "params": ["textDocument": [
                        "uri": uri,
                        "languageId": Self.languageId(path),
                        "version": 1,
                        "text": text]]])
    }

    // MARK: - JSON-RPC（queue 上）

    private func requestLocked(method: String, params: Any, handle: @escaping (Any?) -> Void) {
        let id = nextID
        nextID += 1
        pending[id] = handle
        sendLocked(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
    }

    private func sendLocked(_ obj: [String: Any]) {
        guard let stdin, let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        var msg = Data("Content-Length: \(data.count)\r\n\r\n".utf8)
        msg.append(data)
        try? stdin.write(contentsOf: msg)
    }

    private func feedLocked(_ chunk: Data) {
        stdoutBuffer.append(chunk)
        let separator = Data("\r\n\r\n".utf8)
        while let headerRange = stdoutBuffer.range(of: separator) {
            let header = String(decoding: stdoutBuffer[..<headerRange.lowerBound], as: UTF8.self)
            guard let length = Self.contentLength(header), length >= 0 else {
                stdoutBuffer.removeAll()
                return
            }
            let bodyStart = headerRange.upperBound
            guard stdoutBuffer.count >= bodyStart + length else { return }   // 等更多数据
            let body = stdoutBuffer.subdata(in: bodyStart..<(bodyStart + length))
            stdoutBuffer.removeSubrange(0..<(bodyStart + length))
            handleLocked(body)
        }
    }

    private func handleLocked(_ body: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return }
        if let id = obj["id"] as? Int, let handler = pending.removeValue(forKey: id) {
            handler(obj["result"])
            return
        }
        guard let method = obj["method"] as? String else { return }
        if method == "textDocument/publishDiagnostics", let params = obj["params"] as? [String: Any] {
            applyDiagnosticsLocked(params)
        }
    }

    private func applyDiagnosticsLocked(_ params: [String: Any]) {
        guard let uri = params["uri"] as? String else { return }
        // clangd 会把 /var 解析成 /private/var（符号链接）→ 诊断按"规范路径"归拢
        let key = Self.canonKey(URL(string: uri)?.path ?? uri)
        let items = (params["diagnostics"] as? [[String: Any]]) ?? []
        let text = docTexts[key] ?? ""
        let ns = text as NSString
        var out: [Diagnostic] = []
        for d in items {
            guard let range = d["range"] as? [String: Any],
                  let start = range["start"] as? [String: Any],
                  let end = range["end"] as? [String: Any],
                  let sl = start["line"] as? Int, let sc = start["character"] as? Int,
                  let el = end["line"] as? Int, let ec = end["character"] as? Int,
                  let s = Self.offset(in: ns, line: sl, character: sc),
                  let e = Self.offset(in: ns, line: el, character: ec) else { continue }
            out.append(Diagnostic(range: NSRange(location: s, length: max(0, e - s)),
                                  severity: (d["severity"] as? Int) ?? 2,
                                  message: (d["message"] as? String) ?? "",
                                  line: sl + 1))
        }
        diagnosticsByURI[key] = out
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: ClangdClient.diagnosticsChanged, object: uri)
        }
    }

    // MARK: - 工具

    private static func contentLength(_ header: String) -> Int? {
        for line in header.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].lowercased() == "content-length" {
                return Int(parts[1].trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    /// 补全项 → 可插入文本：优先 insertText；否则取 label 的标识符前缀（clangd 的 label 可能带签名）
    private static func insertableName(_ item: [String: Any]) -> String? {
        if let t = item["insertText"] as? String, !t.isEmpty { return t }
        guard let label = item["label"] as? String else { return nil }
        let name = label.prefix { c in c.isLetter || c.isNumber || c == "_" || c == "~" || c == "$" }
        return name.isEmpty ? nil : String(name)
    }

    private static func languageId(_ path: String) -> String {
        (path as NSString).pathExtension.lowercased() == "c" ? "c" : "cpp"
    }

    static func uri(_ path: String) -> String {
        var comps = URLComponents()
        comps.scheme = "file"
        comps.path = path
        return comps.string ?? "file://\(path)"
    }

    /// 路径规范键：解析符号链接（clangd 的诊断 URI 用的是规范路径）
    private static func canonKey(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// LSP (line, character) → UTF-16 偏移；行不存在返回 nil
    private static func offset(in text: NSString, line: Int, character: Int) -> Int? {
        var currentLine = 0
        var index = 0
        while currentLine < line {
            guard index < text.length else { return nil }
            var lineStart = 0, lineEnd = 0, contentsEnd = 0
            text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                              for: NSRange(location: index, length: 0))
            index = lineEnd
            currentLine += 1
        }
        return min(index + character, text.length)
    }
}

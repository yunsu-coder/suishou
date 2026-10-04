import Foundation
import Darwin

/// 内置终端会话：真 PTY（由 `/usr/bin/script` 分配）+ 登录 shell，输出流式回传。
///
/// 几个刻意的取舍（都是踩过的坑）：
/// - 用 `script` 而不是自己 openpty：script 会把子进程放进**独立会话并挂上控制终端**，
///   于是 ^C（ETX）能真正送到前台进程组；自己 openpty 时没有前台进程组，中断会失灵。
/// - 关掉 zle 与提示符钩子：交互行编辑器会不停重绘输入行，p10k 之类的 precmd 钩子还会
///   往外发 OSC 7（cwd 通知），在面板里就是一片重复字符和 `]7;file://…` 乱码。
/// - `stty -echo` + 面板自己回显 `❯ 命令`：终端回显会把内部的退出码哨兵也一起显示出来。
@Observable
final class TerminalSession {

    /// 已清洗（去 ANSI / 去覆盖式刷新）的输出
    private(set) var output = ""
    /// 有命令在跑（▶ 变 ⏹；靠哨兵行判定）
    private(set) var isRunning = false
    /// 最近一条命令的退出码
    private(set) var lastExitCode: Int?
    private(set) var isStarted = false

    var cwd: URL

    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private var started = false
    private let maxOutput = 400_000
    private static let exitMarker = "__MARKNOTE_EXIT__"
    private static let readyMarker = "__MARKNOTE_READY__"
    /// 发进终端的哨兵要拆成两段引号：终端回显会把整行原样抄回来，
    /// 只有命令**输出**里才会拼成完整哨兵，避免握手被回声提前触发。
    private static let exitMarkerLiteral = "\"__MARKNOTE\"\"_EXIT__\""
    private static let readyMarkerLiteral = "\"__MARKNOTE\"\"_READY__\""
    /// 跨包未闭合的转义序列（OSC/CSI 常被拆到两个 read 里）
    private var pendingEscape = ""
    /// 握手前的内容（rc banner / 首次提示符）先攒着，握手哨兵一到就整段丢弃
    private var handshakeBuffer = ""
    /// 哨兵被拆包时的尾部残留
    private var tailCarry = ""
    /// shell 是否已静音完成（握手哨兵到了才放行用户命令）
    private var ready = false
    /// 静音命令是否已发出（要等 pty 就绪再发，否则会被丢弃）
    private var sanitizerSent = false
    private var queued: [(command: String, echo: Bool)] = []

    init(cwd: URL) {
        self.cwd = cwd
    }

    // MARK: - 生命周期

    func startIfNeeded() {
        guard !started else { return }
        started = true
        start()
    }

    private func start() {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        // -q 静默、/dev/null 不落盘
        // zsh -f +o zle：不读用户的 rc、关掉行编辑器。用户的 .zshrc（oh-my-zsh + p10k）
        // 会在每次提示符处重绘整块 powerline 并往外发 OSC 转义，在面板里就是满屏乱码；
        // 面板只要"能跑命令"，PATH 由下面注入，行为可预期。
        process.arguments = ["-q", "/dev/null", "/bin/zsh", "-f", "+o", "zle"]
        process.currentDirectoryURL = cwd
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env["CLICOLOR_FORCE"] = "1"
        // -f 不读 .zprofile → Homebrew / cargo / go / 用户 bin 自己补进 PATH，脚本才找得到解释器
        let home = NSHomeDirectory()
        let extra = ["\(home)/.cargo/bin", "\(home)/go/bin", "\(home)/.local/bin", "\(home)/.pyenv/shims",
                     "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin"]
        let existing = (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":").map(String.init)
        env["PATH"] = TerminalSession.uniqued(extra + existing).joined(separator: ":")
        process.environment = env
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stdoutPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let chunk = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.ingest(chunk) }
        }
        process.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            DispatchQueue.main.async {
                guard let self else { return }
                self.stdoutPipe.fileHandleForReading.readabilityHandler = nil
                self.isStarted = false
                self.isRunning = false
                self.appendSystemLine(_L("会话已结束（退出码 \(code)）", "Session ended (exit \(code))"))
            }
        }
        do {
            try process.run()
        } catch {
            appendSystemLine(_L("启动 shell 失败：\(error.localizedDescription)",
                                "Failed to start shell: \(error.localizedDescription)"))
            return
        }
        isStarted = true
        // 静音命令此刻先不发：pty 还没挂好，太早写会被伪终端丢掉（实测整条命令消失）。
        // 等 shell 吐出第一个字节（提示符）再发 —— 那说明 pty 与 shell 都活了。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.sendSanitizerIfNeeded()
        }
        // 兜底：rc 极慢或哨兵丢失时也要能用（宁可露出一点噪声，也不能卡住不让输入）
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, !self.ready else { return }
            self.ready = true
            // 兜底：哨兵没等到就把 shell 说过的话原样放出来（至少能看出哪里不对）
            if !self.handshakeBuffer.isEmpty {
                self.output += self.handshakeBuffer
                self.handshakeBuffer = ""
            }
            self.flushQueued()
        }
    }

    func shutdown() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        isStarted = false
        started = false
        isRunning = false
    }

    /// 静音提示符 + 关终端回显（面板自己回显命令）：只发一次
    private func sendSanitizerIfNeeded() {
        guard !sanitizerSent, isStarted, process.isRunning else { return }
        sanitizerSent = true
        raw("stty -echo 2>/dev/null; PROMPT=''; RPROMPT=''; PS1=''; PS2='';\n" +
            "unsetopt PROMPT_SP PROMPT_CR 2>/dev/null; precmd_functions=(); preexec_functions=(); " +
            "chpwd_functions=(); " +
            "echo \(Self.readyMarkerLiteral)\n")
    }

    // MARK: - 交互

    /// 运行一条命令（面板输入框 / ▶ 运行当前文件都走这里）
    func run(_ command: String, echo: Bool = true) {
        startIfNeeded()
        guard isStarted else { return }
        isRunning = true
        lastExitCode = nil
        guard ready else {
            queued.append((command, echo))
            return
        }
        dispatch(command, echo: echo)
    }

    private func dispatch(_ command: String, echo: Bool) {
        if echo { appendSystemLine("❯ " + command) }
        // 哨兵行：输出结束后回传退出码，界面据此把 ⏹ 变回 ▶
        raw(command + "; echo \"\\n\(Self.exitMarkerLiteral)$?\"\n")
    }

    /// 握手完成：丢掉启动噪声，放行排队的命令
    private func flushQueued() {
        let items = queued
        queued = []
        for it in items { dispatch(it.command, echo: it.echo) }
    }

    /// 中断当前命令（ETX → 控制终端把 SIGINT 交给前台进程组）
    func interrupt() {
        guard isStarted else { return }
        raw("\u{03}")
        isRunning = false
    }

    /// 强杀兜底
    func forceKill() {
        if process.isRunning { kill(process.processIdentifier, SIGINT) }
    }

    func clear() {
        output = ""
    }

    func sendRaw(_ text: String) {
        startIfNeeded()
        raw(text)
    }

    private func raw(_ s: String) {
        guard let data = s.data(using: .utf8), process.isRunning else { return }
        try? stdinPipe.fileHandleForWriting.write(contentsOf: data)
    }

    // MARK: - 输出

    private func ingest(_ chunk: String) {
        var visible = sanitize(chunk)
        // 第一包数据到了 = pty 已就绪 → 这时补发静音命令
        sendSanitizerIfNeeded()
        // 握手：等静音命令跑完（哨兵到达）之前的内容全部丢弃，避免 rc banner / 提示符乱入
        if !ready {
            handshakeBuffer += visible
            guard let r = handshakeBuffer.range(of: Self.readyMarker) else {
                if handshakeBuffer.count > 4096 { handshakeBuffer = String(handshakeBuffer.suffix(256)) }
                return
            }
            visible = String(handshakeBuffer[r.upperBound...])
            handshakeBuffer = ""
            ready = true
            output = ""
            flushQueued()
        }
        // 退出码哨兵可能被拆包：数字没到齐就先留到下一包
        var text = tailCarry + visible
        tailCarry = ""
        if let cut = Self.danglingExitMarkerIndex(text) {
            let idx = text.index(text.startIndex, offsetBy: cut)
            tailCarry = String(text[idx...])
            text = String(text[..<idx])
        }
        if let r = text.range(of: Self.exitMarker) {
            let digits = text[r.upperBound...].prefix { $0.isNumber }
            if let code = Int(digits) {
                lastExitCode = code
                isRunning = false
                var head = String(text[text.startIndex..<r.lowerBound])
                head = head.trimmingCharacters(in: .newlines)
                text = head + "\n" + (code == 0
                    ? _L("↳ 完成（退出码 0）", "↳ Done (exit 0)")
                    : _L("↳ 退出码 \(code)", "↳ Exit \(code)")) + "\n"
            }
        }
        output += text
        if output.count > maxOutput { output = String(output.suffix(maxOutput / 2)) }
    }

    private func appendSystemLine(_ line: String) {
        output += (output.isEmpty ? "" : "\n") + line + "\n"
    }

    /// 面板提示（不进 shell，只写一行说明）
    func note(_ line: String) {
        appendSystemLine("· " + line)
    }

    /// PATH 去重（保序）：注入目录在前，用户原有 PATH 在后
    nonisolated private static func uniqued(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    // MARK: - 文本清洗

    /// 拼上跨包残留的转义序列再清洗
    private func sanitize(_ chunk: String) -> String {
        let s = pendingEscape + chunk
        pendingEscape = ""
        if let cut = Self.danglingEscapeIndex(s) {
            let idx = s.index(s.startIndex, offsetBy: cut)
            pendingEscape = String(s[idx...])
            return Self.clean(String(s[..<idx]))
        }
        return Self.clean(s)
    }

    /// 去掉 ANSI 控制序列（CSI / OSC，含 ESC\ 结束的 OSC）+ 统一换行 + 覆盖式刷新只留最后一段
    static func clean(_ s: String) -> String {
        var t = stripANSI(s)
        t = t.replacingOccurrences(of: "\r\n", with: "\n")
        t = t.replacingOccurrences(of: "\u{0C}", with: "")     // 清屏字符：面板自己清
        if t.contains("\r") {
            // 进度条/覆盖式刷新：每行只保留 \r 之后的那一段
            t = t.split(separator: "\n", omittingEmptySubsequences: false).map { line in
                line.split(separator: "\r", omittingEmptySubsequences: false).last ?? line
            }.joined(separator: "\n")
        }
        return t
    }

    private static func stripANSI(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            guard c == "\u{1B}" else { out.append(c); i = s.index(after: i); continue }
            var j = s.index(after: i)
            guard j < s.endIndex else { break }             // 光秃秃的 ESC：丢弃
            let kind = s[j]
            if kind == "[" {                                 // CSI：参数 0x20-0x3F，终止 0x40-0x7E
                j = s.index(after: j)
                while j < s.endIndex, let v = s[j].unicodeScalars.first?.value, (0x20...0x3F).contains(v) {
                    j = s.index(after: j)
                }
                if j < s.endIndex { j = s.index(after: j) }
                i = j
            } else if kind == "]" {                          // OSC：BEL 或 ESC\ 结束
                j = s.index(after: j)
                while j < s.endIndex {
                    if s[j] == "\u{07}" { j = s.index(after: j); break }
                    if s[j] == "\u{1B}" {
                        j = s.index(after: j)
                        if j < s.endIndex { j = s.index(after: j) }
                        break
                    }
                    j = s.index(after: j)
                }
                i = j
            } else if kind == "(" || kind == ")" {            // 字符集切换
                j = s.index(after: j)
                if j < s.endIndex { j = s.index(after: j) }
                i = j
            } else {
                i = j
            }
        }
        return out
    }

    /// 末尾未闭合转义序列的起始下标（nil = 干净）
    static func danglingEscapeIndex(_ s: String) -> Int? {
        var i = s.endIndex
        while i > s.startIndex {
            i = s.index(before: i)
            guard s[i] == "\u{1B}" else { continue }
            let rest = s[i...]
            if rest.hasPrefix("\u{1B}]") {
                return rest.dropFirst(2).contains("\u{07}") || rest.dropFirst(2).contains("\u{1B}") ? nil : s.distance(from: s.startIndex, to: i)
            }
            if rest.hasPrefix("\u{1B}[") {
                // CSI：参数 0x20-0x3F，遇到 0x40-0x7E 就是终止字节（要顺着扫，不能只看末尾字符）
                var j = rest.index(rest.startIndex, offsetBy: 2)
                while j < rest.endIndex, let v = rest[j].unicodeScalars.first?.value, (0x20...0x3F).contains(v) {
                    j = rest.index(after: j)
                }
                if j < rest.endIndex, let v = rest[j].unicodeScalars.first?.value, (0x40...0x7E).contains(v) {
                    return nil
                }
                return s.distance(from: s.startIndex, to: i)
            }
            if rest.count == 1 { return s.distance(from: s.startIndex, to: i) }
            return nil
        }
        return nil
    }

    /// 末尾可能是"半截退出码哨兵"的起始下标（哨兵本身被拆包，或数字还没到齐）
    static func danglingExitMarkerIndex(_ s: String) -> Int? {
        if let r = s.range(of: exitMarker, options: .backwards) {
            var i = r.upperBound
            while i < s.endIndex, s[i].isNumber { i = s.index(after: i) }
            if i == s.endIndex {
                // 还没看到换行 → 数字可能还没收全，整段留到下一包
                return s.distance(from: s.startIndex, to: r.lowerBound)
            }
            return nil
        }
        // 末尾正好是哨兵的前缀（如 "__MARKNOT"）→ 留到下一包
        let maxTail = min(exitMarker.count - 1, s.count)
        guard maxTail > 0 else { return nil }
        for len in stride(from: maxTail, through: 1, by: -1) {
            let start = s.index(s.endIndex, offsetBy: -len)
            if exitMarker.hasPrefix(String(s[start...])) {
                return s.distance(from: s.startIndex, to: start)
            }
        }
        return nil
    }
}

import Foundation
import Darwin

/// 内置终端会话：真 PTY（openpty）+ 登录 shell，输出流式回传。
///
/// 为什么用 PTY 而不是管道：管道下 `isatty` 为假，很多工具会关掉颜色、改缓冲策略，
/// 「终端面板」就不像终端了。这里把 /bin/zsh -l 挂到伪终端上，行为与系统终端一致。
/// 说明：状态字段只在主线程改（UI 观察），读线程负责收数据后回主线程。
@Observable
final class TerminalSession {

    /// 已合并、已去掉 ANSI 控制码的输出（面板直接显示）
    private(set) var output = ""
    /// 有命令在跑（▶ 变 ⏹；PVT 里靠哨兵行判定）
    private(set) var isRunning = false
    /// 最近一条命令的退出码
    private(set) var lastExitCode: Int?
    /// shell 是否已起
    private(set) var isStarted = false

    var cwd: URL

    private var masterFD: Int32 = -1
    private var shell: Process?
    private var readSource: DispatchSourceRead?
    private let ioQueue = DispatchQueue(label: "com.gzhysu.marknote.terminal", qos: .userInitiated)
    /// 输出上限（防止 `yes` 之类的命令把内存吃满）
    private let maxOutput = 400_000
    /// 退出码哨兵：命令末尾追加 echo，用它判定"跑完了"
    private static let exitMarker = "__MARKNOTE_EXIT__"

    init(cwd: URL) {
        self.cwd = cwd
    }

    // MARK: - 生命周期

    func startIfNeeded() {
        guard !isStarted else { return }
        start()
    }

    private func start() {
        var master: Int32 = 0
        var slave: Int32 = 0
        var win = winsize(ws_row: 40, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &win) == 0 else {
            appendSystemLine(_L("打开伪终端失败，终端不可用", "Failed to open a pseudo-terminal"))
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-l"]
        p.currentDirectoryURL = cwd
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env["CLICOLOR_FORCE"] = "1"          // 让 ls/grep 之类保持颜色
        p.environment = env

        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        p.standardInput = slaveHandle
        p.standardOutput = slaveHandle
        p.standardError = slaveHandle
        p.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            DispatchQueue.main.async {
                guard let self else { return }
                self.isStarted = false
                self.isRunning = false
                self.appendSystemLine(_L("会话已结束（退出码 \(code)）", "Session ended (exit \(code))"))
            }
        }
        do {
            try p.run()
        } catch {
            close(master)
            close(slave)
            appendSystemLine(_L("启动 shell 失败：\(error.localizedDescription)",
                                "Failed to start shell: \(error.localizedDescription)"))
            return
        }
        close(slave)                          // 父进程只留主端
        shell = p
        masterFD = master
        isStarted = true

        let src = DispatchSource.makeReadSource(fileDescriptor: master, queue: ioQueue)
        src.setEventHandler { [weak self] in self?.drain() }
        src.setCancelHandler { close(master) }
        src.resume()
        readSource = src
    }

    /// 关掉会话（面板关闭 / 退出 app）
    func shutdown() {
        readSource?.cancel()
        readSource = nil
        if let p = shell, p.isRunning { p.terminate() }
        shell = nil
        masterFD = -1
        isStarted = false
        isRunning = false
    }

    // MARK: - 交互

    /// 运行一条命令（面板输入框 / ▶ 运行当前文件都走这里）
    func run(_ command: String, echo: Bool = true) {
        startIfNeeded()
        guard masterFD >= 0 else { return }
        isRunning = true
        lastExitCode = nil
        if echo { appendSystemLine("❯ " + command) }
        // 哨兵行：输出结束后回传退出码，界面据此把 ⏹ 变回 ▶
        write(command + "; echo \"\\n\(Self.exitMarker)$?\"\n")
    }

    /// 中断当前命令（先 ^C，再由 UI 决定是否强杀）
    func interrupt() {
        guard masterFD >= 0 else { return }
        write("\u{03}")                        // ETX：前台进程组收到 SIGINT
        isRunning = false
    }

    /// 强杀：^C 不奏效时用（例如卡住的编译）
    func forceKill() {
        if let p = shell, p.isRunning {
            kill(p.processIdentifier, SIGINT)
        }
    }

    func clear() {
        output = ""
        write("\u{0C}")                        // ^L：让 shell 也清屏，行为与终端一致
    }

    func sendRaw(_ text: String) {
        startIfNeeded()
        write(text)
    }

    private func write(_ s: String) {
        guard masterFD >= 0, let data = s.data(using: .utf8) else { return }
        data.withUnsafeBytes { buf in
            guard let base = buf.baseAddress else { return }
            _ = Darwin.write(masterFD, base, data.count)
        }
    }

    // MARK: - 输出

    private func drain() {
        var buf = [UInt8](repeating: 0, count: 8192)
        let n = read(masterFD, &buf, buf.count)
        guard n > 0 else { return }
        let raw = String(decoding: buf[0..<n], as: UTF8.self)
        let cleaned = Self.clean(raw)
        DispatchQueue.main.async { self.ingest(cleaned) }
    }

    private func ingest(_ text: String) {
        // 哨兵 → 退出码；同时把哨兵行从可见输出里摘掉
        var visible = text
        if let r = text.range(of: Self.exitMarker) {
            let after = text[r.upperBound...]
            let digits = after.prefix { $0.isNumber }
            if let code = Int(digits) {
                lastExitCode = code
                isRunning = false
                let head = String(text[text.startIndex..<r.lowerBound])
                visible = head.trimmingCharacters(in: .newlines)
                visible += "\n" + (code == 0
                    ? _L("↳ 完成（退出码 0）", "↳ Done (exit 0)")
                    : _L("↳ 退出码 \(code)", "↳ Exit \(code)")) + "\n"
            }
        }
        output += visible
        if output.count > maxOutput {
            output = String(output.suffix(maxOutput / 2))
        }
    }

    private func appendSystemLine(_ line: String) {
        output += (output.isEmpty ? "" : "\n") + line + "\n"
    }

    /// 面板提示（不进 shell，只写一行说明）
    func note(_ line: String) {
        appendSystemLine("· " + line)
    }

    /// 去掉 ANSI 控制序列 + 统一换行（PTY 里是 \r\n；进度条的 \r 只保留最后一段）
    static func clean(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "\r\n", with: "\n")
        if t.contains("\r") {
            // 覆盖式刷新：取最后一段（与终端观感一致）
            let parts = t.split(separator: "\r", omittingEmptySubsequences: false)
            t = parts.count > 1 ? String(parts.last ?? "") : t
        }
        t = t.replacingOccurrences(of: "\u{1B}\\][^\u{07}]*\u{07}", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\u{1B}[()][A-Za-z0-9]", with: "", options: .regularExpression)
        return t
    }
}

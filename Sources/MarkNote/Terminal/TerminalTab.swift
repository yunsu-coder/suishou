import AppKit
import SwiftTerm

/// 一个终端标签页：真 xterm 视图（SwiftTerm）+ 用户自己的登录 shell。
/// 和 VS Code 一样：加载用户 rc（提示符、别名、函数都在），面板关掉进程也不停。
@Observable
final class TerminalTab: Identifiable {
    let id = UUID()
    let view: TerminalView
    private(set) var title: String
    private(set) var cwd: String?
    private(set) var exited = false
    private(set) var exitCode: Int32?
    private let shell: String

    init(theme: TerminalTheme, cwd: URL) {
        self.title = (ProcessInfo.processInfo.environment["SHELL"] as NSString?)?.lastPathComponent ?? "zsh"
        self.cwd = cwd.path
        self.shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        self.view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 240))
        apply(theme: theme)
        (view as? LocalProcessTerminalView)?.processDelegate = self
        startProcess(in: cwd)
    }

    /// 主题/字体变化时即时生效（颜色、字号、光标色）
    func apply(theme: TerminalTheme) {
        view.font = theme.font
        view.nativeBackgroundColor = theme.background
        view.nativeForegroundColor = theme.foreground
        view.caretColor = theme.caret
        view.installColors(theme.ansi)
    }

    private var terminalView: LocalProcessTerminalView? { view as? LocalProcessTerminalView }

    private func startProcess(in cwd: URL) {
        // -l 登录 shell：和 VS Code 的 "login shell" 一致，用户 rc 全量生效
        terminalView?.startProcess(executable: shell, args: ["-l"], environment: nil,
                                   execName: "-" + (shell as NSString).lastPathComponent,
                                   currentDirectory: cwd.path)
        exited = false
        exitCode = nil
    }

    func restart(theme: TerminalTheme) {
        terminalView?.terminate()
        apply(theme: theme)
        startProcess(in: URL(fileURLWithPath: cwd ?? NSHomeDirectory()))
    }

    /// 面板关闭 / 标签关闭时才真正结束进程
    func stop() {
        terminalView?.terminate()
    }

    /// 把一条命令打进终端（▶ 运行当前文件走这里，等于在终端里手敲一行）
    @discardableResult
    func run(_ command: String) -> Bool {
        guard !exited, let v = terminalView else { return false }
        v.window?.makeFirstResponder(v)
        v.send(txt: command + "\n")
        return true
    }

    func focus() {
        guard let v = terminalView else { return }
        v.window?.makeFirstResponder(v)
    }

    /// ⌘K 清屏（VS Code 同款快捷键：先清缓冲再让 shell 自己清）
    func clear() {
        terminalView?.send(txt: "\u{0C}")
    }
}

extension TerminalTab: LocalProcessTerminalViewDelegate {
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { self.title = t }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory, !directory.isEmpty else { return }
        cwd = URL(string: directory)?.path ?? directory
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        exited = true
        self.exitCode = exitCode
    }
}

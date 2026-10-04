import AppKit
import SwiftTerm

enum TerminalMenuAction {
    case clear, restart, close
}

/// 终端视图：在 SwiftTerm 之上补 VS Code 的右键菜单（复制 / 粘贴 / 全选 / 清屏 / 重启 / 关闭）。
/// ⌘点击链接交给 SwiftTerm 默认实现（直接用系统默认浏览器打开），不用另写。
final class MarkNoteTerminalView: LocalProcessTerminalView {
    var onMenuAction: ((TerminalMenuAction) -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let copy = NSMenuItem(title: _L("复制", "Copy"), action: #selector(copy(_:)), keyEquivalent: "c")
        copy.target = self
        copy.isEnabled = (getSelection()?.isEmpty == false)
        menu.addItem(copy)
        let paste = NSMenuItem(title: _L("粘贴", "Paste"), action: #selector(paste(_:)), keyEquivalent: "v")
        paste.target = self
        menu.addItem(paste)
        let all = NSMenuItem(title: _L("全选", "Select All"), action: #selector(selectAll(_:)), keyEquivalent: "a")
        all.target = self
        menu.addItem(all)
        menu.addItem(.separator())
        let clear = NSMenuItem(title: _L("清屏", "Clear"), action: #selector(fireClear), keyEquivalent: "k")
        clear.target = self
        menu.addItem(clear)
        let restart = NSMenuItem(title: _L("重启终端", "Restart Terminal"), action: #selector(fireRestart), keyEquivalent: "")
        restart.target = self
        menu.addItem(restart)
        menu.addItem(.separator())
        let close = NSMenuItem(title: _L("关闭终端", "Close Terminal"), action: #selector(fireClose), keyEquivalent: "")
        close.target = self
        menu.addItem(close)
        return menu
    }

    @objc private func fireClear() { onMenuAction?(.clear) }
    @objc private func fireRestart() { onMenuAction?(.restart) }
    @objc private func fireClose() { onMenuAction?(.close) }
}

/// 一个终端标签页：真 xterm 视图（SwiftTerm）+ 用户自己的登录 shell。
/// 和 VS Code 一样：加载用户 rc（提示符、别名、函数都在），面板关掉进程也不停。
@Observable
final class TerminalTab: Identifiable {
    let id = UUID()
    let view: TerminalView
    /// 供面板挂右键菜单动作
    var onMenuAction: ((TerminalMenuAction) -> Void)? {
        didSet { (view as? MarkNoteTerminalView)?.onMenuAction = onMenuAction }
    }
    private(set) var title: String
    private(set) var cwd: String?
    private(set) var exited = false
    private(set) var exitCode: Int32?
    private let shell: String
    /// 上一次真正应用过的配色/字体指纹：SwiftUI 每次更新都重刷主题会让终端整屏重绘
    private var appliedThemeKey = ""

    init(theme: TerminalTheme, cwd: URL) {
        self.title = (ProcessInfo.processInfo.environment["SHELL"] as NSString?)?.lastPathComponent ?? "zsh"
        self.cwd = cwd.path
        self.shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        self.view = MarkNoteTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 240))
        apply(theme: theme)
        (view as? LocalProcessTerminalView)?.processDelegate = self
        startProcess(in: cwd)
    }

    /// 主题/字体变化时即时生效（颜色、字号、光标色）
    func apply(theme: TerminalTheme) {
        let key = theme.fingerprint
        guard key != appliedThemeKey else { return }
        appliedThemeKey = key
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

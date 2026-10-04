import SwiftUI
import AppKit

/// 内置终端面板（底部停靠）：
/// - 真 PTY 登录 shell，可敲任意命令（cd / 环境变量都保持）
/// - ▶ 运行当前文件：按扩展名选解释器/编译器，在文件所在目录跑
/// - 主题适配：底色、正文色、等宽字体都取自当前主题；代码运行时用固定流行配色不适用这里
struct TerminalPanel: View {

    @Environment(NotesStore.self) private var store
    var onClose: () -> Void

    @State private var session: TerminalSession?
    @State private var input = ""
    @State private var history: [String] = []
    @State private var historyIndex: Int? = nil
    @State private var dragBase: Double? = nil
    @AppStorage("terminalPanelHeight") private var height: Double = 240

    private var theme: AppAppearance { appAppearance }

    var body: some View {
        VStack(spacing: 0) {
            resizeHandle
            header
            Divider()
            TerminalOutputView(text: session?.output ?? "", font: monoFont, background: theme.editorBackground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            inputRow
        }
        .frame(height: height)
        .background(Color(nsColor: theme.editorBackground))
        .onAppear { ensureSession() }
        .onChange(of: store.notesDir) { _, _ in restartSession() }
        .onDisappear { session?.shutdown() }
    }

    // MARK: - 顶部拖拽调高

    private var resizeHandle: some View {
        ZStack {
            Rectangle().fill(.clear)
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 42, height: 3)
        }
        .frame(height: 8)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture()
                .onChanged { v in
                    if dragBase == nil { dragBase = height }
                    let base = dragBase ?? height
                    height = min(640, max(120, base - v.translation.height))
                }
                .onEnded { _ in dragBase = nil }
        )
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 8) {
            ThemeIcon(name: "terminal", fallback: "terminal", size: 13)
                .foregroundStyle(.secondary)
            Text(_LL("终端", "Terminal"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(shortPath(session?.cwd.path ?? store.notesDir.path))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
                .help(session?.cwd.path ?? store.notesDir.path)
            if let code = session?.lastExitCode {
                Text(code == 0 ? "✓" : "✗ \(code)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(code == 0 ? Color.secondary : Color.red.opacity(0.85))
            }
            Spacer()
            Button {
                runCurrentFile()
            } label: {
                Label(running
                        ? _LL("停止", "Stop")
                        : _LL("运行当前文件", "Run Current File"),
                      systemImage: running ? "stop.fill" : "play.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(store.selectedNoteID == nil && !running)
            .help(running ? _L("中断当前命令（^C）", "Interrupt (^C)") : runHelp)
            Button {
                session?.clear()
            } label: {
                Label(_LL("清屏", "Clear"), systemImage: "eraser")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help(_LL("清屏", "Clear"))
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(_LL("关闭面板（⌘J）", "Close Panel (⌘J)"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(theme.surface.map { Color(nsColor: $0) } ?? Color.clear)
    }

    private var running: Bool { session?.isRunning ?? false }

    private var runHelp: String {
        guard let id = store.selectedNoteID else {
            return _L("先在左侧选中一个文件", "Select a file on the left first")
        }
        let ext = (id as NSString).pathExtension
        let path = store.notesDir.appendingPathComponent(id).path
        return RunCommand.command(forExt: ext, file: path)
            ?? _L("这个类型没有内置运行方式，可在下方手动输入命令", "No built-in runner for this type; type a command below")
    }

    // MARK: - 输入行

    private var inputRow: some View {
        HStack(spacing: 6) {
            Text("❯")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.accent)
            TextField(_LL("输入命令，回车执行（↑↓ 历史）", "Type a command, Enter to run (↑↓ history)"), text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit { submit() }
                .onKeyPress(.upArrow) { moveHistory(-1) }
                .onKeyPress(.downArrow) { moveHistory(1) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func submit() {
        let cmd = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        history.append(cmd)
        historyIndex = nil
        input = ""
        session?.run(cmd)
    }

    private func moveHistory(_ delta: Int) -> KeyPress.Result {
        guard !history.isEmpty else { return .ignored }
        let idx = (historyIndex ?? history.count) + delta
        if idx < 0 { return .handled }
        if idx >= history.count {
            historyIndex = nil
            input = ""
            return .handled
        }
        historyIndex = idx
        input = history[idx]
        return .handled
    }

    // MARK: - 运行当前文件

    private func runCurrentFile() {
        ensureSession()
        guard let session else { return }
        if session.isRunning {
            session.interrupt()                 // ^C 优先；仍不结束可再点一次
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if session.isRunning { session.forceKill() }
            }
            return
        }
        guard let id = store.selectedNoteID else { return }
        let url = store.notesDir.appendingPathComponent(id)
        let ext = (id as NSString).pathExtension
        guard let cmd = RunCommand.command(forExt: ext, file: url.path) else {
            session.note(_L("「.\(ext.isEmpty ? "无扩展名" : ext)」没有内置运行方式；可在下方手动输入命令",
                            "No built-in runner for .\(ext.isEmpty ? "(none)" : ext); type a command below"))
            return
        }
        // 在文件所在目录跑，相对路径的输入输出才符合直觉
        session.cwd = url.deletingLastPathComponent()
        session.run("cd \(RunCommand.shellQuote(session.cwd.path)) && \(cmd)")
    }

    private func ensureSession() {
        if session == nil { session = TerminalSession(cwd: store.notesDir) }
        session?.startIfNeeded()
    }

    private func restartSession() {
        session?.shutdown()
        let s = TerminalSession(cwd: store.notesDir)
        s.startIfNeeded()
        session = s
    }

    private var monoFont: NSFont {
        MarkdownEditorView.resolveFont(family: theme.codeFontFamily ?? "mono", size: 12)
    }

    private func shortPath(_ p: String) -> String {
        let home = NSHomeDirectory()
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }
}

/// 终端输出：只读 NSTextView（自动滚到底、可选中复制、等宽）
private struct TerminalOutputView: NSViewRepresentable {
    let text: String
    let font: NSFont
    let background: NSColor

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = background
        scroll.borderType = .noBorder

        let tv = NSTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = true
        tv.backgroundColor = background
        tv.textColor = appAppearance.editorForeground
        tv.font = font
        tv.textContainerInset = NSSize(width: 10, height: 8)
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.font != font { tv.font = font }
        if tv.backgroundColor != background { tv.backgroundColor = background; scroll.backgroundColor = background }
        let color = appAppearance.editorForeground
        if tv.textColor != color { tv.textColor = color }
        guard tv.string != text else { return }
        tv.string = text
        tv.scrollToEndOfDocument(nil)
    }
}

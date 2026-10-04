import SwiftUI
import AppKit
import SwiftTerm

/// 终端会话仓库：面板关掉进程不停（VS Code 同款行为），重新打开还在。
@Observable
final class TerminalStore {
    static let shared = TerminalStore()
    var tabs: [TerminalTab] = []
    var activeID: UUID?
    /// 拆分出来的第二个终端（VS Code 的 split terminal）
    var split: TerminalTab?
    /// 只有用户**主动**打开面板/新建/运行时才抢焦点 —— 换文件重建面板不许抢，
    /// 否则你刚点开一篇笔记，敲的字全进了 shell（实测过这个 bug）。
    var pendingFocus = false

    private init() {}

    var active: TerminalTab? { tabs.first { $0.id == activeID } ?? tabs.first }

    @discardableResult
    func newTab(theme: TerminalTheme, cwd: URL) -> TerminalTab {
        let tab = TerminalTab(theme: theme, cwd: cwd)
        tabs.append(tab)
        activeID = tab.id
        pendingFocus = true
        return tab
    }

    func close(_ tab: TerminalTab) {
        tab.stop()
        tabs.removeAll { $0.id == tab.id }
        if split?.id == tab.id { split = nil }
        if activeID == tab.id { activeID = tabs.last?.id }
    }

    func closeAll() {
        tabs.forEach { $0.stop() }
        split?.stop()
        split = nil
        tabs = []
        activeID = nil
    }

    /// 拆分 / 合并终端（新终端落在当前终端的工作目录）
    func toggleSplit(theme: TerminalTheme, fallbackCwd: URL) {
        if let s = split {
            s.stop()
            split = nil
            return
        }
        let cwd = active?.cwd.flatMap { URL(fileURLWithPath: $0) } ?? fallbackCwd
        split = TerminalTab(theme: theme, cwd: cwd)
        pendingFocus = true
    }
}

/// 内置终端面板：VS Code 式布局 —— 顶部标签栏 + 真 xterm 终端视图 + 右上角动作。
/// 终端本体用 SwiftTerm（完整 xterm 模拟器）：ANSI 颜色、光标、宽字符、鼠标、
/// 历史滚动、选中复制都是终端该有的行为；shell 就是用户自己的登录 shell。
struct TerminalPanel: View {

    @Environment(NotesStore.self) private var store
    var onClose: () -> Void

    @State private var term = TerminalStore.shared
    @State private var dragBase: Double? = nil
    @AppStorage("terminalPanelHeight") private var height: Double = 260

    private var theme: TerminalTheme {
        TerminalTheme.current(fontFamily: appAppearance.codeFontFamily)
    }

    var body: some View {
        VStack(spacing: 0) {
            resizeHandle
            tabBar
            Divider()
            ZStack {
                if let split = term.split, let active = term.active {
                    HSplitView {
                        TerminalHost(tab: active, theme: theme).frame(minWidth: 240)
                        TerminalHost(tab: split, theme: theme).frame(minWidth: 240)
                    }
                } else {
                    ForEach(term.tabs) { tab in
                        TerminalHost(tab: tab, theme: theme)
                            .opacity(tab.id == term.active?.id ? 1 : 0)
                            .allowsHitTesting(tab.id == term.active?.id)
                    }
                }
                if term.tabs.isEmpty {
                    Text(_LL("没有终端：点右上角「＋」或 ⌘J 开关面板",
                             "No terminal: click ＋ above or toggle with ⌘J"))
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(nsColor: theme.background))
        }
        .frame(height: height)
        .onAppear {
            if term.tabs.isEmpty { newTab() }
            wireMenuActions()
            // 只在用户主动打开/新建时抢焦点；换文件导致的面板重建不抢（见 pendingFocus 注释）
            if term.pendingFocus {
                term.pendingFocus = false
                DispatchQueue.main.async { term.active?.focus() }
            }
        }
    }

    // MARK: - 顶部：高度拖拽 + 标签栏

    private var resizeHandle: some View {
        ZStack {
            Rectangle().fill(.clear)
            Capsule().fill(Color.secondary.opacity(0.35)).frame(width: 42, height: 3)
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
                    height = min(760, max(120, base - v.translation.height))
                }
                .onEnded { _ in dragBase = nil }
        )
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(term.tabs) { tab in
                        tabChip(tab)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()

            Button {
                newTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help(_LL("新建终端", "New Terminal"))

            Spacer(minLength: 4)

            Button {
                term.toggleSplit(theme: theme, fallbackCwd: store.notesDir)
                wireMenuActions()
            } label: {
                Image(systemName: "square.split.2x1")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help(_LL("拆分终端（⌘\\）", "Split Terminal (⌘\\)"))

            Button {
                runCurrentFile()
            } label: {
                Label(_LL("运行当前文件", "Run Current File"), systemImage: "play.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(store.selectedNoteID == nil)
            .help(runHelp)

            Button {
                term.active?.restart(theme: theme)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help(_LL("重启终端", "Restart Terminal"))

            Button {
                term.active?.clear()
            } label: {
                Image(systemName: "eraser")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help(_LL("清屏（⌘K）", "Clear (⌘K)"))

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(_LL("关闭面板（⌘J）——终端继续在后台跑", "Hide Panel (⌘J) — terminals keep running"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(appAppearance.surface.map { Color(nsColor: $0) } ?? Color.clear)
    }

    private func tabChip(_ tab: TerminalTab) -> some View {
        let active = tab.id == term.active?.id
        return HStack(spacing: 5) {
            Image(systemName: tab.exited ? "exclamationmark.circle" : "terminal")
                .font(.system(size: 10))
                .foregroundStyle(tab.exited ? Color.orange : (active ? Color.primary : Color.secondary))
            Text(tab.exited ? _L("已结束", "Exited") : tab.title)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(active ? Color.primary : Color.secondary)
            Button {
                term.close(tab)
                if term.tabs.isEmpty { onClose() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .opacity(active ? 0.7 : 0.35)
            .help(_LL("关闭这个终端", "Close This Terminal"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(active ? appAppearance.accent.opacity(0.16) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            term.activeID = tab.id
            tab.focus()
        }
        .help(tab.cwd ?? "")
    }

    // MARK: - 动作

    private func newTab() {
        term.newTab(theme: theme, cwd: store.notesDir)
        wireMenuActions()
        term.active?.focus()
    }

    /// 右键菜单动作接到面板逻辑上（复制/粘贴由 SwiftTerm 自带，这里只处理清屏/重启/关闭）
    private func wireMenuActions() {
        for tab in term.tabs + [term.split].compactMap({ $0 }) {
            tab.onMenuAction = { action in
                switch action {
                case .clear: tab.clear()
                case .restart: tab.restart(theme: theme)
                case .close:
                    if term.split?.id == tab.id {
                        term.split?.stop()
                        term.split = nil
                    } else {
                        term.close(tab)
                        if term.tabs.isEmpty { onClose() }
                    }
                }
            }
        }
    }

    private var runHelp: String {
        guard let id = store.selectedNoteID else {
            return _L("先在左侧选中一个文件", "Select a file on the left first")
        }
        let ext = (id as NSString).pathExtension
        let path = store.notesDir.appendingPathComponent(id).path
        return RunCommand.command(forExt: ext, file: path)
            ?? _L("这个类型没有内置运行方式，直接在终端里敲命令即可", "No built-in runner; type the command in the terminal")
    }

    /// ▶ 运行当前文件：等价于在终端里敲 `cd 目录 && 运行命令`（先落盘，跑的是最新内容）
    private func runCurrentFile() {
        guard let id = store.selectedNoteID else { return }
        term.pendingFocus = true
        DispatchQueue.main.async { term.active?.focus() }
        if term.tabs.isEmpty { newTab() }
        guard let tab = term.active else { return }
        let url = store.notesDir.appendingPathComponent(id)
        store.flush()                                  // 编辑器内容先落盘，终端读的是磁盘文件
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if size == 0 {
            tab.run("echo \(RunCommand.shellQuote(_L("「\(url.lastPathComponent)」还是空文件（0 字节）：先写点代码再运行；C/C++ 的 `Undefined symbols: _main` 就是这个原因", "「\(url.lastPathComponent)」 is empty (0 bytes) — write code first; that is what `Undefined symbols: _main` means")))")
            return
        }
        let ext = (id as NSString).pathExtension
        guard let cmd = RunCommand.command(forExt: ext, file: url.path) else {
            tab.run("echo \(RunCommand.shellQuote(_L("「.\(ext.isEmpty ? "无扩展名" : ext)」没有内置运行方式，直接敲命令吧", "No built-in runner for .\(ext.isEmpty ? "(none)" : ext); type the command yourself")))")
            return
        }
        tab.run("cd \(RunCommand.shellQuote(url.deletingLastPathComponent().path)) && \(cmd)")
    }
}

/// SwiftTerm 视图的 SwiftUI 包装：视图实例由 TerminalTab 持有，切换标签只切显示。
private struct TerminalHost: NSViewRepresentable {
    let tab: TerminalTab
    let theme: TerminalTheme

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        tab.view as? LocalProcessTerminalView ?? MarkNoteTerminalView(frame: .zero)
    }

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {
        tab.apply(theme: theme)
    }
}

import Foundation

/// ▶「运行当前文件」的共享入口 —— 编辑器右上角的运行三角与终端工具条共用同一套行为：
/// 先把编辑器内容落盘 → 确保终端有标签页 → 在文件所在目录执行运行命令。
@MainActor
enum RunCoordinator {
    static func runCurrentFile(store: NotesStore, term: TerminalStore, theme: TerminalTheme) {
        guard let id = store.selectedNoteID ?? store.loadedNoteID else { return }
        // 冲突态下磁盘上不是编辑器里的内容：先让用户处理，别跑一份旧代码骗自己
        if store.externalConflict || store.conflictHandled {
            if term.tabs.isEmpty { term.newTab(theme: theme, cwd: store.notesDir) }
            term.active?.run("echo \(RunCommand.shellQuote(_L("文件在外部被改过，编辑器内容还没落盘 —— 先在顶栏解决冲突（或 ⌘S），再运行", "File changed on disk and your edits are not saved yet — resolve the conflict in the banner above (or ⌘S) first")))")
            store.reopenConflictPrompt()
            return
        }
        term.pendingFocus = true
        DispatchQueue.main.async { term.active?.focus() }
        if term.tabs.isEmpty { term.newTab(theme: theme, cwd: store.notesDir) }
        guard let tab = term.active else { return }
        let url = store.notesDir.appendingPathComponent(id)
        store.flush()                                  // 编辑器内容先落盘，终端读的是磁盘文件
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if size == 0 {
            tab.run("echo \(RunCommand.shellQuote(_L("「\(url.lastPathComponent)」还是空文件（0 字节）：先写点代码再运行；C/C++ 的 `Undefined symbols: _main` 就是这个原因", "「\(url.lastPathComponent)」 is empty (0 bytes) — write code first; that is what `Undefined symbols: _main` means")))")
            return
        }
        let ext = (id as NSString).pathExtension
        guard let cmd = RunCommand.command(forExt: ext, file: url.path, workspace: store.notesDir) else {
            tab.run("echo \(RunCommand.shellQuote(_L("「.\(ext.isEmpty ? "无扩展名" : ext)」没有内置运行方式，直接敲命令吧", "No built-in runner for .\(ext.isEmpty ? "(none)" : ext); type the command yourself")))")
            return
        }
        tab.run("cd \(RunCommand.shellQuote(url.deletingLastPathComponent().path)) && \(cmd)")
    }
}

import SwiftUI
import AppKit
import WebKit

extension Notification.Name {
    /// 视图模式菜单切换 → @AppStorage 视图刷新
    static let editorModeDidChange = Notification.Name("editorModeDidChange")
    /// 「插入」菜单 → 编辑器光标处插入语法
    static let insertMarkdown = Notification.Name("insertMarkdown")
    /// 编辑器内 ⌘⌫/⌘⌦ → 删除选中笔记
    static let deleteNoteRequested = Notification.Name("deleteNoteRequested")
    /// 命令面板请求
    static let commandPaletteRequested = Notification.Name("commandPaletteRequested")
    /// 面板命令（新建文件夹/导入/附件/版本——由命令面板转发给视图）
    static let requestNewCategory = Notification.Name("requestNewCategory")
    static let requestImportFiles = Notification.Name("requestImportFiles")
    static let requestImportFolder = Notification.Name("requestImportFolder")
    static let requestAttachments = Notification.Name("requestAttachments")
    static let requestVersions = Notification.Name("requestVersions")
}

/// 「插入」菜单支持的类型（随通知 object 传）
enum InsertKind: String, CaseIterable {
    case link, code, codeBlock, math, table, attachment

    var title: String {
        switch self {
        case .link: return "链接…"
        case .code: return "行内代码"
        case .codeBlock: return "代码块"
        case .math: return "公式（$$…$$）"
        case .table: return "表格"
        case .attachment: return "附件…"
        }
    }
}

@main
struct MarkNoteApp: App {
    @State private var store: NotesStore

    init() {
        // 菜单栏中文化：AppKit 依据 app 语言渲染 File/Edit/View… 系统菜单组，
        // 未显式声明开发语言时回落英文 —— 启动早期锁定为简体中文。
        UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        let store = NotesStore()
        _store = State(initialValue: store)
    }

    private static func setEditorMode(_ raw: String) {
        UserDefaults.standard.set(raw, forKey: "editorMode")
        NotificationCenter.default.post(name: .editorModeDidChange, object: nil)
    }

    /// 关于窗口
    private static func showAbout() {
        let alert = NSAlert()
        alert.messageText = "随手"
        alert.informativeText = """
        v1.1.0 · macOS 原生 Markdown 笔记应用
        数据与 start 项目无缝兼容（JSON 文件直存）

        图标主体：微软 Fluent UI Emoji 3D Frog（MIT）
        渲染管线：markdown-it + KaTeX + Mermaid + highlight.js（离线内置）
        """
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    /// 帮助弹窗：快捷键一览
    private static func showShortcuts() {
        let alert = NSAlert()
        alert.messageText = "快捷键一览"
        alert.informativeText = """
        新建笔记                          ⌘N
        保存                              ⌘S
        删除当前笔记（回收站）              ⌘⌫
        视图模式：编辑 / 分屏 / 预览        ⌘1 / ⌘2 / ⌘3
        导入文件                          ⌘⇧I
        上一篇 / 下一篇笔记                ⌥⌘↑ / ⌥⌘↓
        切换笔记目录                       ⌘⇧O
        设置（主题 / 字号 / 缩放）          ⌘,
        插入语法（链接/代码/公式/表格）      ⌥⌘L · ⌥⌘C · ⌥⌘K · ⌥⌘F · ⌥⌘T
        """
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 1024, minHeight: 640)
        }
        .defaultSize(width: 1360, height: 860)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("新建笔记") { store.createNote() }
                    .keyboardShortcut("n", modifiers: [.command])
                Button("导入文件…") { store.showImportPanel() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("切换笔记目录…") { store.chooseNotesDirectory() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button("保存") { store.saveCurrent() }
                    .keyboardShortcut("s", modifiers: [.command])
                Button("删除选中笔记（移入回收站）") { store.deleteSelection() }
                    .keyboardShortcut(.delete, modifiers: [.command])
                Divider()
                Button("上一篇笔记") { store.moveSelection(-1) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Button("下一篇笔记") { store.moveSelection(1) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            }

            CommandMenu("视图") {
                let currentMode = UserDefaults.standard.string(forKey: "editorMode") ?? EditorMode.split.rawValue
                Button {
                    Self.setEditorMode(EditorMode.editor.rawValue)
                } label: {
                    Text((currentMode == EditorMode.editor.rawValue ? "✓ " : "") + "仅编辑")
                }
                .keyboardShortcut("1", modifiers: [.command])
                Button {
                    Self.setEditorMode(EditorMode.split.rawValue)
                } label: {
                    Text((currentMode == EditorMode.split.rawValue ? "✓ " : "") + "分屏")
                }
                .keyboardShortcut("2", modifiers: [.command])
                Button {
                    Self.setEditorMode(EditorMode.preview.rawValue)
                } label: {
                    Text((currentMode == EditorMode.preview.rawValue ? "✓ " : "") + "仅预览")
                }
                .keyboardShortcut("3", modifiers: [.command])
                Divider()
                ForEach(Theme.allCases) { t in
                    Button {
                        store.setTheme(t)
                    } label: {
                        let selected = currentTheme == t
                        Text((selected ? "✓ " : "") + t.name)
                    }
                }
            }

            CommandMenu("插入") {
                Button("链接…") { NotificationCenter.default.post(name: .insertMarkdown, object: InsertKind.link) }
                    .keyboardShortcut("l", modifiers: [.command, .option])
                Button("行内代码") { NotificationCenter.default.post(name: .insertMarkdown, object: InsertKind.code) }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                Button("代码块") { NotificationCenter.default.post(name: .insertMarkdown, object: InsertKind.codeBlock) }
                    .keyboardShortcut("k", modifiers: [.command, .option])
                Button("公式（$$…$$）") { NotificationCenter.default.post(name: .insertMarkdown, object: InsertKind.math) }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                Button("表格") { NotificationCenter.default.post(name: .insertMarkdown, object: InsertKind.table) }
                    .keyboardShortcut("t", modifiers: [.command, .option])
                Button("附件…") { NotificationCenter.default.post(name: .insertMarkdown, object: InsertKind.attachment) }
            }

            CommandMenu("导出") {
                Button("导出 Markdown…") { ExportService.exportMD(store) }
                Button("导出纯文本…") { ExportService.exportTXT(store) }
                Button("导出 HTML…") { ExportService.exportHTML(store) }
                Divider()
                Button("导出 PDF…") { ExportService.exportPDF(store) }
            }

            CommandGroup(replacing: .appInfo) {
                Button("关于 随手…") { Self.showAbout() }
            }

            CommandGroup(replacing: .help) {
                Button("命令面板…") { NotificationCenter.default.post(name: .commandPaletteRequested, object: nil) }
                    .keyboardShortcut("p", modifiers: [.control, .shift])
                Button("命令面板…（⌘ 系）") { NotificationCenter.default.post(name: .commandPaletteRequested, object: nil) }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Button("快捷键一览…") { Self.showShortcuts() }
            }
        }

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}

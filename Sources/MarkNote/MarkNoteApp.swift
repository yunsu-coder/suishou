import SwiftUI
import AppKit
import WebKit
import Carbon

extension Notification.Name {
    /// 视图模式菜单切换 → @AppStorage 视图刷新
    static let editorModeDidChange = Notification.Name("editorModeDidChange")
    /// 「插入」菜单 → 编辑器光标处插入语法
    static let insertMarkdown = Notification.Name("insertMarkdown")
    /// 编辑器内 ⌘⌫/⌘⌦ → 删除选中文件
    static let deleteNoteRequested = Notification.Name("deleteNoteRequested")
    /// 命令面板请求
    static let commandPaletteRequested = Notification.Name("commandPaletteRequested")
    /// 面板命令（新建文件夹/导入/附件/版本——由命令面板转发给视图）
    static let requestNewCategory = Notification.Name("requestNewCategory")
    static let requestImportFiles = Notification.Name("requestImportFiles")
    static let requestImportFolder = Notification.Name("requestImportFolder")
    static let requestVersions = Notification.Name("requestVersions")
    /// 内联新建：⌘N/命令面板 → 侧栏进入命名行（文件/文件夹）
    static let requestNewNote = Notification.Name("requestNewNote")
    /// 快速打开（⌘P）：浮层搜索打开文件（VSCode Quick Open）
    static let quickOpenRequested = Notification.Name("quickOpenRequested")
    /// 切换侧边栏（⌘B）
    static let toggleSidebarRequested = Notification.Name("toggleSidebarRequested")
    /// 编辑器查找/替换（⌘F / ⇧⌘F）浮条请求
    static let findReplaceRequested = Notification.Name("findReplaceRequested")
}

/// 「插入」菜单支持的类型（随通知 object 传）
enum InsertKind: String, CaseIterable {
    case link, code, codeBlock, math, table, attachment

    var title: String {
        switch self {
        case .link: return _L("链接…", "Link…")
        case .code: return _L("行内代码", "Inline Code")
        case .codeBlock: return _L("代码块", "Code Block")
        case .math: return _L("公式（$$…$$）", "Equation ($$…$$)")
        case .table: return _L("表格", "Table")
        case .attachment: return _L("附件…", "Attachment…")
        }
    }
}

/// 文件打开（Finder 双击/右键打开 .md → 导入为文件）
/// 双通道：AppKit openFiles + AppleEvent kAEOpenDocuments（LaunchServices 必然路径）
final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: NotesStore?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleOpenDocuments(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEOpenDocuments))
        // ⇧⌘/ 帮助搜索为系统级热键（菜单级 keyEquivalent，非菜单项）—— 拦截在 ContentView 的
        // local monitor（先于菜单处理）；菜单探查（--dump-menu 已移除）证实帮助菜单无该项，剥键无效
    }

    @MainActor
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        sender.reply(toOpenOrPrint: .success)
        importer(filenames)
    }

    @objc func handleOpenDocuments(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let list = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) else { return }
        let paths = (0..<list.numberOfItems)
            .map { list.atIndex($0 + 1)?.stringValue ?? "" }
            .filter { !$0.isEmpty }
        DispatchQueue.main.async { [weak self] in self?.importer(paths) }
    }

    /// 文件名解析三形态归一：file:// 未解码串 / file:// URL / 裸路径（编码或未编码）
    @MainActor
    private func importer(_ paths: [String]) {
        guard let store else { return }
        var last: String?
        for raw in paths {
            guard let url = Self.robustFileURL(raw) else {
                store.showHint(_L("无法解析路径：\(raw)", "Cannot resolve path: \(raw)"))
                continue
            }
            if let id = store.importNote(from: url) { last = id }
            else { store.showHint(_L("无法读取：\(url.lastPathComponent)", "Cannot read: \(url.lastPathComponent)"))
            }
        }
        if let last {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { store.openNote(last) }
        }
    }

    /// 把各种来源的路径解析成规范 file URL
    nonisolated static func robustFileURL(_ raw: String) -> URL? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        // 1) 直接 file:// URL（含编码）→ URL(string:) 可自动解码 path
        if cleaned.hasPrefix("file://"), let url = URL(string: cleaned), url.isFileURL {
            return URL(fileURLWithPath: url.path.removingPercentEncoding ?? url.path)
        }
        // 2) 裸路径（可能带 % 编码）→ 解码后构造
        let decoded = cleaned.removingPercentEncoding ?? cleaned
        let pathPart = decoded.hasPrefix("file://") ? String(decoded.dropFirst("file://".count)) : decoded
        return URL(fileURLWithPath: pathPart)
    }
}

@main
struct MarkNoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: NotesStore

    init() {
        // 菜单栏语言与 app 界面语言一致：AppKit 依据 AppleLanguages 渲染 File/Edit/View… 系统菜单。
        // 之前硬编码 zh-Hans 导致英文界面下系统菜单仍是中文；现在跟随 AppLanguage.settings，
        // 中/英/跟随系统 三态准确，且不会在用户第一次程序后残留。
        switch UserDefaults.standard.string(forKey: "appLanguage") ?? "system" {
        case "zh": UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        case "en": UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        default:
            let first = Locale.preferredLanguages.first ?? "en"
            UserDefaults.standard.set([first.hasPrefix("zh") ? "zh-Hans" : "en"], forKey: "AppleLanguages")
        }
        let store = NotesStore()
        _store = State(initialValue: store)
        appDelegate.store = store
        // 诊断线：--verify（数据层自检）/ --probe-preview（渲染性能探针）
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--create-note") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                NotificationCenter.default.post(name: .requestNewNote, object: nil)
            }
        } else if let i = args.firstIndex(of: "--probe-render"), i + 1 < args.count {
            let id = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                Self.probeRenderNote(store, noteID: id)
            }
        } else if let i = args.firstIndex(of: "--probe-preview") {
            let target = i + 1 < args.count ? args[i + 1] : nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if let target { store.openNote(target) }
                // 等 SwiftUI 完成装载（EmptyStateView → PreviewView/WebView 实例化）再探测；
                // 若同帧就扫窗口会因 WKWebView 尚未挂载而误报 no webview
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { Self.probeRender(store) }
            }
        } else if let i = args.firstIndex(of: "--test-export"), i + 1 < args.count {
            let id = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                store.openNote(id)
                ExportService.debugExportHTML(store)
            }
        } else if let i = args.firstIndex(of: "--verify"), i + 1 < args.count {
            let id = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { Self.probeVerify(store, openID: id) }
        } else if args.contains("--verify") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { Self.probeVerify(store, openID: nil) }
        }
    }

    /// 数据层自检：写入 ~/Library/Application Support/MarkNote/verify.txt
    private static func probeVerify(_ store: NotesStore, openID: String?) {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MarkNote/verify.txt")
        var lines: [String] = []
        if let openID {
            store.openNote(openID)
        }
        lines.append("文件总数: \(store.index.count)")
        lines.append("打开文件: \(store.selectedNoteID ?? "nil") / 标题: \(store.currentTitle)")
        lines.append("搜索词: '\(store.searchQuery)' → 命中 \(store.filteredIndex.count) 篇")
        lines.append("回收站: \(store.listTrash().count) 篇")
        lines.append("图片注册表: \(store.imageRegistry.count) 条 / v\(store.imageRegistryVersion)")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// 渲染性能探针：读 WebView 内 JS 计时 → probe.txt
    private static func probeRender(_ store: NotesStore) {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MarkNote/probe.txt")
        // 遍历全部窗口（首个可能是设置窗/辅窗）
        var web: WKWebView?
        for window in NSApp.windows {
            var stack = window.contentView?.subviews ?? []
            while !stack.isEmpty, web == nil {
                let v = stack.removeLast()
                if let w = v as? WKWebView { web = w; break }
                stack.append(contentsOf: v.subviews)
            }
            if web != nil { break }
        }
        guard let web else {
            try? "no webview".write(to: url, atomically: true, encoding: .utf8)
            return
        }
        web.evaluateJavaScript("JSON.stringify({renderMd: typeof window.renderMd, lastRenderMs: window.__lastRenderMs || -1, regCount: window.__imgRegCount || 0, fontCount: window.__fontCount || 0, codeBtns: document.querySelectorAll('.copy-btn').length, jsError: window.__jsError || null, attCards: document.querySelectorAll('.attach-card').length})") { result, error in
            let text = String(describing: result ?? "NULL") + "\nERR: " + String(describing: error)
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }



    /// 离屏渲染统计：独立 WKWebView 渲染任意文件 → DOM 统计 → probe-render.txt
    /// （不依赖主窗口；TCC/模态环境下亦可执行 —— 全链路渲染健康度终验）
    private static func probeRenderNote(_ store: NotesStore, noteID: String) {
        let outURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MarkNote/probe-render.txt")
        store.openNote(noteID)
        store.prepareImageRegistry(store.workingText)

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let web = WKWebView(frame: NSRect(x: -5000, y: -5000, width: 1000, height: 800), configuration: config)
        var attached = false
        if let host = (NSApp.windows.first?.contentView ?? NSApp.keyWindow?.contentView) {
            host.addSubview(web)
            attached = true
        }
        // 窗口未建时也允许离屏加载（多数环境仍需可见树；12s 超时兜底）
        if !attached {
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                try? "no-host-or-timeout".write(to: outURL, atomically: true, encoding: .utf8)
            }
        }
        guard let html = Bundle.module.url(forResource: "preview", withExtension: "html", subdirectory: "Resources") else {
            try? "no html".write(to: outURL, atomically: true, encoding: .utf8)
            return
        }
        let md = store.workingText
        let basePath = store.notesDir.standardizedFileURL.absoluteString
        let dark = (currentTheme.dataTheme ?? "system") == "dawn" ? false : true
        let registry = store.imageRegistry

        let nav = ProbeNav(onFinish: {
            for (path, dataURL) in registry {
                let p = Self.jsStringForProbe(path)
                let d = Self.jsStringForProbe(dataURL)
                web.evaluateJavaScript("if (window.__setEntry) window.__setEntry(\(p), \(d));")
            }
            let renderJS = "window.renderMd ? window.renderMd(\(Self.jsStringForProbe(md)), \(Self.jsStringForProbe(basePath)), { dark: \(dark), resetScroll: true }) : -1;"
            web.evaluateJavaScript(renderJS) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    web.evaluateJavaScript("""
                    JSON.stringify({
                      ms: window.__lastRenderMs || -1,
                      katex: document.querySelectorAll('.katex').length,
                      sup: document.querySelectorAll('sup').length,
                      sub: document.querySelectorAll('sub').length,
                      mmOK: document.querySelectorAll('.mermaid-rendered').length,
                      mmErr: document.querySelectorAll('.mermaid-error').length,
                      jsError: window.__jsError || null,
                      mmErrMsg: (document.querySelector('.mermaid-error') || {}).textContent || null
                    })
                    """) { result, _ in
                        try? String(describing: result ?? "NULL").write(to: outURL, atomically: true, encoding: .utf8)
                    }
                }
            }
        })
        web.navigationDelegate = nav
        var req = URLRequest(url: html, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        web.load(req)
        activeProbe = nav // 强驻（navigationDelegate 为 weak，释放则永不 didFinish）
    }

    private static var activeProbe: ProbeNav?

    private static func jsStringForProbe(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              let arr = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(arr.dropFirst().dropLast())
    }

    private final class ProbeNav: NSObject, WKNavigationDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFinish() }
    }

    private static func setEditorMode(_ raw: String) {
        UserDefaults.standard.set(raw, forKey: "editorMode")
        NotificationCenter.default.post(name: .editorModeDidChange, object: nil)
    }

    /// 关于窗口
    private static func showAbout() {
        let alert = NSAlert()
        alert.messageText = _L("随手", "MarkNote")
        alert.informativeText = _L(
            """
            v1.1.0 · macOS 原生 Markdown 文件应用
            独立数据源：本机 JSON 直存，目录即库，可整体备份/迁移

            图标主体：微软 Fluent UI Emoji 3D Frog（MIT）
            渲染管线：markdown-it + KaTeX + Mermaid + highlight.js（离线内置）
            """,
            """
            v1.1.0 · Native Markdown file app for macOS
            Standalone data source: JSON stored directly on disk; each folder is a library — fully backup/migratable

            Icons: Microsoft Fluent UI Emoji 3D Frog (MIT)
            Render pipeline: markdown-it + KaTeX + Mermaid + highlight.js (bundled offline)
            """
        )
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: _L("好", "OK"))
        alert.runModal()
    }

    /// 帮助弹窗：快捷键一览
    private static func showShortcuts() {
        let alert = NSAlert()
        alert.messageText = _L("快捷键一览", "Keyboard Shortcuts")
        alert.informativeText = _L(
            """
            新建文件                         ⌘N
            保存                             ⌘S
            删除当前文件（移入废纸篓）       ⌘⌫
            视图模式：编辑 / 分屏 / 预览   ⌘1 / ⌘2 / ⌘3
            导入文件                         ⌘⇧I
            上一篇 / 下一篇笔记             ⌥⌘↑ / ⌥⌘↓
            切换工作台目录                   ⌘⇧O
            设置（主题 / 字号 / 缩放）        ⌘,
            插入语法（链接/代码/公式/表格/附件）  ⌥⌘L · ⌥⌘C · ⌥⌘K · ⌥⌘F · ⌥⌘T · ⌥⌘P
            """,
            """
            New File                         ⌘N
            Save                             ⌘S
            Delete Current File (Trash)      ⌘⌫
            View Mode: Edit / Split / Preview   ⌘1 / ⌘2 / ⌘3
            Import Files                     ⌘⇧I
            Previous / Next Note             ⌥⌘↑ / ⌥⌘↓
            Change Folder                    ⌘⇧O
            Settings (Theme / Font / Zoom)   ⌘,
            Insert Syntax (Link/Code/Equation/Table/Attachment)  ⌥⌘L · ⌥⌘C · ⌥⌘K · ⌥⌘F · ⌥⌘T · ⌥⌘P
            """
        )
        alert.addButton(withTitle: _L("好", "OK"))
        alert.runModal()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 1024, minHeight: 640)
        }
        .defaultSize(width: 1360, height: 860)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .undoRedo) {
                Button(_LL("查找…", "Find…")) { NotificationCenter.default.post(name: .findReplaceRequested, object: "find") }
                    .keyboardShortcut("f", modifiers: [.command])
                Button(_LL("替换…", "Replace…")) { NotificationCenter.default.post(name: .findReplaceRequested, object: "replace") }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .saveItem) {
                Button(_LL("关闭标签页", "Close Tab")) { store.closeCurrentTab() }
                    .keyboardShortcut("w", modifiers: [.command])
            }

            // 替换系统 New Window：⌘N = 新建文件（否则被"新建窗口"抢占）
            CommandGroup(replacing: .newItem) {
                Button(_LL("新建文件", "New File")) {
                    NotificationCenter.default.post(name: .requestNewNote, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
                Button(_LL("快速打开…", "Quick Open…")) {
                    NotificationCenter.default.post(name: .quickOpenRequested, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command])
                Button(_LL("导入文件…", "Import Files…")) { store.showImportPanel() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button(_LL("切换文件目录…", "Change Folder…")) { store.chooseNotesDirectory() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button(_LL("保存", "Save")) { store.saveNow() }
                    .keyboardShortcut("s", modifiers: [.command])
                Button(_LL("删除选中文件（物理删除）", "Delete Selected File (Permanent)")) { store.deleteSelection() }
                    .keyboardShortcut(.delete, modifiers: [.command])
                Divider()
                Button(_LL("上一篇文件", "Previous Note")) { store.moveSelection(-1) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Button(_LL("下一篇文件", "Next Note")) { store.moveSelection(1) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            }

            CommandMenu(_L("视图", "View")) {
                let currentMode = UserDefaults.standard.string(forKey: "editorMode") ?? EditorMode.split.rawValue
                Button {
                    Self.setEditorMode(EditorMode.editor.rawValue)
                } label: {
                    Text((currentMode == EditorMode.editor.rawValue ? "✓ " : "") + _L("仅编辑", "Editor Only"))
                }
                .keyboardShortcut("1", modifiers: [.command])
                Button {
                    Self.setEditorMode(EditorMode.split.rawValue)
                } label: {
                    Text((currentMode == EditorMode.split.rawValue ? "✓ " : "") + _L("分屏", "Split"))
                }
                .keyboardShortcut("2", modifiers: [.command])
                Button {
                    Self.setEditorMode(EditorMode.preview.rawValue)
                } label: {
                    Text((currentMode == EditorMode.preview.rawValue ? "✓ " : "") + _L("仅预览", "Preview Only"))
                }
                .keyboardShortcut("3", modifiers: [.command])
                Divider()
                Button(_LL("切换侧边栏", "Toggle Sidebar")) {
                    NotificationCenter.default.post(name: .toggleSidebarRequested, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command])
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

            CommandMenu(_L("插入", "Insert")) {
                Button(_LL("链接…", "Link…")) { NotificationCenter.default.post(name: .insertMarkdown, object: InsertKind.link) }
                    .keyboardShortcut("l", modifiers: [.command, .option])
                Button(_LL("行内代码", "Inline Code")) { NotificationCenter.default.post(name: .insertMarkdown, object: InsertKind.code) }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                Button(_LL("代码块", "Code Block")) { NotificationCenter.default.post(name: .insertMarkdown, object: InsertKind.codeBlock) }
                    .keyboardShortcut("k", modifiers: [.command, .option])
                Button(_LL("公式（$$…$$）", "Equation ($$…$$)")) { NotificationCenter.default.post(name: .insertMarkdown, object: InsertKind.math) }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                Button(_LL("表格", "Table")) { NotificationCenter.default.post(name: .insertMarkdown, object: InsertKind.table) }
                    .keyboardShortcut("t", modifiers: [.command, .option])
                Button(_LL("附件…", "Attachment…")) { NotificationCenter.default.post(name: .insertMarkdown, object: InsertKind.attachment) }
                    .keyboardShortcut("p", modifiers: [.command, .option])
            }

            CommandMenu(_L("AI", "AI")) {
                Button {
                    NotificationCenter.default.post(name: .aiPanelToggle, object: nil)
                } label: {
                    Text((UserDefaults.standard.bool(forKey: "aiPanelVisible") ? "✓ " : "") + _L("AI 问答面板", "AI Chat Panel"))
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                Divider()
                Button(_LL("翻译选区内容", "Translate Selection")) { NotificationCenter.default.post(name: .aiQuickActionRequested, object: AIQuickAction.translate) }
                    .disabled(!FeatureModules.isEnabled(FeatureModules.aiQuickActions))
                    .keyboardShortcut("t", modifiers: [.command, .option, .shift])
                Button(_LL("改写选区内容", "Rewrite Selection")) { NotificationCenter.default.post(name: .aiQuickActionRequested, object: AIQuickAction.rewrite) }
                    .disabled(!FeatureModules.isEnabled(FeatureModules.aiQuickActions))
                    .keyboardShortcut("r", modifiers: [.command, .option, .shift])
                Button(_LL("润色选区内容", "Polish Selection")) { NotificationCenter.default.post(name: .aiQuickActionRequested, object: AIQuickAction.polish) }
                    .disabled(!FeatureModules.isEnabled(FeatureModules.aiQuickActions))
                    .keyboardShortcut("p", modifiers: [.command, .option, .shift])
                Divider()
                Text(_LL("AI 操作前请先选中文本；结果替换选中内容（可 ⌘Z 撤销）", "Select text before using AI; the result replaces the selection (⌘Z to undo)"))
            }

            CommandMenu(_L("导出", "Export")) {
                Button(_LL("导出 Markdown…", "Export Markdown…")) { ExportService.exportMD(store) }
                Button(_LL("导出纯文本…", "Export Plain Text…")) { ExportService.exportTXT(store) }
                Button(_LL("导出 HTML…", "Export HTML…")) { ExportService.exportHTML(store) }
                Divider()
                Button(_LL("导出 PDF…", "Export PDF…")) { ExportService.exportPDF(store) }
                    .disabled(!FeatureModules.isEnabled(FeatureModules.exportPDF))
            }

            CommandGroup(replacing: .appInfo) {
                Button(_LL("关于 随手…", "About MarkNote…")) { Self.showAbout() }
            }

            CommandGroup(replacing: .help) {
                Button(_LL("命令面板…", "Command Palette…")) { NotificationCenter.default.post(name: .commandPaletteRequested, object: nil) }
                    .keyboardShortcut("p", modifiers: [.control, .shift])
                Button(_LL("命令面板…（⌘ 系）", "Command Palette… (⌘)")) { NotificationCenter.default.post(name: .commandPaletteRequested, object: nil) }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Button(_LL("快捷键一览…", "Keyboard Shortcuts…")) { Self.showShortcuts() }
            }
        }

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}

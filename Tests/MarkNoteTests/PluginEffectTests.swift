import XCTest
import Foundation
@testable import MarkNote

/// 插件生效全链路集成：安装包 → 启用 → 各消费者数据
final class PluginEffectTests: XCTestCase {

    @MainActor
    func testFullChain() throws {
        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pm = PluginManager.shared
        let plugins = dir.appendingPathComponent(".plugins", isDirectory: true)
        func json(_ o: Any) -> Data { try! JSONSerialization.data(withJSONObject: o) }

        // 1) 专家包
        let e = plugins.appendingPathComponent("it-expert", isDirectory: true)
        try FileManager.default.createDirectory(at: e, withIntermediateDirectories: true)
        try json(["id": "it-expert", "name": "IT", "version": "1", "kind": "experts", "main": "experts.json"]).write(to: e.appendingPathComponent("manifest.json"))
        try json([["id": "tux", "name": "企鹅专家", "icon": "penguin", "desc": "d", "system": "你是企鹅"]]).write(to: e.appendingPathComponent("experts.json"))

        // 2) 主题包
        let t = plugins.appendingPathComponent("it-theme", isDirectory: true)
        try FileManager.default.createDirectory(at: t, withIntermediateDirectories: true)
        try json(["id": "it-theme", "name": "IT主题", "version": "1", "kind": "theme", "main": "themes.json"]).write(to: t.appendingPathComponent("manifest.json"))
        let fontDir = t.appendingPathComponent("fonts", isDirectory: true)
        let iconDir = t.appendingPathComponent("icons", isDirectory: true)
        try FileManager.default.createDirectory(at: fontDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: iconDir, withIntermediateDirectories: true)
        try Data([0, 1, 2, 3]).write(to: fontDir.appendingPathComponent("ui.ttf"))
        try Data([0, 1, 2, 3]).write(to: fontDir.appendingPathComponent("code.ttf"))
        for name in ["folder", "folder.open", "file.markdown", "file.code", "file.data", "file.image",
                     "file.video", "file.audio", "file.document", "file.archive", "file.other",
                     "plugin", "settings", "sidebar", "search", "sparkle", "branch", "paw"] {
            try Data([0, 1, 2, 3]).write(to: iconDir.appendingPathComponent("\(name).png"))
        }
        let icons: [String: String] = [
            "folder": "icons/folder.png",
            "folder.open": "icons/folder.open.png",
            "file.markdown": "icons/file.markdown.png",
            "file.code": "icons/file.code.png",
            "file.data": "icons/file.data.png",
            "file.image": "icons/file.image.png",
            "file.video": "icons/file.video.png",
            "file.audio": "icons/file.audio.png",
            "file.document": "icons/file.document.png",
            "file.archive": "icons/file.archive.png",
            "file.other": "icons/file.other.png",
            "puzzlepiece.extension": "icons/plugin.png",
            "shippingbox": "icons/plugin.png",
            "gearshape": "icons/settings.png",
            "sidebar.left": "icons/sidebar.png",
            "magnifyingglass": "icons/search.png",
            "sparkles": "icons/sparkle.png",
            "clock.arrow.circlepath": "icons/branch.png",
            "paw": "icons/paw.png",
        ]
        try json([[
            "id": "mint", "name": "薄荷", "desc": "绿", "cssFile": "mint.css", "swatchHex": "#00ff88",
            "reviewed": true,
            "auditVersion": 2,
            "uiFont": ["file": "fonts/ui.ttf", "family": "Audit UI", "size": 12],
            "codeFont": ["file": "fonts/code.ttf", "family": "Audit Mono", "size": 12],
            "icons": icons,
            "easterEgg": ["trigger": "icon-click", "clicks": 3, "symbols": ["✨"], "message": "Hi"],
            "motion": ["ambientBubbles": true, "iconBounce": true, "tabSpring": true,
                       "durationMs": 280, "respectReduceMotion": true],
        ]]).write(to: t.appendingPathComponent("themes.json"))
        try """
        :root { --bg:#FFFFFF; --text:#111111; --text-secondary:#555555; --accent:#0066CC; --accent-ink:#0055AA; }
        """.write(to: t.appendingPathComponent("mint.css"), atomically: true, encoding: .utf8)
        // 审核锁：内容哈希必须与 reviewedHash 匹配，测试夹具也要先“审核”一次。
        let themeHash = try XCTUnwrap(ThemeQuality.contentHash(packageDir: t, mainFileName: "themes.json"))
        let rawEntries = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: t.appendingPathComponent("themes.json"))) as? [[String: Any]]
        )
        var reviewedEntry = try XCTUnwrap(rawEntries.first)
        reviewedEntry["reviewedHash"] = themeHash
        try json([reviewedEntry]).write(to: t.appendingPathComponent("themes.json"))

        // 3) 渲染包
        let r = plugins.appendingPathComponent("it-render", isDirectory: true)
        try FileManager.default.createDirectory(at: r, withIntermediateDirectories: true)
        try json(["id": "it-render", "name": "IT渲染", "version": "1", "kind": "render", "main": "render.js"]).write(to: r.appendingPathComponent("manifest.json"))
        try "window.__registerRenderPlugin({ id: 'x', use: function(){} });".write(to: r.appendingPathComponent("render.js"), atomically: true, encoding: .utf8)

        // 4) 命令包
        let c = plugins.appendingPathComponent("it-cmd", isDirectory: true)
        try FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
        try json(["id": "it-cmd", "name": "IT命令", "version": "1", "kind": "commands", "main": "commands.json"]).write(to: c.appendingPathComponent("manifest.json"))
        try json([["id": "q", "name": "打开面板", "icon": "sparkles", "category": "IT", "action": "toggleAIPanel"]]).write(to: c.appendingPathComponent("commands.json"))

        // 5) 模板包
        let s = plugins.appendingPathComponent("it-snip", isDirectory: true)
        try FileManager.default.createDirectory(at: s, withIntermediateDirectories: true)
        try json(["id": "it-snip", "name": "IT模板", "version": "1", "kind": "snippets", "main": "snippets.json"]).write(to: s.appendingPathComponent("manifest.json"))
        try json([["id": "t1", "name": "模板一", "language": "all", "text": "TEXT-A"]]).write(to: s.appendingPathComponent("snippets.json"))

        // 6) 文件类型包
        let f = plugins.appendingPathComponent("it-ft", isDirectory: true)
        try FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        try json(["id": "it-ft", "name": "IT文件", "version": "1", "kind": "filetypes", "main": "filetypes.json"]).write(to: f.appendingPathComponent("manifest.json"))
        try json(["zzz": ["icon": "bolt", "comment": "##", "indent": 6]]).write(to: f.appendingPathComponent("filetypes.json"))

        // 扫描
        UserDefaults.standard.removeObject(forKey: "pluginThemeID")
        for id in ["it-expert", "it-theme", "it-render", "it-cmd", "it-snip", "it-ft"] {
            UserDefaults.standard.removeObject(forKey: "pluginEnabled.\(id)")
        }
        pm.scan(workspaceDir: dir)
        print("DBG all=\(pm.allPackages().map { $0.id + ":" + $0.dir.path })")
        let ws = pm.allPackages().filter { $0.id.hasPrefix("it-") }
        print("DBG ws.count=\(ws.count) dir=\(dir.path)")
        XCTAssertEqual(ws.count, 6, "工作台扫到 6 包（另有全局 28 包）")
        for id in ["it-expert", "it-theme", "it-render", "it-cmd", "it-snip", "it-ft"] {
            pm.toggle(id)
        }
        // 逐个验证生效
        XCTAssertEqual(pm.allExperts().count, 1, "专家注册")
        XCTAssertEqual(pm.allExperts().first?.icon, "penguin")

        let fixtureTheme = try XCTUnwrap(
            pm.allThemes().first { $0.id.contains("it-theme") },
            "主题注册"
        )
        pm.setTheme(fixtureTheme.id)
        let theme = pm.enabledTheme()
        XCTAssertNotNil(theme, "选中的主题可读取")
        let css = try? String(contentsOfFile: theme!.cssFile, encoding: .utf8)
        XCTAssertTrue(css?.contains("#0066CC") == true, "主题 CSS 文件可读：\(String(describing: css))")

        XCTAssertEqual(pm.allRenderPlugins().count, 1, "渲染插件 JS 注册")
        XCTAssertTrue(pm.allRenderPlugins().first!.js.contains("__registerRenderPlugin"), "JS 内容完整")

        XCTAssertEqual(pm.allCommands().count, 1, "命令注册")
        XCTAssertEqual(pm.allCommands().first?.actionID, "toggleAIPanel")

        XCTAssertEqual(pm.allSnippets().count, 1, "模板注册")

        XCTAssertEqual(Workspace.lineComment(for: "zzz"), "##", "文件类型注释覆盖生效")
        XCTAssertEqual(Workspace.fileSymbol(for: "zzz"), "bolt", "图标覆盖生效")

        // 清理
        for id in ["it-expert", "it-theme", "it-render", "it-cmd", "it-snip", "it-ft"] {
            UserDefaults.standard.removeObject(forKey: "pluginEnabled.\(id)")
        }
        pm.scan(workspaceDir: dir)
    }


    /// 回归：作者把换行误写成字面反斜杠n(JSON 源文件两个反斜杠) -> 解码后仍是两字符,
    /// 应用侧 normalizeText 必须归一化为真实换行,模板插入后不再一行挤到底。
    @MainActor
    func testSnippetLiteralEscapeNormalized() throws {
        let (_, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pm = PluginManager.shared
        let p = dir.appendingPathComponent(".plugins/bad-snip", isDirectory: true)
        try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true)
        func json(_ o: Any) -> Data { try! JSONSerialization.data(withJSONObject: o) }
        try json(["id": "bad-snip", "name": "坏模板", "version": "1", "kind": "snippets", "main": "snippets.json"])
            .write(to: p.appendingPathComponent("manifest.json"))
        // Swift 源码 LINE1\\nLINE2: 在 Swift 里是字面反斜杠+n(2字符),序列化进 JSON 后模拟\\n 的坏包
        try json([["id": "t", "name": "两行", "language": "all", "text": "LINE1\\nLINE2\\nLINE3"]])
            .write(to: p.appendingPathComponent("snippets.json"))

        pm.scan(workspaceDir: dir)
        pm.toggle("bad-snip")
        defer {
            UserDefaults.standard.removeObject(forKey: "pluginEnabled.bad-snip")
            pm.scan(workspaceDir: dir)
        }
        let sn = pm.allSnippets().first { $0.id.hasPrefix("sn-bad-snip") }
        XCTAssertNotNil(sn, "坏包模板应注册成功")
        let text = sn?.text ?? ""
        // 用 Unicode 标量构造真实换行符,源码里不留字面换行
        let nl = "\u{0A}"
        XCTAssertTrue(text.contains(nl), "应含真实换行")
        XCTAssertFalse(text.contains("LINE1\\nLINE2"), "不应残留字面反斜杠n")
        XCTAssertEqual(text.components(separatedBy: nl).count, 3, "应解码为 3 行:" + text.debugDescription)
    }
}

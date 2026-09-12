import XCTest
import AppKit
@testable import MarkNote

/// Bubble Pop 主题包：字体 / 图标 / 彩蛋 / 亮色配色都必须在真实插件扫描链路中可用。
final class BubblePopThemeTests: XCTestCase {

    @MainActor
    func testBubblePopPackageExposesFontsIconsAndEasterEgg() throws {
        let (_, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let src = root.appendingPathComponent("plugins-market/theme-bubble-pop", isDirectory: true)
        let dst = dir.appendingPathComponent(".plugins/theme-bubble-pop", isDirectory: true)
        try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: src, to: dst)

        UserDefaults.standard.set(true, forKey: "pluginEnabled.theme-bubble-pop")
        defer {
            UserDefaults.standard.removeObject(forKey: "pluginEnabled.theme-bubble-pop")
        }

        let pm = PluginManager.shared
        pm.scan(workspaceDir: dir)
        let themes = pm.allThemes().filter { $0.id.contains("theme-bubble-pop") }
        XCTAssertEqual(themes.count, 1, "只保留亮色单主题（暗色以后按 v4 规则重做）")
        XCTAssertTrue(pm.themeIssues(for: "theme-bubble-pop").isEmpty, "Bubble Pop 应通过质量门槛")

        for theme in themes {
            XCTAssertTrue(FileManager.default.fileExists(atPath: theme.cssFile))
            XCTAssertEqual(theme.uiFont?.family, "Fusion Pixel 12px Proportional zh_hans")
            XCTAssertEqual(theme.codeFont?.family, "Fusion Pixel 12px Monospaced zh_hans")
            XCTAssertEqual(theme.displayFont?.family, "Silkscreen")
            XCTAssertEqual(theme.uiFont?.size, 12)
            XCTAssertEqual(theme.easterEgg?.clicks, 5)
            XCTAssertFalse(theme.easterEgg?.symbols.isEmpty ?? true)
            XCTAssertEqual(theme.motion?.ambientBubbles, true)
            XCTAssertEqual(theme.motion?.respectReduceMotion, true)
            for key in ThemeQuality.requiredIconKeys(for: 1).sorted() {
                let path = try XCTUnwrap(theme.icons[key], "缺少主题图标：\(key)")
                XCTAssertTrue(FileManager.default.fileExists(atPath: path), "图标文件不存在：\(path)")
            }
            if let font = theme.uiFont {
                ThemeFonts.register(URL(fileURLWithPath: font.file))
                XCTAssertNotNil(NSFont(name: font.family, size: 12), "主题字体应可注册并解析")
            }
        }
    }

    func testCssOnlyThemeFailsQualityGate() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("theme-audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try """
        :root { --bg: #FFFFFF; --text: #000000; --text-secondary: #444444; --accent: #666666; }
        """.write(to: dir.appendingPathComponent("plain.css"), atomically: true, encoding: .utf8)

        let json = """
        { "id": "plain", "name": "Plain", "cssFile": "plain.css", "swatchHex": "#666666" }
        """
        let spec = try JSONDecoder().decode(ThemeSpec.self, from: Data(json.utf8))
        let issues = ThemeQuality.audit(spec, packageDir: dir)
        XCTAssertTrue(issues.contains { $0.contains("字体") }, "纯换色主题必须因缺少专属字体被拒")
        XCTAssertTrue(issues.contains { $0.contains("图标") }, "纯换色主题必须因缺少专属图标被拒")
        XCTAssertTrue(issues.contains { $0.contains("彩蛋") }, "纯换色主题必须因缺少彩蛋被拒")
        XCTAssertTrue(issues.contains { $0.contains("动效") || $0.contains("特效") }, "纯换色主题必须因缺少动效被拒")
    }

    func testWrongSemanticIconKeyIsRejected() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("theme-semantic-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try ":root { --bg:#FFFFFF; --text:#000000; --text-secondary:#444444; --accent:#0055AA; }"
            .write(to: dir.appendingPathComponent("plain.css"), atomically: true, encoding: .utf8)
        let json = """
        {
          "id": "bad-semantic", "name": "Bad", "cssFile": "plain.css",
          "icons": { "terminal": "icons/terminal.png" }
        }
        """
        let spec = try JSONDecoder().decode(ThemeSpec.self, from: Data(json.utf8))
        let issues = ThemeQuality.audit(spec, packageDir: dir)
        XCTAssertTrue(issues.contains { $0.contains("图标语义未适配：terminal") },
                      "Codex 语义键不得混入随手语义：\(issues)")
        XCTAssertTrue(issues.contains { $0.contains("图标语义未覆盖：folder") },
                      "缺少随手语义槽位必须拦截：\(issues)")
    }

    /// 回归：插件扫描在持锁时发通知会造成 ThemeCatalog 回调查询死锁。
    func testPluginNotificationDoesNotDeadlockObservers() {
        let pm = PluginManager.shared
        let notified = expectation(description: "plugins-changed")
        let token = NotificationCenter.default.addObserver(
            forName: PluginManager.changedNotification, object: nil, queue: nil
        ) { _ in
            _ = pm.allThemes()   // 若通知仍在锁内发送，这里会永久等待
            notified.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }
        DispatchQueue.global(qos: .userInitiated).async {
            pm.scan(workspaceDir: nil)
        }
        wait(for: [notified], timeout: 5)
    }

    /// 审核锁：主题内容（图标/CSS/字体）任何变化都必须重新人工审核。
    func testThemeContentChangeInvalidatesReview() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let src = root.appendingPathComponent("plugins-market/theme-bubble-pop", isDirectory: true)
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("theme-review-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: src, to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }

        let specs = try JSONDecoder().decode(
            [ThemeSpec].self,
            from: Data(contentsOf: temp.appendingPathComponent("theme.json"))
        )
        let spec = try XCTUnwrap(specs.first)
        XCTAssertTrue(ThemeQuality.audit(spec, packageDir: temp).isEmpty, "初始包应通过审核")

        let iconRel = try XCTUnwrap(spec.icons?["folder"])
        let iconURL = temp.appendingPathComponent(iconRel)
        let handle = try FileHandle(forWritingTo: iconURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0]))
        try handle.close()

        let issues = ThemeQuality.audit(spec, packageDir: temp)
        XCTAssertTrue(issues.contains { $0.contains("等待人工审核") },
                      "资源变化后必须失效审核：\(issues)")
    }
}

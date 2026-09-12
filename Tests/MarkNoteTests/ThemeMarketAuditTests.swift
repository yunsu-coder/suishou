import XCTest
@testable import MarkNote

/// 市场主题包全量审计：所有 theme-* 包都必须通过硬门槛。
final class ThemeMarketAuditTests: XCTestCase {

    @MainActor
    func testAllMarketThemePackagesPassQualityGate() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("plugins-market", isDirectory: true)
        let packages = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]
        ).filter {
            $0.lastPathComponent.hasPrefix("theme-") &&
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        XCTAssertFalse(packages.isEmpty, "市场应至少有一个合格主题包")

        let pm = PluginManager.shared
        for src in packages {
            let (_, temp) = try TestEnv.makeStore()
            defer { try? FileManager.default.removeItem(at: temp) }
            let dest = temp.appendingPathComponent(".plugins/\(src.lastPathComponent)", isDirectory: true)
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: src, to: dest)
            UserDefaults.standard.set(true, forKey: "pluginEnabled.\(src.lastPathComponent)")
            defer { UserDefaults.standard.removeObject(forKey: "pluginEnabled.\(src.lastPathComponent)") }

            pm.scan(workspaceDir: temp)
            let issues = pm.themeIssues(for: src.lastPathComponent)
            XCTAssertTrue(issues.isEmpty, "\(src.lastPathComponent) 未通过质量门槛：\(issues)")
            let themes = pm.allThemes().filter { $0.id.contains(src.lastPathComponent) }
            XCTAssertGreaterThanOrEqual(themes.count, 1, "\(src.lastPathComponent) 应至少注册一套主题")
        }
    }

    /// 候选升级稿：技术审计必须全部通过，只允许“等待人工审核”这一项。
    @MainActor
    func testReviewCandidatesAreTechnicallyReady() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("plugins-market/_review", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let candidates = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]
        ).filter {
            let suffix = $0.lastPathComponent.split(separator: "-").last.map(String.init) ?? ""
            return suffix.hasPrefix("v") && Int(suffix.dropFirst()) != nil &&
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        guard !candidates.isEmpty else { return }   // 无待审稿时跳过

        let pm = PluginManager.shared
        for src in candidates {
            let manifest = try XCTUnwrap(
                JSONSerialization.jsonObject(
                    with: Data(contentsOf: src.appendingPathComponent("manifest.json"))
                ) as? [String: Any]
            )
            let pluginID = try XCTUnwrap(manifest["id"] as? String)
            let (_, temp) = try TestEnv.makeStore()
            defer { try? FileManager.default.removeItem(at: temp) }
            let dest = temp.appendingPathComponent(".plugins/\(src.lastPathComponent)", isDirectory: true)
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: src, to: dest)
            UserDefaults.standard.set(true, forKey: "pluginEnabled.\(pluginID)")
            defer { UserDefaults.standard.removeObject(forKey: "pluginEnabled.\(pluginID)") }

            pm.scan(workspaceDir: temp)
            let issues = pm.themeIssues(for: pluginID)
            XCTAssertFalse(issues.isEmpty, "候选稿必须处于待人工审核状态")
            let blocking = issues.filter { !$0.contains("等待人工审核") }
            XCTAssertTrue(blocking.isEmpty, "\(pluginID) 候选稿技术门槛未通过：\(blocking)")
        }
    }

    /// 兜底规则：至少一个主题包启用；关闭最后一个会被拒绝。
    /// 统一标准：市场里的主题必须是 auditVersion ≥ 5（含编辑器语法配色），且只保留一套配色；
    /// 纸底必须是真·亮色（亮度 >0.5）、真·暗色（<0.2）或**中色**（0.2–0.5）。
    /// 中色档额外要求正文对比 ≥7:1 —— 避免"灰扑扑又看不清"的半成品。
    @MainActor
    func testMarketThemesAreV4AndLightOnly() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("plugins-market", isDirectory: true)
        let packages = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]
        ).filter {
            $0.lastPathComponent.hasPrefix("theme-") &&
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        XCTAssertFalse(packages.isEmpty)

        for pkg in packages {
            // 包内主文件名以 manifest 为准（默认 theme.json）
            let manifest = (try? Data(contentsOf: pkg.appendingPathComponent("manifest.json")))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let mainFile = (manifest?["main"] as? String) ?? "theme.json"
            let data = try Data(contentsOf: pkg.appendingPathComponent(mainFile))
            let entries = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                "\(pkg.lastPathComponent) 的 \(mainFile) 应为数组")
            XCTAssertEqual(entries.count, 1,
                           "\(pkg.lastPathComponent) 应只保留一套主题（当前亮色单主题；暗色以后按 v4 重做）")

            for e in entries {
                let version = e["auditVersion"] as? Int ?? 1
                XCTAssertGreaterThanOrEqual(version, 5,
                                            "\(pkg.lastPathComponent) 必须满足 auditVersion ≥ 5（含编辑器语法配色）")
                let cssFile = try XCTUnwrap(e["cssFile"] as? String)
                let css = try String(contentsOf: pkg.appendingPathComponent(cssFile), encoding: .utf8)
                let layers = PluginCSS.parse(css)
                for variant in ["dawn", "night"] {
                    for dark in [false, true] {
                        let vars = PluginCSS.vars(layers, variant: variant, dark: dark)
                        guard let bg = PluginCSS.color(from: vars["--bg"]) else { continue }
                        let l = PluginCSS.luminance(bg)
                        XCTAssertTrue(l > 0.5 || l < 0.2 || (0.2...0.5).contains(l),
                                      "\(pkg.lastPathComponent) 的纸底必须明确落在亮 / 中 / 暗三档之一，当前 \(String(format: "%.2f", l))")
                        if (0.2...0.5).contains(l), let text = PluginCSS.color(from: vars["--text"]) {
                            let lt = PluginCSS.luminance(text)
                            let ratio = (max(lt, l) + 0.05) / (min(lt, l) + 0.05)
                            XCTAssertGreaterThanOrEqual(ratio, 7.0,
                                String(format: "%@ 是中色纸底，正文对比需 ≥7:1，当前 %.2f:1", pkg.lastPathComponent, ratio))
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testAtLeastOneThemePackageAlwaysEnabled() throws {
        let pm = PluginManager.shared
        let ids = ["theme-bubble-pop", "theme-sumi-paper"]
        let saved = ids.map { ($0, UserDefaults.standard.object(forKey: "pluginEnabled.\($0)")) }
        defer {
            for (id, value) in saved {
                if let value {
                    UserDefaults.standard.set(value, forKey: "pluginEnabled.\(id)")
                } else {
                    UserDefaults.standard.removeObject(forKey: "pluginEnabled.\(id)")
                }
            }
            pm.scan(workspaceDir: nil)
        }

        for id in ids { UserDefaults.standard.set(false, forKey: "pluginEnabled.\(id)") }
        pm.scan(workspaceDir: nil)
        var enabled = pm.allPackages().filter { $0.kind == .theme && $0.enabled }
        XCTAssertFalse(enabled.isEmpty, "全部关闭时必须自动启用兜底主题包")

        for pkg in enabled.dropFirst() { _ = pm.toggle(pkg.id) }
        enabled = pm.allPackages().filter { $0.kind == .theme && $0.enabled }
        let only = try XCTUnwrap(enabled.first)
        XCTAssertEqual(enabled.count, 1)
        if case .blockedLastTheme = pm.toggle(only.id) {
            // 预期：最后一个主题包不可关闭
        } else {
            XCTFail("关闭最后一个主题包必须被阻止")
        }
        XCTAssertTrue(pm.allPackages().first { $0.id == only.id }?.enabled == true)
    }
}

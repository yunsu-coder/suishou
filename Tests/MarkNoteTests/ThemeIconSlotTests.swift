import XCTest
import Foundation
@testable import MarkNote

/// 语言图标槽位：app 侧映射 + 主题质量规则（v6 起整组必填，v5 可选补齐）
final class ThemeIconSlotTests: XCTestCase {

    func testThemeIconKeyPerLanguage() {
        let cases: [(String, String)] = [
            ("py", "file.python"), ("pyw", "file.python"),
            ("js", "file.javascript"), ("jsx", "file.javascript"),
            ("ts", "file.typescript"), ("tsx", "file.typescript"),
            ("go", "file.go"), ("rs", "file.rust"),
            ("c", "file.c"), ("h", "file.c"),
            ("cpp", "file.cpp"), ("hpp", "file.cpp"),
            ("cs", "file.csharp"), ("java", "file.java"), ("kt", "file.kotlin"),
            ("swift", "file.swift"),
            ("html", "file.html"), ("vue", "file.vue"), ("xml", "file.xml"),
            ("css", "file.css"), ("scss", "file.css"),
            ("sh", "file.shell"), ("zsh", "file.shell"),
            ("json", "file.json"), ("yml", "file.yaml"),
            ("sql", "file.sql"), ("rb", "file.ruby"), ("php", "file.php"),
            ("lua", "file.lua"), ("asm", "file.asm"), ("r", "file.r"),
            ("md", "file.markdown"), ("png", "file.image"), ("pdf", "file.document"),
        ]
        for (ext, key) in cases {
            XCTAssertEqual(Workspace.themeIconKey(for: ext), key, "扩展名 .\(ext) 的图标槽位")
        }
    }

    func testLanguageSlotsAreKnownToQualityRules() {
        for key in ["file.python", "file.cpp", "file.html", "file.r"] {
            XCTAssertTrue(ThemeQuality.languageIconKeys.contains(key), "\(key) 应登记为已知语言槽位")
            XCTAssertTrue(ThemeQuality.knownIconKeys.contains(key), "\(key) 不应被判成「语义未适配」")
        }
    }

    func testV6RequiresWholeLanguageSetButV5DoesNot() {
        let icons = ["file.python": "icons/file.python-64.png"]
        XCTAssertTrue(ThemeQuality.missingLanguageIcons(for: 5, icons: icons).isEmpty,
                      "v5 主题可以只补一部分语言图标")
        let missing = ThemeQuality.missingLanguageIcons(for: 6, icons: icons)
        XCTAssertEqual(missing.count, ThemeQuality.languageIconKeys.count - 1,
                       "v6 起必须整组补齐")
        XCTAssertTrue(missing.contains("file.go"))
    }

    func testDeclaredLanguageIconsMustBeDistinct() {
        let icons = [
            "file.python": "icons/a.png",
            "file.go": "icons/a.png",          // 复用同一资源 → 应被判重
        ]
        let keys = ThemeQuality.distinctIconKeys(for: 5, icons: icons)
        XCTAssertTrue(keys.contains("file.python") && keys.contains("file.go"))
    }
}

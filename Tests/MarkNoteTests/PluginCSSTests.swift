import XCTest
import AppKit
@testable import MarkNote

/// 插件主题 CSS 简化级联解析：变体（dawn/night）+ 媒体门控（light/dark）+ 颜色值解析。
/// 覆盖市场包实际使用的全部结构形态（:root / :root[data-theme=…] / @media）。
final class PluginCSSTests: XCTestCase {

    func testSelectors_withVariantBlocks_perMatchingVariant() {
        let css = """
        :root[data-theme="dawn"] { --bg: #FFFFFF; --text: #222; }
        :root[data-theme="night"] { --bg: #101012; --text: #EEE; }
        """
        let layers = PluginCSS.parse(css)
        let dawn = PluginCSS.vars(layers, variant: "dawn", dark: false)
        XCTAssertEqual(dawn["--bg"], "#FFFFFF")
        XCTAssertEqual(dawn["--text"], "#222")
        let night = PluginCSS.vars(layers, variant: "night", dark: true)
        XCTAssertEqual(night["--bg"], "#101012")
        // daemon 变体不得串夜航者变量（后层覆盖规则下外置校验）
        XCTAssertNotEqual(night["--bg"], dawn["--bg"])
    }

    func testSelectors_dualSelectorSameValues() {
        // Dracula：dawn/night 双选择器同一套暗色值 —— 两种门控下都应是暗底
        let css = """
        :root[data-theme="dawn"], :root[data-theme="night"] {
          --bg: #282a36;
          --accent: #bd93f9;
        }
        """
        let layers = PluginCSS.parse(css)
        for v in ["dawn", "night"] {
            for d in [false, true] {
                let vars = PluginCSS.vars(layers, variant: v, dark: d)
                XCTAssertEqual(vars["--bg"], "#282a36", "variant=\(v) dark=\(d)")
            }
        }
    }

    func testMediaGate_gruvboxStyle() {
        // Gruvbox：:root 深色预设 + @media light 浅色 —— 门控按深/浅分流
        let css = """
        :root { --bg: #1d2021; --text: #ebdbb2; }
        @media (prefers-color-scheme: light) {
          :root { --bg: #fbf1c7; --text: #282828; }
        }
        """
        let layers = PluginCSS.parse(css)
        XCTAssertEqual(PluginCSS.vars(layers, variant: "dawn", dark: false)["--bg"], "#fbf1c7")
        XCTAssertEqual(PluginCSS.vars(layers, variant: "dawn", dark: true)["--bg"], "#1d2021")
        XCTAssertEqual(PluginCSS.vars(layers, variant: "night", dark: true)["--bg"], "#1d2021")
    }

    func testMediaGate_overridesInFileOrder_layerOrderRespected() {
        let css = """
        :root { --bg: #FFF; --accent: #111; }
        @media (prefers-color-scheme: dark) { :root { --bg: #000; } }
        """
        let layers = PluginCSS.parse(css)
        // 媒体块后置：dark 门控下 --bg 覆盖；未触碰的 --accent 仍取 :root
        let dark = PluginCSS.vars(layers, variant: "dawn", dark: true)
        XCTAssertEqual(dark["--bg"], "#000")
        XCTAssertEqual(dark["--accent"], "#111")
    }

    func testPlainRoot_appliesToBothVariants() {
        let css = ":root { --bg: #ECEFF4; --accent: #5E81AC; }"
        let layers = PluginCSS.parse(css)
        XCTAssertEqual(PluginCSS.vars(layers, variant: "dawn", dark: false)["--bg"], "#ECEFF4")
        XCTAssertEqual(PluginCSS.vars(layers, variant: "night", dark: true)["--bg"], "#ECEFF4")
    }

    func testCommentsAndTableFixups_doNotPollute() {
        let css = """
        /* 注释：:root[data-theme="dawn"] { --fake: #000; } */
        :root[data-theme="night"] .markdown-body th { background: var(--surface); }
        :root[data-theme="night"] { --bg: #111; }
        """
        let layers = PluginCSS.parse(css)
        let vars = PluginCSS.vars(layers, variant: "night", dark: false)
        XCTAssertEqual(vars["--bg"], "#111")
        XCTAssertNil(vars["--fake"])     // 注释不生效
        // 非变量选择器（th fixup）不产生变量层噪音 —— 只读 --bg 校验即可
        XCTAssertNil(vars["--surface"])
    }

    func testColorParsing_rgbRgbaHex() {
        // 全大写 + 带空格，与市场包实际写法一致
        XCTAssertEqual(PluginCSS.color(from: "#282a36")?.description, NSColor(srgbRed: 0x28 / 255, green: 0x2a / 255, blue: 0x36 / 255, alpha: 1).description)
        XCTAssertEqual(PluginCSS.color(from: "#FFF")?.description, NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1).description)
        XCTAssertEqual(PluginCSS.color(from: "rgba(248, 248, 242, 0.10)")?.alphaComponent ?? -1, 0.1, accuracy: 0.001)
        XCTAssertEqual(PluginCSS.color(from: "rgba(76, 201, 240, 0.16)")?.redComponent ?? -1, 76.0 / 255.0, accuracy: 0.001)
        // 0..1 浮点分量
        XCTAssertEqual(PluginCSS.color(from: "rgba(0.5, 0.5, 0.5, 0.5)")?.redComponent ?? -1, 0.5, accuracy: 0.001)
        XCTAssertNil(PluginCSS.color(from: "var(--bg)"))
        XCTAssertNil(PluginCSS.color(from: "rgba(1)"))
    }

    func testLuminance_darkLightThreshold() {
        let white = PluginCSS.color(from: "#FFFFFF")!
        let black = PluginCSS.color(from: "#000000")!
        let dracula = PluginCSS.color(from: "#282a36")!
        let paper = PluginCSS.color(from: "#f5f0e6")!
        XCTAssertTrue(PluginCSS.luminance(white) > 0.9)
        XCTAssertTrue(PluginCSS.luminance(black) < 0.01)
        XCTAssertTrue(PluginCSS.luminance(dracula) < 0.35)   // 暗底
        XCTAssertTrue(PluginCSS.luminance(paper) > 0.5)      // 浅底
    }

    func testCaretAdaptsWhenAccentHasLowContrast() {
        let background = PluginCSS.color(from: "#F2ECBC")!
        let text = PluginCSS.color(from: "#4A4238")!
        let lowContrastAccent = PluginCSS.color(from: "#E6C384")!
        let highContrastAccent = PluginCSS.color(from: "#1E66F5")!

        let fallback = AppAppearance.caretColor(accent: lowContrastAccent,
                                                background: background,
                                                text: text)
        XCTAssertEqual(fallback.description, text.description, "低对比 accent 必须回退为正文色")
        XCTAssertGreaterThanOrEqual(AppAppearance.contrastRatio(fallback, background), 4.5)

        let themed = AppAppearance.caretColor(accent: highContrastAccent,
                                              background: background,
                                              text: text)
        XCTAssertEqual(themed.description, highContrastAccent.description, "高对比 accent 保留主题光标色")
        XCTAssertGreaterThanOrEqual(AppAppearance.contrastRatio(themed, background), 3.0)
    }

    func testThemeOptionsExposePluginThemesOnly() {
        let options = allThemeOptions
        XCTAssertFalse(options.contains { $0.id.hasPrefix("builtin:") }, "内置主题不得出现在用户菜单")
        XCTAssertEqual(Set(options.map(\.id)).count, options.count, "主题 id 不得重复")
        XCTAssertEqual(options.map(\.id).sorted(),
                       PluginManager.shared.allThemes().map { "plugin:\($0.id)" }.sorted())
    }
}

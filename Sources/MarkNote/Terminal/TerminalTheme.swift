import AppKit
import SwiftTerm

/// 终端配色：正文/底色跟随当前主题，ANSI 16 色用 VS Code 默认的那两套
/// （Dark+ / Light+）—— 终端里 `ls --color`、git、编译器的上色和 VS Code 一致。
struct TerminalTheme {
    let font: NSFont
    let background: NSColor
    let foreground: NSColor
    let caret: NSColor
    let ansi: [SwiftTerm.Color]

    /// 指纹：只有真变了才重新套用（installColors 会清缓存并整屏重绘）
    var fingerprint: String {
        "\(font.fontName)-\(font.pointSize)-\(background.terminalHex)-\(foreground.terminalHex)-\(caret.terminalHex)-\(appAppearance.dark)"
    }

    static func current(fontFamily: String?, fontSize: CGFloat = 12) -> TerminalTheme {
        let dark = appAppearance.dark
        return TerminalTheme(
            font: terminalFont(family: fontFamily, size: fontSize),
            background: appAppearance.editorBackground,
            foreground: appAppearance.editorForeground,
            caret: NSColor(appAppearance.accent),
            ansi: dark ? Self.vsCodeDark : Self.vsCodeLight
        )
    }

    /// 终端字体：先用主题的代码字体，但它必须画得出 Powerline / Nerd 图标
    /// （powerlevel10k 之类提示符全靠这些字形）；画不出就换一个覆盖广的等宽字体，
    /// 否则提示符会变成一排 "?" 方框 —— 这是实测出来的问题。
    static func terminalFont(family: String?, size: CGFloat) -> NSFont {
        let preferred = MarkdownEditorView.resolveFont(family: family ?? "mono", size: size)
        if coversTerminalGlyphs(preferred) { return preferred }
        let fallbacks = [
            "MesloLGS-NF-Regular", "MesloLGS NF", "MesloLGM Nerd Font", "MesloLGS NF Regular",
            "JetBrainsMono-Regular", "JetBrainsMonoNF-Regular", "HackNerdFont-Regular",
            "FiraCodeNF-Regular", "FiraCode-Regular", "Menlo-Regular", "SFMono-Regular",
        ]
        for name in fallbacks {
            if let f = NSFont(name: name, size: size), coversTerminalGlyphs(f) { return f }
        }
        return preferred
    }

    /// 覆盖检测：Powerline 分隔符 + 几个 Nerd 图标（p10k 常用）
    static func coversTerminalGlyphs(_ font: NSFont) -> Bool {
        let probe: [UniChar] = [0xE0B0, 0xE0B2, 0xE0B4, 0xF015, 0xF07B, 0xF0A0]
        var glyphs = [CGGlyph](repeating: 0, count: probe.count)
        let ok = CTFontGetGlyphsForCharacters(font as CTFont, probe, &glyphs, probe.count)
        return ok && !glyphs.contains(0)
    }

    /// VS Code Dark+ 默认终端 ANSI
    static let vsCodeDark: [SwiftTerm.Color] = [
        c("#000000"), c("#CD3131"), c("#0DBC79"), c("#E5E510"),
        c("#2472C8"), c("#BC3FBC"), c("#11A8CD"), c("#E5E5E5"),
        c("#666666"), c("#F14C4C"), c("#23D18B"), c("#F5F543"),
        c("#3B8EEA"), c("#D670D6"), c("#29B8DB"), c("#E5E5E5"),
    ]

    /// VS Code Light+ 默认终端 ANSI
    static let vsCodeLight: [SwiftTerm.Color] = [
        c("#000000"), c("#CD3131"), c("#00BC00"), c("#949800"),
        c("#0451A5"), c("#BC05BC"), c("#0598BC"), c("#555555"),
        c("#666666"), c("#CD3131"), c("#14CE14"), c("#B5BA00"),
        c("#0451A5"), c("#BC05BC"), c("#0598BC"), c("#A5A5A5"),
    ]

    private static func c(_ hex: String) -> SwiftTerm.Color {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = UInt32(s, radix: 16) ?? 0
        func ch(_ shift: UInt32) -> UInt16 { UInt16((v >> shift) & 0xFF) * 257 }
        return SwiftTerm.Color(red: ch(16), green: ch(8), blue: ch(0))
    }
}

private extension NSColor {
    /// 指纹用的十六进制串（与 Flowchart 的同名扩展区分开）
    var terminalHex: String {
        guard let c = usingColorSpace(.sRGB) else { return "?" }
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)))
    }
}

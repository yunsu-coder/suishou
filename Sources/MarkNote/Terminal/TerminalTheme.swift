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

    static func current(fontFamily: String?, fontSize: CGFloat = 12) -> TerminalTheme {
        let dark = appAppearance.dark
        return TerminalTheme(
            font: MarkdownEditorView.resolveFont(family: fontFamily ?? "mono", size: fontSize),
            background: appAppearance.editorBackground,
            foreground: appAppearance.editorForeground,
            caret: NSColor(appAppearance.accent),
            ansi: dark ? Self.vsCodeDark : Self.vsCodeLight
        )
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

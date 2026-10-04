import AppKit

/// 代码文件配色：固定采用业界最流行的方案 —— 暗色 One Dark Pro、亮色 One Light
/// （VS Code / Atom 装机量最高的两套主题，同源同族）。
///
/// 刻意**不跟随主题包**：主题负责 UI 与 Markdown 观感，代码文件用行业通用色，
/// 换主题不会把代码染成"主题色"，代码的对比度与辨识度始终稳定。
/// 想换方案只需改本文件（如 GitHub Dark、Dracula、Monokai）。
enum CodePalette {

    static func isDark() -> Bool { appAppearance.dark }

    /// token 颜色（暗色 One Dark Pro / 亮色 One Light）
    static func color(for kind: CodeKind) -> NSColor {
        isDark() ? darkColor(kind) : lightColor(kind)
    }

    // MARK: - One Dark Pro（#282C34 底 / #ABB2BF 字）

    private static func darkColor(_ kind: CodeKind) -> NSColor {
        switch kind {
        case .keyword:  return NSColor.sRGB(0.776, 0.471, 0.867)   // #C678DD
        case .type:     return NSColor.sRGB(0.898, 0.753, 0.482)   // #E5C07B
        case .string:   return NSColor.sRGB(0.596, 0.765, 0.475)   // #98C379
        case .comment:  return NSColor.sRGB(0.498, 0.518, 0.557)   // #7F848E（比 One Dark 原版提一档：暗底上 ≥4.5:1）
        case .number:   return NSColor.sRGB(0.820, 0.603, 0.400)   // #D19A66
        case .preproc:  return NSColor.sRGB(0.337, 0.714, 0.761)   // #56B6C2
        case .function: return NSColor.sRGB(0.380, 0.686, 0.937)   // #61AFEF
        case .variable: return NSColor.sRGB(0.878, 0.424, 0.459)   // #E06C75
        case .tag:      return NSColor.sRGB(0.878, 0.424, 0.459)   // #E06C75
        case .property: return NSColor.sRGB(0.820, 0.603, 0.400)   // #D19A66
        case .constant: return NSColor.sRGB(0.820, 0.603, 0.400)   // #D19A66
        case .escape:   return NSColor.sRGB(0.337, 0.714, 0.761)   // #56B6C2（与预处理同族）
        }
    }

    // MARK: - One Light（#FAFAFA 底 / #383A42 字）

    /// One Light 色相不变，压暗到白底 ≥4.5:1（原版 #C18401/#50A14F/#E45649 只有 3.2~3.7:1，读起来发飘）
    private static func lightColor(_ kind: CodeKind) -> NSColor {
        switch kind {
        case .keyword:  return NSColor.sRGB(0.651, 0.149, 0.643)   // #A626A4
        case .type:     return NSColor.sRGB(0.541, 0.392, 0.000)   // #8A6400
        case .string:   return NSColor.sRGB(0.239, 0.478, 0.235)   // #3D7A3C
        case .comment:  return NSColor.sRGB(0.431, 0.447, 0.486)   // #6E727C
        case .number:   return NSColor.sRGB(0.596, 0.408, 0.004)   // #986801
        case .preproc:  return NSColor.sRGB(0.004, 0.420, 0.608)   // #016B9B
        case .function: return NSColor.sRGB(0.204, 0.341, 0.784)   // #3457C8
        case .variable: return NSColor.sRGB(0.788, 0.247, 0.196)   // #C93F32
        case .tag:      return NSColor.sRGB(0.788, 0.247, 0.196)   // #C93F32
        case .property: return NSColor.sRGB(0.541, 0.392, 0.000)   // #8A6400
        case .constant: return NSColor.sRGB(0.596, 0.408, 0.004)   // #986801
        case .escape:   return NSColor.sRGB(0.004, 0.420, 0.608)   // #016B9B
        }
    }

    /// 代码文件预览的底色 / 正文色（与上面同族，保证 WebView 里也是同一套观感）
    static var background: NSColor {
        isDark() ? NSColor.sRGB(0.157, 0.173, 0.204)               // #282C34
                 : NSColor.sRGB(0.980, 0.980, 0.980)               // #FAFAFA
    }

    static var foreground: NSColor {
        isDark() ? NSColor.sRGB(0.671, 0.698, 0.749)               // #ABB2BF
                 : NSColor.sRGB(0.220, 0.227, 0.259)               // #383A42
    }

}

import SwiftUI
import AppKit
import Combine

/// 主题 —— 晨曦（暖白·琥珀）/ 夜航者（深空·蓝）
enum Theme: String, CaseIterable, Identifiable, Codable {
    case dawn
    case night

    var id: String { rawValue }

    var name: String {
        switch self {
        case .dawn: return _L("晨曦", "Dawn")
        case .night: return _L("夜航者", "Night Voyager")
        }
    }
    var subtitle: String {
        switch self {
        case .dawn: return _L("暖白 · 琥珀", "Warm White · Amber")
        case .night: return _L("深空 · 蓝", "Deep Space · Blue")
        }
    }

    /// macOS 外观：晨曦 = 浅色；夜航者 = 深色
    var colorScheme: ColorScheme {
        switch self {
        case .dawn: return .light
        case .night: return .dark
        }
    }

    /// SwiftUI 侧 accent（工具栏选中态、活动条、行高亮等）
    /// 对比度控制（对深色背景 ≥ 4.5:1）：夜航者取亮蓝 #7fa4ff
    /// 注意：启用插件主题时全局 accent 由 appAppearance 接管（此值仅作回退）。
    var accent: Color {
        switch self {
        case .dawn: return Color(red: 0.737, green: 0.369, blue: 0.243) // #BC5E3E（深压至浅底 ≥4.5:1）
        case .night: return Color(red: 0.50, green: 0.64, blue: 1.00)   // #7FA4FF（深底 ≥6.8:1）
        }
    }

    /// 预览 html 的 data-theme 值
    var dataTheme: String? { rawValue }

    /// 选中态行底色（AppKit 侧；与 accent 同系）
    var rowSelectionColor: Color { accent }
}

/// 当前主题（设置持久化，默认晨曦；过去固定单主题）
var currentTheme: Theme {
    Theme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .dawn
}

// MARK: - 统一主题选项：仅插件主题（内置晨曦/夜航者只做无插件时的内部兜底）

/// 设置页、菜单共用的主题条目。id 只用于选择与持久化，界面不再区分来源层级。
struct ThemeOption: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let swatch: Color?
    let isPlugin: Bool
}

var allThemeOptions: [ThemeOption] {
    PluginManager.shared.allThemes().map {
        ThemeOption(id: "plugin:\($0.id)",
                    name: $0.name,
                    subtitle: $0.desc,
                    swatch: PluginCSS.color(from: $0.swatchHex).map { Color(nsColor: $0) },
                    isPlugin: true)
    }
}

var currentThemeOptionID: String {
    if let plugin = PluginManager.shared.enabledTheme() {
        return "plugin:\(plugin.id)"
    }
    return allThemeOptions.first?.id ?? ""
}

/// 主题目录：插件启停/切换后主动刷新，菜单可在运行中即时增删主题项。
final class ThemeCatalog: ObservableObject {
    @Published private(set) var options: [ThemeOption] = allThemeOptions

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: PluginManager.changedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.options = allThemeOptions
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

// MARK: - 全局外观：内置主题为基底，插件主题（启用时）以 CSS 变量为准
// 插件主题不再是「仅预览面板」：深/浅模式、全局强调色、编辑器底色/正文色、
// 行号色、导出外观全部随启用中的插件主题走（与预览所见完全一致）。

/// 全局外观解析结果（不可变快照；appAppearance 按变更缓存）
struct AppAppearance {
    /// 应用全局深浅（.preferredColorScheme）
    let scheme: ColorScheme
    /// 深色判定（编辑器明暗自适应色、预览 dark 参数、导出等）
    let dark: Bool
    /// 全局强调色（.tint / 选中态 / 行高亮）
    let accent: Color
    /// 编辑器底色（插件主题 --bg；缺省内置）
    let editorBackground: NSColor
    /// 编辑器正文色（插件主题 --text；缺省内置）
    let editorForeground: NSColor
    /// 编辑器插入光标：优先主题 accent；对比不足时回退正文色/黑白
    let caret: NSColor
    /// 编辑器选区底色（accent 半透明）
    let selectionBackground: NSColor
    /// 行号颜色（正文色降透明度，深浅主题都清晰）
    let lineNumber: NSColor
    /// 插件主题窗口底色（--bg）；内置主题为 nil，继续使用系统窗口色
    let windowBackground: NSColor?
    /// 插件主题面板/侧栏底色（--surface）；内置主题为 nil
    let surface: NSColor?
    /// 插件主题界面字体家族（可选）
    let uiFontFamily: String?
    /// 插件主题界面字号（缺省 13）
    let uiFontSize: Double
    /// 插件主题代码字体家族（可选）
    let codeFontFamily: String?
    /// 插件主题标题/展示字体家族（可选）
    let displayFontFamily: String?
    /// 插件主题代码字号（可选；像素字体必须落在设计网格上）
    let codeFontSize: Double?
    /// 插件主题语义图标映射
    let themeIcons: [String: String]
    /// 插件主题彩蛋配置
    let easterEgg: ThemeEasterEgg?
    /// 插件主题动效配置
    let motion: ThemeMotion?
    /// 编辑器语法色：主题声明的 --md-* 变量（键含前导 --，如 "--md-h1"）；无主题时为空
    let mdSyntax: [String: NSColor]
    /// 主题自带透明度（0 = 不透明）
    let glass: Double
    /// 启用中的插件主题 id（视图重建 token；无 = nil）
    let pluginThemeID: String?

    /// 取编辑器语法色（缺省 nil → 编辑器回落到内置配色）
    func mdColor(_ key: String) -> NSColor? { mdSyntax[key] }

    /// 无插件主题时的内置编辑器颜色（与 preview.css dawn/night 对齐，消除拼接缝）
    static func builtinEditorBackground(dark: Bool) -> NSColor {
        dark ? NSColor(calibratedRed: 0.067, green: 0.075, blue: 0.102, alpha: 1) // #11131A
             : NSColor(calibratedRed: 0.980, green: 0.973, blue: 0.961, alpha: 1) // #FAF8F5
    }
    static func builtinEditorForeground(dark: Bool) -> NSColor {
        dark ? NSColor.sRGB(0.93, 0.94, 0.96)   // 近白（深底 ≥14:1）
             : NSColor.sRGB(0.13, 0.14, 0.17)   // 近黑（浅底 ≥14:1）
    }

    /// WCAG 对比度（1…21）
    static func contrastRatio(_ a: NSColor, _ b: NSColor) -> Double {
        let l1 = PluginCSS.luminance(a)
        let l2 = PluginCSS.luminance(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// 光标色：主题 accent 对编辑器底色的对比度 ≥3:1 时直接用；
    /// 否则回退正文色；极端情况下按底色明暗取黑/白，避免“光标消失”。
    static func caretColor(accent: NSColor, background: NSColor, text: NSColor) -> NSColor {
        if contrastRatio(accent, background) >= 3.0 { return accent }
        if contrastRatio(text, background) >= 4.5 { return text }
        return PluginCSS.luminance(background) < 0.35 ? .white : .black
    }

    /// 选区底色：accent 太接近底色时退回系统标签色，保证选区仍可见。
    static func selectionColor(accent: NSColor, background: NSColor) -> NSColor {
        let base = contrastRatio(accent, background) >= 1.35 ? accent : NSColor.labelColor
        return base.withAlphaComponent(0.26)
    }
}

/// 全局外观（缓存键 = 内置主题 + 插件主题 id + css mtime；解析仅发生在变化时）
var appAppearance: AppAppearance {
    let base = currentTheme
    let plugin = PluginManager.shared.enabledTheme()
    var pluginKey = "-"
    if let p = plugin {
        let mtime = (try? FileManager.default.attributesOfItem(atPath: p.cssFile)[.modificationDate] as? Date)?.timeIntervalSince1970
            ?? -1
        pluginKey = "\(p.id)|\(mtime)|\(p.uiFont?.family ?? "-")|\(p.codeFont?.family ?? "-")|\(p.icons.count)"
    }
    let key = "\(base.rawValue)|\(pluginKey)"
    if key == appearanceCacheKey, let cached = appearanceCacheValue { return cached }
    let value = resolveAppAppearance(base: base, plugin: plugin)
    appearanceCacheKey = key
    appearanceCacheValue = value
    return value
}

private var appearanceCacheKey = ""
private var appearanceCacheValue: AppAppearance?

/// 解析链：内置基底 →（插件主题）CSS 简化级联取 --bg/--text/--accent →
/// 按 --bg 亮度裁决全局深/浅（若插件主题在浅色门控下仍是暗底 → 翻转门控重算一遍，
/// 收敛结果与预览页实际渲染一致 —— 这正是「插件主题作用于全局」的判定标准）
private func resolveAppAppearance(base: Theme, plugin: PluginTheme?) -> AppAppearance {
    var vars: [String: String] = [:]
    var bg: NSColor?
    var text: NSColor?
    var accent: NSColor?
    if let plugin, let css = try? String(contentsOfFile: plugin.cssFile, encoding: .utf8), !css.isEmpty {
        let layers = PluginCSS.parse(css)
        let baseDark = base == .night
        vars = PluginCSS.vars(layers, variant: base.rawValue, dark: baseDark)
        bg = PluginCSS.color(from: vars["--bg"])
        if let bg, (PluginCSS.luminance(bg) < 0.35) != baseDark {
            // 插件主题强制反转深浅（如 Dracula 在晨曦下仍为暗底）→ 翻转媒体门控重算
            vars = PluginCSS.vars(layers, variant: base.rawValue, dark: !baseDark)
        }
        text = PluginCSS.color(from: vars["--text"])
        if let a = PluginCSS.color(from: vars["--accent"]) {
            accent = a
        } else if let swatch = PluginCSS.color(from: plugin.swatchHex) {
            accent = swatch
        }
    }
    let dark = bg.map { PluginCSS.luminance($0) < 0.35 } ?? (base == .night)
    let editorBackground = bg ?? AppAppearance.builtinEditorBackground(dark: dark)
    let editorForeground = text ?? AppAppearance.builtinEditorForeground(dark: dark)
    let resolvedAccent = accent ?? NSColor(base.accent)
    return AppAppearance(
        scheme: dark ? .dark : .light,
        dark: dark,
        accent: Color(nsColor: resolvedAccent),
        editorBackground: editorBackground,
        editorForeground: editorForeground,
        caret: AppAppearance.caretColor(accent: resolvedAccent,
                                        background: editorBackground,
                                        text: editorForeground),
        selectionBackground: AppAppearance.selectionColor(accent: resolvedAccent,
                                                          background: editorBackground),
        lineNumber: editorForeground.withAlphaComponent(dark ? 0.55 : 0.45),
        windowBackground: plugin == nil ? nil : (bg ?? editorBackground),
        surface: plugin == nil ? nil : PluginCSS.color(from: vars["--surface"]),
        uiFontFamily: plugin?.uiFont?.family,
        uiFontSize: plugin?.uiFont?.size ?? 13,
        codeFontFamily: plugin?.codeFont?.family,
        displayFontFamily: plugin?.displayFont?.family,
        codeFontSize: plugin?.codeFont?.size,
        themeIcons: plugin?.icons ?? [:],
        easterEgg: plugin?.easterEgg,
        motion: plugin?.motion,
        mdSyntax: vars.reduce(into: [String: NSColor]()) { acc, item in
            guard item.key.hasPrefix("--md-"), let color = PluginCSS.color(from: item.value) else { return }
            acc[item.key] = color
        },
        glass: plugin?.glass ?? 0,
        pluginThemeID: plugin?.id
    )
}

/// 主题语义图标 → NSImage（未声明/文件损坏时返回 nil，由调用方回退 SF Symbol）。
func themeIconImage(_ name: String) -> NSImage? {
    guard let path = appAppearance.themeIcons[name] else { return nil }
    return NSImage(contentsOfFile: path)
}

// MARK: - 插件主题 CSS 简化级联

/// 主题包实际使用的全部结构形态：:root / :root[data-theme="dawn"]/“night” 数据主题选择器、
/// @media (prefers-color-scheme: light|dark) 媒体门控。按源顺序分层，解析变量时后层覆盖前层
/// （与浏览器级联一致）；只为取配色变量（--bg/--text/--accent…），不做完整 CSS 解析。
enum PluginCSS {
    struct Layer {
        /// 适用 data-theme 变体（dawn/night）；空 = 通用
        let variants: Set<String>
        /// prefers-color-scheme 门控（true=dark）；nil = 不限
        let darkGate: Bool?
        var vars: [String: String]
    }

    static func parse(_ css: String) -> [Layer] {
        parseScope(css, gate: nil)
    }

    /// 取某变体 × 某深浅下的有效变量表（后层覆盖前层）
    static func vars(_ layers: [Layer], variant: String, dark: Bool) -> [String: String] {
        var out: [String: String] = [:]
        for l in layers {
            if !l.variants.isEmpty, !l.variants.contains(variant) { continue }
            if let g = l.darkGate, g != dark { continue }
            out.merge(l.vars) { _, new in new }
        }
        return out
    }

    // MARK: 语法解析

    private static func parseScope(_ css: String, gate: Bool?) -> [Layer] {
        var layers: [Layer] = []
        let chars = Array(css)
        let n = chars.count
        var i = 0
        var selector = ""
        while i < n {
            // 注释：整段跳过（避免注释内容混入选择器/声明体）
            if chars[i] == "/", i + 1 < n, chars[i + 1] == "*" {
                var j = i + 2
                while j + 1 < n, !(chars[j] == "*" && chars[j + 1] == "/") { j += 1 }
                i = min(n, j + 2)
                selector = ""
                continue
            }
            // @media：门控解析整块（块内可能再嵌 :root[data-theme=…] 选择器）
            if chars[i] == "@" {
                // 条件 + 左花括号（主题包内为单行，跨行亦可扫描；遇 ; / 注释则放弃）
                var lb: Int?
                var j = i
                while j < n, chars[j] != ";", !(chars[j] == "/" && j + 1 < n && chars[j + 1] == "*") {
                    if chars[j] == "{" { lb = j; break }
                    j += 1
                }
                if let lb {
                    let condition = String(chars[i..<lb]).lowercased()
                    var gate2 = gate
                    if condition.contains("prefers-color-scheme") {
                        if condition.contains("dark") { gate2 = true }
                        else if condition.contains("light") { gate2 = false }
                    }
                    if let (body, next) = scanBlock(chars, open: lb) {
                        layers += parseScope(body, gate: gate2)
                        i = next
                        selector = ""
                        continue
                    }
                }
                // @media 无配套块（不应出现）→ 跳过到行尾，避免死循环
                while i < n, chars[i] != "\n" { i += 1 }
                selector = ""
                continue
            }
            if chars[i] == "{" {
                if let (body, next) = scanBlock(chars, open: i) {
                    let sel = selector.trimmingCharacters(in: .whitespacesAndNewlines)
                    let decls = declarations(in: body)
                    if !decls.isEmpty {
                        layers.append(Layer(variants: selectorVariants(sel), darkGate: gate, vars: decls))
                    }
                    i = next
                } else {
                    break
                }
                selector = ""
                continue
            }
            selector.append(chars[i])
            i += 1
        }
        return layers
    }

    /// 从 open（"{"）扫到匹配的（"}"）；返回 (块体完整文本, 闭括号后的索引)
    private static func scanBlock(_ chars: [Character], open: Int) -> (String, Int)? {
        let n = chars.count
        var depth = 1
        var j = open + 1
        while j < n, depth > 0 {
            if chars[j] == "{" { depth += 1 }
            else if chars[j] == "}" { depth -= 1 }
            j += 1
        }
        guard depth == 0 else { return nil }
        let close = j - 1
        return (String(chars[(open + 1)..<close]), j)
    }

    /// data-theme 选择器 → 适用变体；无 data-theme（:root 本体）→ 通用
    private static func selectorVariants(_ sel: String) -> Set<String> {
        var variants: Set<String> = []
        if sel.contains("data-theme=\"dawn\"") { variants.insert("dawn") }
        if sel.contains("data-theme=\"night\"") { variants.insert("night") }
        return variants
    }

    private static func declarations(in body: String) -> [String: String] {
        let regex = declarationRegex
        guard let r = regex else { return [:] }
        let ns = body as NSString
        var out: [String: String] = [:]
        r.enumerateMatches(in: body, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            let name = ns.substring(with: m.range(at: 1))
            let value = ns.substring(with: m.range(at: 2))
            out[name] = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return out
    }

    /// --name: value;（value 允许 #hex 与 rgb()/rgba() —— 主题包变量值仅有这两种形态）
    private static let declarationRegex = try? NSRegularExpression(
        pattern: #"(--[a-zA-Z0-9-]+)\s*:\s*([^;{}]+?)\s*;"#)

    // MARK: 颜色值解析

    /// #RGB / #RRGGBB（含 4/8 位带 alpha）与 rgb()/rgba() → NSColor；失败 nil
    static func color(from value: String?) -> NSColor? {
        guard let v = value?.trimmingCharacters(in: .whitespaces).lowercased(), !v.isEmpty else { return nil }
        if v.hasPrefix("#") {
            return hexColor(String(v.dropFirst()))
        }
        if v.hasPrefix("rgb") {
            // 剥掉函数名与括号（rgb(...) / rgba(...) 两种长度）
            let stripped = String(v.dropFirst(v.hasPrefix("rgba") ? 5 : 4).dropLast(1))
            let parts = stripped.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count >= 3 else { return nil }
            let scale: Double = (parts[0] > 1 || parts[1] > 1 || parts[2] > 1) ? 255 : 1
            let alpha: Double = parts.count > 3 ? parts[3] : 1
            return NSColor(srgbRed: parts[0] / scale, green: parts[1] / scale,
                           blue: parts[2] / scale, alpha: max(0, min(1, alpha)))
        }
        return nil
    }

    private static func hexColor(_ h: String) -> NSColor? {
        guard h.count == 3 || h.count == 4 || h.count == 6 || h.count == 8 else { return nil }
        let chars = Array(h)
        func nib(_ c: Character) -> Double? {
            guard let v = c.hexDigitValue else { return nil }
            return Double(v)
        }
        func pair(_ c1: Character, _ c2: Character) -> Double? {
            guard let a = nib(c1), let b = nib(c2) else { return nil }
            return (a * 16 + b) / 255
        }
        let r: Double, g: Double, b: Double
        let alpha: Double
        if h.count == 3 || h.count == 4 {
            guard let r0 = nib(chars[0]), let g0 = nib(chars[1]), let b0 = nib(chars[2]) else { return nil }
            r = r0 / 15; g = g0 / 15; b = b0 / 15
            alpha = h.count == 4 ? (nib(chars[3]) ?? 15) / 15 : 1
        } else {
            guard let rp = pair(chars[0], chars[1]), let gp = pair(chars[2], chars[3]),
                  let bp = pair(chars[4], chars[5]) else { return nil }
            r = rp; g = gp; b = bp
            alpha = h.count == 8 ? (pair(chars[6], chars[7]) ?? 1) : 1
        }
        return NSColor(srgbRed: r, green: g, blue: b, alpha: alpha)
    }

    /// WCAG 相对亮度（0=黑 → 1=白）
    static func luminance(_ color: NSColor) -> Double {
        let c = color.usingColorSpace(.sRGB) ?? color
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
    }
}

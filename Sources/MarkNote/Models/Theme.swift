import SwiftUI

/// 主题 —— 配套 app 外观 + 预览配色。
/// 预览侧通过 html data-theme + preview.css 变量组实现；系统主题走 prefers-color-scheme。
enum Theme: String, CaseIterable, Identifiable, Codable {
    case system
    case night   // 夜航者 —— start 暗色系：深蓝黑底 + 粉 accent
    case dawn    // 晨曦 —— start 亮色系：暖白底 + 琥珀 accent
    case forest  // 墨林 —— 深墨绿底 + 琥珀绿 accent
    case violet  // 紫鸢 —— 深紫底 + 紫罗兰 accent

    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: return "跟随系统"
        case .night: return "夜航者"
        case .dawn: return "晨曦"
        case .forest: return "墨林"
        case .violet: return "紫鸢"
        }
    }

    var subtitle: String {
        switch self {
        case .system: return "深浅与系统外观一致"
        case .night: return "深蓝黑 · 粉"
        case .dawn: return "暖白 · 琥珀"
        case .forest: return "墨绿 · 苔青"
        case .violet: return "深紫 · 鸢尾"
        }
    }

    var previewDescription: String { "\(name) · \(subtitle)" }

    /// 强制 macOS 外观；system = 跟随系统
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .night, .forest, .violet: return .dark
        case .dawn: return .light
        }
    }

    /// SwiftUI 侧 accent（工具栏选中态等）
    var accent: Color {
        switch self {
        case .system: return .accentColor
        case .night: return Color(red: 1.0, green: 0.42, blue: 0.62)   // #ff6b9d
        case .dawn: return Color(red: 0.75, green: 0.41, blue: 0.28)   // #c06848
        case .forest: return Color(red: 0.45, green: 0.87, blue: 0.62) // #73de9e
        case .violet: return Color(red: 0.72, green: 0.60, blue: 1.0)  // #b799ff
        }
    }

    /// 预览 html 的 data-theme 值；system 不设 → media query 决定
    var dataTheme: String? { self == .system ? nil : rawValue }
}

/// 启动时从 UserDefaults 恢复
var currentTheme: Theme {
    get {
        Theme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .system
    }
    set {
        UserDefaults.standard.set(newValue.rawValue, forKey: "theme")
    }
}

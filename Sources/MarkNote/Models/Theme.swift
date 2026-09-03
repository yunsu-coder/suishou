import SwiftUI

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

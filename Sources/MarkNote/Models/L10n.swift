import Foundation
import SwiftUI

/// 轻量国际化：中文/英文双文案（代码内维护，后续可迁移 .strings）。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case zh = "zh"
    case en = "en"
    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: return _L("跟随系统（中文/English 自动）", "Follow System")
        case .zh: return "中文"
        case .en: return "English"
        }
    }

    /// 当前生效语言（"zh" / "en"）
    static var effective: String {
        switch UserDefaults.standard.string(forKey: "appLanguage") ?? "system" {
        case "zh": return "zh"
        case "en": return "en"
        default:
            let first = Locale.preferredLanguages.first ?? "en"
            return first.hasPrefix("zh") ? "zh" : "en"
        }
    }

    static var isEnglish: Bool { effective == "en" }
}

/// 纯字符串取用
func _L(_ zh: String, _ en: String) -> String {
    AppLanguage.effective == "zh" ? zh : en
}

/// SwiftUI Text/Label 取用
func _LL(_ zh: String, _ en: String) -> LocalizedStringKey {
    LocalizedStringKey(_L(zh, en))
}

/// 格式化文案占位
func _LF(_ zh: String, _ en: String, _ args: CVarArg...) -> String {
    let tpl = _L(zh, en)
    return String(format: tpl, arguments: args)
}

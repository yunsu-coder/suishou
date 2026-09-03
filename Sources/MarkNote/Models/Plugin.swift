import Foundation
import SwiftUI

/// 插件系统（P1+P2）：纯声明式包（无代码执行，零崩溃风险）。
/// 目录：工作台 .plugins/<id>/ 与 全局 ~/Library/Application Support/MarkNote/plugins/<id>/
/// 包结构：manifest.json（schema 见 PluginManifest）+ 按 kind 的数据文件。

enum PluginKind: String, Codable, CaseIterable {
    case experts, theme, filetypes, snippets, render, commands

    var displayName: String {
        switch self {
        case .experts: return _L("AI 专家", "AI Expert")
        case .theme: return _L("主题", "Theme")
        case .filetypes: return _L("文件类型", "File Type")
        case .snippets: return _L("插入模板", "Snippet")
        case .render: return _L("渲染扩展", "Render Extension")
        case .commands: return _L("命令", "Command")
        }
    }
}

struct PluginManifest: Codable {
    let id: String
    let name: String
    let version: String
    let kind: PluginKind
    let main: String
    /// 一句话简介（市场列表）
    var desc: String?
    /// 基础功能清单（详情页 feature bullets）
    var features: [String]?
    var author: String?
    var minAppVersion: String?
    /// 标志性图标：SF Symbol 名（如 "sparkles"）；包内 icon.png 存在时优先使用图片
    var icon: String?
    /// 详情 README（可选，包内文件）
    var readme: String?
    /// 双语：英文名/简介/功能清单（缺省回退中文；外国人市场展示用）
    var nameEn: String?
    var descEn: String?
    var featuresEn: [String]?
}

/// 扫描到的插件包（启用/禁用持久化在 UserDefaults["pluginEnabled.<id>"]）
struct PluginPackage: Identifiable {
    let id: String
    let name: String
    let version: String
    let kind: PluginKind
    let desc: String
    let features: [String]
    let author: String
    let minAppVersion: String
    let iconSymbol: String
    let dir: URL
    let isGlobal: Bool
    var enabled: Bool
    /// 双语数据（英文缺失时回退中文，兼容旧包）
    var nameEn: String?
    var descEn: String?
    var featuresEn: [String]?

    /// 当前语言下的展示名/简介/功能清单
    var displayName: String { AppLanguage.isEnglish ? (nameEn ?? name) : name }
    var displayDesc: String { AppLanguage.isEnglish ? (descEn ?? desc) : desc }
    var displayFeatures: [String] {
        if AppLanguage.isEnglish { return featuresEn ?? features }
        return features
    }

    /// 图标图片（包内 icon.png；缺失用 SF Symbol）
    var iconURL: URL? {
        let f = dir.appendingPathComponent("icon.png")
        return FileManager.default.fileExists(atPath: f.path) ? f : nil
    }

    /// 包内某 kind 内容文件（experts.json / theme.css / filetypes.json / snippets.json）
    var mainURL: URL { dir.appendingPathComponent(mainFile) }
    var mainFile: String = "main.json"

    static func placeholder(id: String, name: String, version: String, kind: PluginKind,
                            desc: String, features: [String], author: String, minAppVersion: String,
                            iconSymbol: String, dir: URL, isGlobal: Bool, enabled: Bool,
                            nameEn: String? = nil, descEn: String? = nil, featuresEn: [String]? = nil) -> PluginPackage {
        var p = PluginPackage(id: id, name: name, version: version, kind: kind,
                              desc: desc, features: features, author: author,
                              minAppVersion: minAppVersion, iconSymbol: iconSymbol,
                              dir: dir, isGlobal: isGlobal, enabled: enabled,
                              nameEn: nameEn, descEn: descEn, featuresEn: featuresEn)
        p.mainFile = "main.json"
        return p
    }

    /// 各类默认图标（manifest 未指定时）
    static func defaultIcon(for kind: PluginKind) -> String {
        switch kind {
        case .experts: return "person.crop.circle"
        case .theme: return "paintpalette"
        case .filetypes: return "doc.text"
        case .snippets: return "text.insert"
        case .render: return "wand.and.stars"
        case .commands: return "command"
        }
    }

    /// 各类主题色（市场图标底）
    static func tint(for kind: PluginKind) -> Color {
        switch kind {
        case .experts: return Color(red: 0.90, green: 0.45, blue: 0.60)
        case .theme: return Color(red: 0.62, green: 0.50, blue: 0.95)
        case .filetypes: return Color(red: 0.20, green: 0.62, blue: 0.60)
        case .snippets: return Color(red: 0.95, green: 0.62, blue: 0.25)
        case .render: return Color(red: 0.25, green: 0.55, blue: 0.95)
        case .commands: return Color(red: 0.55, green: 0.57, blue: 0.62)
        }
    }
}

struct FileTypeOverride: Codable {
    var icon: String?
    var comment: String?
    var indent: Int?
}

struct PluginSnippet: Identifiable {
    let id: String
    let name: String
    let language: String   // "markdown" / "code" / "all"
    let text: String
    /// 英文版模板正文（缺省回退 text）
    var textEn: String?

    /// 当前语言下的模板正文
    var displayText: String { AppLanguage.isEnglish ? (textEn ?? text) : text }
}

struct PluginTheme: Identifiable {
    let id: String
    let name: String
    let desc: String
    let cssFile: String
    let swatchHex: String
}



/// 渲染插件：用户 JS 包（P3）—— 在预览 Web 沙箱内注册 markdown-it 插件/钩子
struct RenderPlugin: Identifiable {
    let id: String
    let js: String
}

/// 命令插件（P4）：命令面板注册；action 为宿主白名单动作
struct PluginCommand: Identifiable {
    let id: String
    let name: String
    let icon: String
    let category: String
    let actionID: String
}

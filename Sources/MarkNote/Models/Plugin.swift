import Foundation
import SwiftUI

/// 插件系统（P1+P2）：纯声明式包（无代码执行，零崩溃风险）。
/// 目录：工作台 .plugins/<id>/ 与 全局 ~/Library/Application Support/MarkNote/plugins/<id>/
/// 包结构：manifest.json（schema 见 PluginManifest）+ 按 kind 的数据文件。

enum PluginKind: String, Codable, CaseIterable {
    case experts, theme, filetypes, snippets, render, commands, views

    var displayName: String {
        switch self {
        case .experts: return _L("AI 专家", "AI Expert")
        case .theme: return _L("主题", "Theme")
        case .filetypes: return _L("文件类型", "File Type")
        case .snippets: return _L("插入模板", "Snippet")
        case .render: return _L("渲染扩展", "Render Extension")
        case .commands: return _L("命令", "Command")
        case .views: return _L("视图", "View")
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
        case .views: return "rectangle.grid.2x2"
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
        case .views: return Color(red: 0.20, green: 0.66, blue: 0.52)
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
    /// 插件包根目录（字体/图标资源相对路径解析基准）
    let dir: String
    /// 主题声明的界面字体（可选）
    let uiFont: ThemeFontAsset?
    /// 主题声明的代码字体（可选）
    let codeFont: ThemeFontAsset?
    /// 主题声明的标题/展示字体（可选）
    let displayFont: ThemeFontAsset?
    /// 语义图标映射（如 "folder" / "sparkles" → 包内绝对路径）
    let icons: [String: String]
    /// 主题彩蛋（可选）
    let easterEgg: ThemeEasterEgg?
    /// 主题动效/特效配置（可选）
    let motion: ThemeMotion?
    /// 主题自带透明度（0 = 不透明）
    let glass: Double
}

/// 主题字体资源：file 为包内相对路径，family 为 CoreText 家族名。
struct ThemeFontAsset: Equatable {
    let file: String
    let family: String
    let size: Double?
}

/// 主题彩蛋：trigger 目前支持 "icon-click"；symbols 为飘落符号。
struct ThemeEasterEgg: Equatable {
    let trigger: String
    let clicks: Int
    let symbols: [String]
    let message: String?
}

/// 主题动效：全部为轻量 SwiftUI 动画，默认尊重系统“减少动态效果”。
struct ThemeMotion: Equatable {
    let ambientBubbles: Bool
    let ambientPixels: Bool
    let ambientInk: Bool
    /// 雾青主题氛围：极淡的花粉光尘缓慢飘落
    let ambientPollen: Bool
    let scanlines: Bool
    let iconBounce: Bool
    let tabSpring: Bool
    /// 单次动画时长（秒，0.12…0.60）
    let duration: Double
    let respectReduceMotion: Bool
}

/// theme.json 中的单条主题声明（含可选字体 / 图标 / 彩蛋 / 动效资源）。
struct ThemeSpec: Codable {
    let id: String
    let name: String
    let desc: String?
    /// 人工审核标记：true 才允许进入主题列表
    let reviewed: Bool?
    /// 人工审核时锁定的内容哈希：任何资源变化都会失效，退回待审核
    let reviewedHash: String?
    /// 质量审计版本：1 = 基础图标规则；2 = 文件格式/文件夹/颜色层级规则
    let auditVersion: Int?
    let cssFile: String
    let swatchHex: String?
    let uiFont: FontSpec?
    let codeFont: FontSpec?
    let displayFont: FontSpec?
    let icons: [String: String]?
    let easterEgg: EasterEggSpec?
    let motion: MotionSpec?
    /// 主题自带透明度（0 = 不透明，0…1）；缺省 0。
    let glass: Double?

    struct FontSpec: Codable {
        let file: String
        let family: String
        let size: Double?
    }

    struct EasterEggSpec: Codable {
        let trigger: String?
        let clicks: Int?
        let symbols: [String]?
        let message: String?
    }

    struct MotionSpec: Codable {
        let ambientBubbles: Bool?
        let ambientPixels: Bool?
        let ambientInk: Bool?
        let ambientPollen: Bool?
        let scanlines: Bool?
        let iconBounce: Bool?
        let tabSpring: Bool?
        let durationMs: Int?
        let respectReduceMotion: Bool?
    }
}



/// 渲染插件：用户 JS 包（P3）—— 在预览 Web 沙箱内注册 markdown-it 插件/钩子
struct RenderPlugin: Identifiable {
    let id: String
    let js: String
}


// MARK: - 视图插件（声明式：插件只声明配置，界面由 app 用主题变量渲染）

/// 视图类型：app 内置渲染器，插件不提供代码。
enum PluginViewType: String, Codable, CaseIterable {
    case noteCards
    case assetGrid
    case collector
    case flowchart

    var displayName: String {
        switch self {
        case .noteCards: return _L("卡片墙", "Note Cards")
        case .assetGrid: return _L("素材网格", "Asset Grid")
        case .collector: return _L("素材采集", "Asset Collector")
        case .flowchart: return _L("流程图", "Flowchart")
        }
    }
}

/// 作用域：workspace = 只读当前工作台；global = 本机 UI 偏好（不读笔记内容）
enum PluginViewScope: String, Codable {
    case workspace, global
}

/// 放置位置：main = 占主区域（可切换）；panel = 侧边面板
enum PluginViewPlacement: String, Codable {
    case main, panel
}

/// 视图选项（受控字段；未知键会被忽略，避免插件塞私有配置）
struct PluginViewOptions: Codable, Equatable {
    /// day | folder | none
    var groupBy: String?
    /// 卡片预览行数（3 / 6 / 10）
    var previewLines: Int?
    var showProgress: Bool?
    /// open | star | archive
    var actions: [String]?
    /// assetGrid：扫描哪些目录（默认 source）
    var dirs: [String]?
    var showRefCount: Bool?
    /// assetGrid：是否允许「从其他工作台导入」
    var allowImport: Bool?

    static let `default` = PluginViewOptions()
}

/// views.json 中的单条视图声明。
struct ViewSpec: Codable {
    let id: String
    let name: String
    let nameEn: String?
    let type: String
    let scope: String
    let placement: String
    let options: PluginViewOptions?
}

/// 注册后的视图（含来源包目录）。
struct PluginView: Identifiable {
    let id: String
    let name: String
    let type: PluginViewType
    let scope: PluginViewScope
    let placement: PluginViewPlacement
    let options: PluginViewOptions
    let dir: String

    var previewLines: Int { max(1, min(20, options.previewLines ?? 6)) }
}

/// 命令插件（P4）：命令面板注册；action 为宿主白名单动作
struct PluginCommand: Identifiable {
    let id: String
    let name: String
    let icon: String
    let category: String
    let actionID: String
}

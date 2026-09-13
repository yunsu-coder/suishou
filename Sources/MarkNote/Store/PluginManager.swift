import Foundation
import AppKit

/// 插件管理器：扫描（工作台 .plugins/ + 全局目录）→ 校验 manifest → 按启用集合并进注册表。
/// 全部数据驱动，不执行任何代码；坏包跳过。线程安全（锁）。
final class PluginManager {
    static let shared = PluginManager()
    static let changedNotification = Notification.Name("pluginsChanged")

    enum ToggleOutcome {
        case ok
        case blockedLastTheme
    }

    private let lock = NSLock()
    private var packagesByID: [String: PluginPackage] = [:]
    private(set) var data = PluginData()

    func scan(workspaceDir: URL?) {
        lock.lock()
        var found: [String: PluginPackage] = [:]
        var roots: [(URL, Bool)] = [
            (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("MarkNote/plugins", isDirectory: true), true),
        ]
        if let ws = workspaceDir {
            roots.append((ws.appendingPathComponent(".plugins", isDirectory: true), false))
        }
        for (root, isGlobal) in roots {
            guard let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for dir in entries where dir.hasDirectoryPath {
                if let pkg = loadPackage(at: dir, isGlobal: isGlobal) {
                    found[pkg.id] = pkg
                }
            }
        }
        packagesByID = found
        rebuildData()
        lock.unlock()
        // 通知必须在释放锁之后发送：观察者会回调 allThemes()/allPackages() 再次取锁。
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
    }

    private func loadPackage(at dir: URL, isGlobal: Bool) -> PluginPackage? {
        let manifestURL = dir.appendingPathComponent("manifest.json")
        guard let raw = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PluginManifest.self, from: raw) else { return nil }
        guard !manifest.id.isEmpty, !manifest.name.isEmpty else { return nil }
        let enabled = UserDefaults.standard.bool(forKey: "pluginEnabled.\(manifest.id)")
        var pkg = PluginPackage.placeholder(id: manifest.id, name: manifest.name,
                                            version: manifest.version, kind: manifest.kind,
                                            desc: manifest.desc ?? "",
                                            features: manifest.features ?? [],
                                            author: manifest.author ?? "",
                                            minAppVersion: manifest.minAppVersion ?? "",
                                            iconSymbol: manifest.icon ?? PluginPackage.defaultIcon(for: manifest.kind),
                                            dir: dir,
                                            isGlobal: isGlobal, enabled: enabled,
                                            nameEn: manifest.nameEn, descEn: manifest.descEn,
                                            featuresEn: manifest.featuresEn)
        pkg.mainFile = manifest.main
        return pkg
    }

    private func rebuildData() {
        ensureThemeFallbackEnabled()
        var d = PluginData()
        for pkg in packagesByID.values.sorted(by: { $0.id < $1.id }) where pkg.enabled {
            apply(pkg, into: &d)
        }
        // 用户可见主题只来自插件：当前选中缺失/失效时自动落到第一个合格主题。
        if !d.themes.isEmpty {
            let current = UserDefaults.standard.string(forKey: "pluginThemeID") ?? ""
            if !d.themes.contains(where: { $0.id == current }) {
                UserDefaults.standard.set(d.themes[0].id, forKey: "pluginThemeID")
            }
        }
        data = d
    }

    /// 至少启用一个主题包：全部关闭时自动启用兜底（墨纸优先），绝不回退到内置主题。
    private func ensureThemeFallbackEnabled() {
        let themes = packagesByID.values.filter { $0.kind == .theme }
        guard !themes.isEmpty, !themes.contains(where: { $0.enabled }) else { return }
        let preferred = ["theme-sumi-paper", "theme-bubble-pop"]
        let chosen = preferred.compactMap { id in themes.first { $0.id == id } }.first
            ?? themes.sorted { $0.id < $1.id }.first
        guard let chosen else { return }
        packagesByID[chosen.id]?.enabled = true
        UserDefaults.standard.set(true, forKey: "pluginEnabled.\(chosen.id)")
    }

    private func apply(_ pkg: PluginPackage, into d: inout PluginData) {
        switch pkg.kind {
        case .experts:
            guard let items = try? JSONDecoder().decode([ExpertSpec].self, from: Data(contentsOf: pkg.mainURL)) else { return }
            d.experts.append(contentsOf: items.map {
                let e = $0.toExpert()
                return AIExpert(id: e.id, name: e.name, icon: e.icon,
                                desc: Self.normalizeText(e.desc),
                                system: Self.normalizeText(e.system))
            })
        case .filetypes:
            guard let items = try? JSONDecoder().decode([String: FileTypeOverride].self, from: Data(contentsOf: pkg.mainURL)) else { return }
            for (ext, o) in items { d.fileOverrides[ext.lowercased()] = o }
        case .snippets:
            guard let items = try? JSONDecoder().decode([SnippetSpec].self, from: Data(contentsOf: pkg.mainURL)) else { return }
            d.snippets.append(contentsOf: items.map {
                PluginSnippet(id: "sn-\(pkg.id)-\($0.id ?? UUID().uuidString)",
                              name: $0.name, language: $0.language ?? "all",
                              text: Self.normalizeText($0.text),
                              textEn: $0.textEn.map { Self.normalizeText($0) })
            })
        case .theme:
            guard let items = try? JSONDecoder().decode([ThemeSpec].self, from: Data(contentsOf: pkg.mainURL)) else { return }
            for t in items {
                func asset(_ rel: String) -> String {
                    pkg.dir.appendingPathComponent(rel).path
                }
                let uiFont = t.uiFont.map {
                    ThemeFontAsset(file: asset($0.file), family: $0.family, size: $0.size)
                }
                let codeFont = t.codeFont.map {
                    ThemeFontAsset(file: asset($0.file), family: $0.family, size: $0.size)
                }
                let displayFont = t.displayFont.map {
                    ThemeFontAsset(file: asset($0.file), family: $0.family, size: $0.size)
                }
                let icons = (t.icons ?? [:]).mapValues(asset)
                let egg = t.easterEgg.map {
                    ThemeEasterEgg(trigger: $0.trigger ?? "icon-click",
                                   clicks: max(1, $0.clicks ?? 5),
                                   symbols: ($0.symbols?.isEmpty == false) ? $0.symbols! : ["✨"],
                                   message: $0.message)
                }
                let motion = t.motion.map {
                    ThemeMotion(
                        ambientBubbles: $0.ambientBubbles ?? false,
                        ambientPixels: $0.ambientPixels ?? false,
                        ambientInk: $0.ambientInk ?? false,
                        ambientPollen: $0.ambientPollen ?? false,
                        scanlines: $0.scanlines ?? false,
                        iconBounce: $0.iconBounce ?? false,
                        tabSpring: $0.tabSpring ?? false,
                        duration: Double(max(120, min(600, $0.durationMs ?? 280))) / 1000,
                        respectReduceMotion: $0.respectReduceMotion ?? true
                    )
                }
                let issues = ThemeQuality.audit(t, packageDir: pkg.dir, mainFileName: pkg.mainFile)
                guard issues.isEmpty else {
                    d.themeIssues[pkg.id, default: []].append(contentsOf: issues.map { "\(t.name)：\($0)" })
                    continue
                }
                d.themes.append(PluginTheme(id: "plugin-\(pkg.id)-\(t.id)", name: t.name,
                                            desc: t.desc ?? "",
                                            cssFile: pkg.dir.appendingPathComponent(t.cssFile).path,
                                            swatchHex: t.swatchHex ?? "#7c9eff",
                                            dir: pkg.dir.path,
                                            uiFont: uiFont,
                                            codeFont: codeFont,
                                            displayFont: displayFont,
                                            icons: icons,
                                            easterEgg: egg,
                                            motion: motion,
                                            glass: max(0, min(1, t.glass ?? 0))))
            }
        case .views:
            guard let items = try? JSONDecoder().decode([ViewSpec].self, from: Data(contentsOf: pkg.mainURL)) else { return }
            for v in items {
                guard !v.id.isEmpty, !v.name.isEmpty else { continue }
                guard let type = PluginViewType(rawValue: v.type) else {
                    d.viewIssues[pkg.id, default: []].append("\(v.name)：未知视图类型 \(v.type)（只支持 noteCards / assetGrid / collector / flowchart）")
                    continue
                }
                guard let scope = PluginViewScope(rawValue: v.scope) else {
                    d.viewIssues[pkg.id, default: []].append("\(v.name)：作用域必须是 workspace 或 global")
                    continue
                }
                guard let placement = PluginViewPlacement(rawValue: v.placement) else {
                    d.viewIssues[pkg.id, default: []].append("\(v.name)：placement 必须是 main、panel 或 sheet")
                    continue
                }
                // 隔离硬门槛：读笔记内容的视图必须是 workspace 作用域
                // 隔离硬门槛：读取当前工作台内容的视图都必须是 workspace
                if (type == .noteCards || type == .assetGrid || type == .collector || type == .flowchart),
                   scope != .workspace {
                    let why = type == .noteCards ? "卡片墙读取笔记内容"
                        : (type == .assetGrid ? "素材网格读取工作台资源"
                           : (type == .collector ? "素材采集写入当前工作台的素材库"
                              : "流程图读写当前工作台的 source/flowchart"))
                    d.viewIssues[pkg.id, default: []].append("\(v.name)：\(why)，作用域必须是 workspace")
                    continue
                }
                // 流程图是「大画布」：sheet（弹窗大窗口）或 main（旧主区域声明）都行；
                // 面板形态没有意义（窄侧栏画不了图，避免装出看不见的插件）
                if type == .flowchart, placement == .panel {
                    d.viewIssues[pkg.id, default: []].append("\(v.name)：流程图必须 placement = sheet（或旧声明 main）")
                    continue
                }
                d.views.append(PluginView(id: "view-\(pkg.id)-\(v.id)", name: v.name,
                                          type: type, scope: scope, placement: placement,
                                          options: v.options ?? .default, dir: pkg.dir.path))
            }
        case .render:
            guard let js = try? String(contentsOf: pkg.mainURL, encoding: .utf8), !js.isEmpty else { return }
            d.renderPlugins.append(RenderPlugin(id: pkg.id, js: js))
        case .commands:
            guard let items = try? JSONDecoder().decode([CommandSpec].self, from: Data(contentsOf: pkg.mainURL)) else { return }
            d.commands.append(contentsOf: items.map {
                PluginCommand(id: "cmd-\(pkg.id)-\($0.id)", name: $0.name,
                              icon: $0.icon ?? "command",
                              category: $0.category ?? _L("插件", "Plugins"), actionID: $0.action)
            })
        }
    }

    /// 容错：把 JSON 解码后残留的字面转义（作者误写成 \n 而非换行）归一化为真实换行/制表符。
    /// 正确写法在 JSON 源文件就是 \n（一个反斜杠），解码后已是真实换行，此函数为零变化；只有误写 \\n（两个反斜杠）的旧包会被修正。
    static func normalizeText(_ s: String) -> String {
        s.replacingOccurrences(of: "\\n", with: "\n")
         .replacingOccurrences(of: "\\t", with: "\t")
         .replacingOccurrences(of: "\\r\\n", with: "\r\n")
    }

    // MARK: - 查询

    func allPackages() -> [PluginPackage] {
        lock.lock(); defer { lock.unlock() }
        return packagesByID.values.sorted { $0.name < $1.name }
    }

    @discardableResult
    func toggle(_ id: String) -> ToggleOutcome {
        lock.lock()
        guard let pkg = packagesByID[id] else {
            lock.unlock()
            return .ok
        }
        let now = !pkg.enabled
        if !now, pkg.kind == .theme,
           packagesByID.values.filter({ $0.kind == .theme && $0.enabled }).count <= 1 {
            lock.unlock()
            return .blockedLastTheme
        }
        UserDefaults.standard.set(now, forKey: "pluginEnabled.\(id)")
        packagesByID[id]?.enabled = now
        rebuildData()
        lock.unlock()
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
        return .ok
    }

    func fileOverride(for ext: String) -> FileTypeOverride? {
        lock.lock(); defer { lock.unlock() }
        return data.fileOverrides[ext.lowercased()]
    }

    func allExperts() -> [AIExpert] {
        lock.lock(); defer { lock.unlock() }
        return data.experts
    }

    func allSnippets() -> [PluginSnippet] {
        lock.lock(); defer { lock.unlock() }
        return data.snippets
    }

    func allThemes() -> [PluginTheme] {
        lock.lock(); defer { lock.unlock() }
        return data.themes
    }

    /// 某主题包未通过质量审计的原因（空 = 全部通过）。
    func themeIssues(for packageID: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return data.themeIssues[packageID] ?? []
    }

    func allRenderPlugins() -> [RenderPlugin] {
        lock.lock(); defer { lock.unlock() }
        return data.renderPlugins
    }

    func allCommands() -> [PluginCommand] {
        lock.lock(); defer { lock.unlock() }
        return data.commands
    }

    /// 已启用包提供的全部视图。
    func allViews() -> [PluginView] {
        lock.lock(); defer { lock.unlock() }
        return data.views
    }

    /// 某视图包未通过的原因（空 = 通过）。
    func viewIssues(for packageID: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return data.viewIssues[packageID] ?? []
    }

    /// 主区域视图（placement = main）；多个时取第一个。
    func mainAreaView(type: PluginViewType) -> PluginView? {
        lock.lock(); defer { lock.unlock() }
        return data.views.first { $0.type == type && $0.placement == .main }
    }

    func enabledTheme() -> PluginTheme? {
        lock.lock(); defer { lock.unlock() }
        let id = UserDefaults.standard.string(forKey: "pluginThemeID")
        return data.themes.first { $0.id == id }
    }

    func setTheme(_ id: String) {
        UserDefaults.standard.set(id, forKey: "pluginThemeID")
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
    }

    static func reveal(_ dir: URL) { NSWorkspace.shared.open(dir) }

    // MARK: - Specs

    struct ExpertSpec: Codable {
        let id: String
        let name: String
        let icon: String?
        let desc: String?
        let system: String
        func toExpert() -> AIExpert {
            AIExpert(id: id, name: name, icon: icon ?? "person.crop.circle",
                     desc: desc ?? "", system: system)
        }
    }

    struct SnippetSpec: Codable {
        let id: String?
        let name: String
        let language: String?
        let text: String
        let textEn: String?
    }

    struct CommandSpec: Codable {
        let id: String
        let name: String
        let icon: String?
        let category: String?
        let action: String
    }

}

struct PluginData {
    var experts: [AIExpert] = []
    var fileOverrides: [String: FileTypeOverride] = [:]
    var snippets: [PluginSnippet] = []
    var themes: [PluginTheme] = []
    /// 主题包 → 质量审计未通过原因（面板可展示，帮助作者补齐）
    var themeIssues: [String: [String]] = [:]
    var renderPlugins: [RenderPlugin] = []
    var commands: [PluginCommand] = []
    /// 视图插件（声明式视图：卡片墙 / 素材网格）
    var views: [PluginView] = []
    /// 视图包 → 未通过原因（面板可展示）
    var viewIssues: [String: [String]] = [:]
}

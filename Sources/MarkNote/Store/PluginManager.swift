import Foundation
import AppKit

/// 插件管理器：扫描（工作台 .plugins/ + 全局目录）→ 校验 manifest → 按启用集合并进注册表。
/// 全部数据驱动，不执行任何代码；坏包跳过。线程安全（锁）。
final class PluginManager {
    static let shared = PluginManager()
    static let changedNotification = Notification.Name("pluginsChanged")

    private let lock = NSLock()
    private var packagesByID: [String: PluginPackage] = [:]
    private(set) var data = PluginData()

    func scan(workspaceDir: URL?) {
        lock.lock(); defer { lock.unlock() }
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
        var d = PluginData()
        for pkg in packagesByID.values where pkg.enabled {
            apply(pkg, into: &d)
        }
        data = d
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
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
                d.themes.append(PluginTheme(id: "plugin-\(pkg.id)-\(t.id)", name: t.name,
                                            desc: t.desc ?? "",
                                            cssFile: pkg.dir.appendingPathComponent(t.cssFile).path,
                                            swatchHex: t.swatchHex ?? "#7c9eff"))
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

    func toggle(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        guard let pkg = packagesByID[id] else { return }
        let now = !pkg.enabled
        UserDefaults.standard.set(now, forKey: "pluginEnabled.\(id)")
        packagesByID[id]?.enabled = now
        rebuildData()
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

    func allRenderPlugins() -> [RenderPlugin] {
        lock.lock(); defer { lock.unlock() }
        return data.renderPlugins
    }

    func allCommands() -> [PluginCommand] {
        lock.lock(); defer { lock.unlock() }
        return data.commands
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

    struct ThemeSpec: Codable {
        let id: String
        let name: String
        let desc: String?
        let cssFile: String
        let swatchHex: String?
    }
}

struct PluginData {
    var experts: [AIExpert] = []
    var fileOverrides: [String: FileTypeOverride] = [:]
    var snippets: [PluginSnippet] = []
    var themes: [PluginTheme] = []
    var renderPlugins: [RenderPlugin] = []
    var commands: [PluginCommand] = []
}

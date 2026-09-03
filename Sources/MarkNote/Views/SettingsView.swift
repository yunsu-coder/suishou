import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 设置面板（⌘,）
struct SettingsView: View {
    @Environment(NotesStore.self) private var store
    @AppStorage("editorFontSize") private var editorFontSize = 13.0
    @AppStorage("previewFontScale") private var previewFontScale = 1.0

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .environment(store)
                .tabItem { Label(_LL("通用", "General"), systemImage: "gear") }
            // 主题：按产品决策仅保留「晨曦」，无选择器
            EditorSettingsTab(editorFontSize: $editorFontSize, previewFontScale: $previewFontScale)
                .tabItem { Label(_LL("编辑", "Editor"), systemImage: "textformat.size") }
            PluginsSettingsTab()
                .tabItem { Label(_LL("插件", "Plugins"), systemImage: "puzzlepiece.extension") }
        }
        .frame(width: 480, height: 380)
    }
}

private struct GeneralSettingsTab: View {
    @Environment(NotesStore.self) private var store
    @AppStorage(Glass.key) private var windowGlass = 0.0
    @AppStorage(LLM.kModel) private var llmModel = "deepseek-v4-flash-vision-exp"
    /// 语言切换后 VS Code 式重启提示（设置窗口打开时语言选项改变 → 提示重启）
    @State private var languageChanged = false

    var body: some View {
        Form {
            Section(_L("语言 / Language", "Language")) {
                Picker(_L("界面语言", "Language"), selection: Binding<String>(
                    get: { UserDefaults.standard.string(forKey: "appLanguage") ?? "system" },
                    set: {
                        UserDefaults.standard.set($0, forKey: "appLanguage")
                        languageChanged = true
                    }
                )) {
                    Text(AppLanguage.system.name).tag("system")
                    Text(_L("中文", "Chinese")).tag("zh")
                    Text("English").tag("en")
                }
                .pickerStyle(.menu)
                if languageChanged {
                    HStack(spacing: 10) {
                        Label(_L("更改将在重启应用后完全生效", "Changes take full effect after restarting the app"),
                              systemImage: "arrow.clockwise.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(_L("立即重启", "Restart Now")) { relaunchApp() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                } else {
                    Text(_L("切换后重启应用完全生效（核心界面即时部分生效）。", "Restart app for full effect."))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Section(_L("AI 自动化", "AI Automation")) {
                Toggle(_L("AI 自动命名（新建文件后生成标题）", "Auto-name new files (generate a title after creation)"), isOn: Binding(
                    get: { UserDefaults.standard.object(forKey: "aiAutoTitle") as? Bool ?? true },
                    set: { UserDefaults.standard.set($0, forKey: "aiAutoTitle") }
                ))
                .toggleStyle(.switch)
            }
            Section(_L("大模型（Auto 命名）", "Model (Auto naming)")) {
                Picker(_L("模型", "Model"), selection: $llmModel) {
                    ForEach(LLM.availableModels, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .pickerStyle(.menu)
                Text(_L("DeepSeek 已内置（无需密钥）。自动命名：新建「无标题」草稿后自动生成标题；右键文件 →「AI 改标题」可手动触发。仅上送当前文档前 1500 字，不上送整个库。", "DeepSeek is built in (no API key needed). Auto-naming: after an untitled draft is created, a title is generated automatically; right-click a file → 'AI Rename Title' to trigger it manually. Only the first 1500 characters of the current document are sent, not the whole library."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Section(_L("外观", "Appearance")) {
                Picker(_L("主题", "Theme"), selection: Binding(
                    get: { currentTheme },
                    set: { store.setTheme($0) }
                )) {
                    ForEach(Theme.allCases) { t in
                        Text(_L("\(t.name)（\(t.subtitle)）", "\(t.name) (\(t.subtitle))")).tag(t)
                    }
                }
                .pickerStyle(.menu)
                VStack {
                    HStack {
                        Text(_L("毛玻璃（透出桌面壁纸）", "Glass (show desktop wallpaper)"))
                        Spacer()
                        Text("\(Int(windowGlass * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $windowGlass, in: 0...1, step: 0.05)
                }
                Text(_L("开启后窗口、编辑器与预览背景转为半透明：壁纸经模糊处理透出，文字可读性有保障。关闭（0%）恢复原有不透明观感。", "When enabled, the window, editor and preview backgrounds become semi-transparent: the wallpaper shows through blurred while text stays readable. Turning it off (0%) restores the original opaque look."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Section(_L("工作台（本地文件夹）", "Workspace (local folder)")) {
                Text(store.notesDir.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .truncationMode(.middle)
                    .lineLimit(2)
                    .textSelection(.enabled)
                HStack {
                    Button(_L("选择 / 新建工作台…", "Select / New Workspace…")) { store.chooseNotesDirectory() }
                    Button(_L("在 Finder 中显示", "Show in Finder")) {
                        NSWorkspace.shared.open(store.notesDir)
                    }
                    Spacer()
                }
                Text(_L("工作台是一个本地文件夹：Markdown 文件即笔记，资源自动归类到 source/<类型>/；可多工作台切换（历史目录在上）。", "A workspace is a local folder: Markdown files are notes, and assets are automatically sorted into source/<type>/. Multiple workspaces can be switched (history directories listed above)."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                // 多工作台：历史目录列表（切换/移除）
                if store.workspaceRoots.count > 1 {
                    ForEach(store.workspaceRoots, id: \.self) { path in
                        let active = FileManager.default.isWritableFile(atPath: path) == true && store.notesDir.path == path
                        HStack {
                            Text(path)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(active ? Color.accentColor : .secondary)
                            Spacer()
                            if !active {
                                Button(_L("切换", "Switch")) { store.switchWorkspace(path) }
                                    .buttonStyle(.borderless)
                                Button(_L("移除", "Remove")) { store.removeWorkspace(path) }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(_L("当前", "Current")).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            Spacer()
        }
        .padding()
        .formStyle(.grouped)
    }

    /// VS Code 式重启：以 open -n 强制启动新实例，再退出当前（应用已写入新语言配置）。
    /// 注意：不能用 NSWorkspace.open——它检测到已有实例只会激活不新建，terminate 后应用就没了。
    private func relaunchApp() {
        let url = Bundle.main.bundleURL
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-n", url.path]
        try? p.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            NSApp.terminate(nil)
        }
    }
}

/// 编辑设置：字号 / 字体（含自定义字体库）+ 预览缩放与字体
private struct EditorSettingsTab: View {
    @Environment(NotesStore.self) private var store
    @Binding var editorFontSize: Double
    @Binding var previewFontScale: Double
    @AppStorage("previewFont") private var previewFont = "system"
    @AppStorage("editorFontFamily") private var editorFontFamily = "mono"

    var body: some View {
        Form {
            Section(_L("编辑器", "Editor")) {
                VStack {
                    HStack {
                        Text(_L("源码字号", "Source Font Size"))
                        Spacer()
                        Text("\(editorFontSize, specifier: "%.1f") pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $editorFontSize, in: 9...30)
                }
                Picker(_L("源码字体", "Source Font"), selection: $editorFontFamily) {
                    Text(_L("等宽（SF Mono）", "Monospaced (SF Mono)")).tag("mono")
                    Text("Menlo").tag("menlo")
                    Text("Monaco").tag("monaco")
                    Text(_L("PingFang 苹方", "PingFang")).tag("pingfang")
                    Text(_L("Kaiti 楷体", "Kaiti")).tag("kaiti")
                    Text(_L("Songti 宋体", "Songti")).tag("songti")
                    ForEach(store.customFonts) { f in
                        Text(f.family).tag(f.family)
                    }
                }
            }
            Section(_L("预览", "Preview")) {
                VStack {
                    HStack {
                        Text(_L("正文缩放", "Body Scale"))
                        Spacer()
                        Text("\(previewFontScale, specifier: "%.1f%%")")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $previewFontScale, in: 0.6...2.0)
                }
                Picker(_L("预览字体", "Preview Font"), selection: $previewFont) {
                    Text(_L("系统", "System")).tag("system")
                    Text(_L("苹方 PingFang", "PingFang")).tag("pingfang")
                    Text(_L("楷体 Kaiti", "Kaiti")).tag("kaiti")
                    Text(_L("宋体 Songti", "Songti")).tag("songti")
                    Text(_L("等宽 Mono", "Mono")).tag("mono")
                    ForEach(store.customFonts) { f in
                        Text(f.family).tag(f.family)
                    }
                }
            }
            Section(_L("自定义字体", "Custom Fonts")) {
                if store.customFonts.isEmpty {
                    Text(_L("导入 .ttf / .otf / .ttc 字体文件后，可在「源码字体」「预览字体」中选用。", "After importing .ttf / .otf / .ttc font files, you can select them in 'Source Font' and 'Preview Font'."))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(store.customFonts) { f in
                        HStack {
                            Text(f.family).lineLimit(1)
                            Spacer()
                            Button(_L("删除", "Delete")) { store.removeCustomFont(f) }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                        }
                    }
                }
                Button(_L("导入字体…", "Import Font…")) { importCustomFont() }
            }
            Spacer()
        }
        .padding()
        .formStyle(.grouped)
    }

    /// 文件选择器导入字体（.ttf/.otf/.ttc；结果 Toast 反馈）
    private func importCustomFont() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = CustomFonts.extensions.compactMap { UTType(filenameExtension: $0) }
        panel.message = _L("选择字体文件（.ttf / .otf / .ttc）", "Choose a font file (.ttf / .otf / .ttc)")
        panel.prompt = _L("导入", "Import")
        if panel.runModal() == .OK, let url = panel.url {
            store.importCustomFont(from: url)
        }
    }
}


/// 插件设置：扫描包列表（工作台 .plugins/ + 全局），启用/禁用、主题应用、Finder 显示
private struct PluginsSettingsTab: View {
    @State private var packages: [PluginPackage] = []
    @State private var themes: [PluginTheme] = []
    @State private var selectedThemeID = ""
    @State private var note = ""

    var body: some View {
        Form {
            Section(_L("已安装插件", "Installed Plugins")) {
                if packages.isEmpty {
                    Text(_L("未发现插件\n放置位置：工作台 .plugins/<id>/ 或 ~/Library/Application Support/MarkNote/plugins/<id>/", "No plugins found\nLocation: workspace .plugins/<id>/ or ~/Library/Application Support/MarkNote/plugins/<id>/"))
                        .font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(packages) { pkg in
                        Toggle(isOn: Binding(
                            get: { pkg.enabled },
                            set: { _ in PluginManager.shared.toggle(pkg.id); reload() }
                        )) {
                            HStack(spacing: 8) {
                                Text(pkg.name).font(.callout.weight(.medium))
                                Text(pkg.version).font(.caption2).foregroundStyle(.tertiary)
                                Text(pkg.kind.displayName)
                                    .font(.caption2)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                                Text(pkg.isGlobal ? _L("全局", "Global") : _L("工作台", "Workspace"))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                }
            }
            
            
            
            if !themes.isEmpty {
                Section(_L("插件主题", "Plugin Themes")) {
                    ForEach(themes) { t in
                        Button {
                            PluginManager.shared.setTheme(t.id)
                            selectedThemeID = t.id
                        } label: {
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(hex: t.swatchHex))
                                    .frame(width: 18, height: 18)
                                Text(t.name).font(.callout)
                                Spacer()
                                Image(systemName: selectedThemeID == t.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedThemeID == t.id ? Color.accentColor : Color.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Text(note).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
        .formStyle(.grouped)
        .onAppear {
            reload()
            PluginManager.shared.scan(workspaceDir: nil)
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: PluginManager.changedNotification)) { _ in
            reload()
        }
    }

    private func reload() {
        packages = PluginManager.shared.allPackages()
        themes = PluginManager.shared.allThemes()
        selectedThemeID = UserDefaults.standard.string(forKey: "pluginThemeID") ?? ""
    }
}

extension Color {
    /// #RRGGBB → Color（插件主题色板用）
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let v = UInt64(h, radix: 16) else {
            self = .accentColor
            return
        }
        self = Color(red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }
}

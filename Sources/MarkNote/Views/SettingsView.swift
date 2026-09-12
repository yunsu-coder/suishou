import SwiftUI
import AppKit
/// 设置面板（⌘,）
struct SettingsView: View {
    @Environment(NotesStore.self) private var store
    @AppStorage("editorFontSize") private var editorFontSize = 13.0
    @AppStorage("previewFontScale") private var previewFontScale = 1.0
    @State private var appearanceToken = "-"

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .environment(store)
                .tabItem { Label(_LL("通用", "General"), systemImage: "gear") }
            EditorSettingsTab(editorFontSize: $editorFontSize, previewFontScale: $previewFontScale)
                .tabItem { Label(_LL("编辑", "Editor"), systemImage: "textformat.size") }
            PluginsSettingsTab()
                .tabItem { Label(_LL("插件", "Plugins"), systemImage: "puzzlepiece.extension") }
        }
        .frame(width: 480, height: 380)
        .tint(appAppearance.accent)
        .preferredColorScheme(appAppearance.scheme)
        // 只刷新外观，不重建整个 TabView（避免与插件重扫形成 onAppear 循环）。
        .background(Color.clear.id("\(store.themeVersion)-\(appearanceToken)"))
        .onReceive(NotificationCenter.default.publisher(for: PluginManager.changedNotification)) { _ in
            appearanceToken = PluginManager.shared.enabledTheme()?.id ?? "-"
        }
    }
}

private struct GeneralSettingsTab: View {
    @Environment(NotesStore.self) private var store
    @AppStorage(LLM.kModel) private var llmModel = "deepseek-v4-flash-vision-exp"
    @State private var themeOptions: [ThemeOption] = []
    /// 设置页里的 API Key 输入草稿（保存后清空，列表只显示掩码）
    @State private var apiKeyDraft = ""
    @State private var keyStatus: String?
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
                Text(_L("自动命名：新建「无标题」草稿后自动生成标题；右键文件 →「AI 改标题」可手动触发。仅上送当前文档前 1500 字，不上送整个库。", "Auto-naming: after an untitled draft is created, a title is generated automatically; right-click a file → 'AI Rename Title' to trigger it manually. Only the first 1500 characters of the current document are sent, never the whole library."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Section(_L("模型服务（API Key）", "Model service (API key)")) {
                HStack(spacing: 8) {
                    SecureField(_L("粘贴你的 API Key（sk-…）", "Paste your API key (sk-…)"), text: $apiKeyDraft)
                        .textFieldStyle(.roundedBorder)
                    Button(_L("保存", "Save")) {
                        LLM.setAPIKey(apiKeyDraft)
                        apiKeyDraft = ""
                        keyStatus = LLM.configured ? _L("已保存", "Saved") : _L("已清除", "Cleared")
                    }
                    .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(_L("清除", "Clear")) {
                        LLM.clearAPIKey()
                        keyStatus = _L("已清除", "Cleared")
                    }
                    .disabled(!LLM.configured)
                }
                HStack(spacing: 8) {
                    Text(LLM.configured
                         ? _L("当前：\(LLM.maskedKey)", "Current: \(LLM.maskedKey)")
                         : _L("未配置 —— AI 功能不可用", "Not configured — AI features are unavailable"))
                        .font(.caption)
                        .foregroundStyle(LLM.configured ? .secondary : .tertiary)
                    Button(_L("测试连接", "Test connection")) {
                        keyStatus = _L("测试中…", "Testing…")
                        Task {
                            let err = await LLM.verifyConnection()
                            await MainActor.run {
                                keyStatus = err.map { _L("连接失败：\($0)", "Failed: \($0)") } ?? _L("连接正常 ✓", "Connection OK ✓")
                            }
                        }
                    }
                    .disabled(!LLM.configured)
                    if let keyStatus {
                        Text(keyStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(_L("密钥只保存在本机（UserDefaults），不写入仓库、不上传；请到模型服务商后台自行申请。没填 key 时 AI 面板与自动命名会明确提示「API Key 无效」。",
                        "The key is stored only on this machine (UserDefaults) — never committed or uploaded. Get one from your model provider. Without a key, the AI panel and auto-naming say so explicitly."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Section(_L("外观", "Appearance")) {
                if themeOptions.isEmpty {
                    Text(_L("未安装主题插件。安装并启用主题包后，这里会出现可选主题。",
                            "No theme plugins installed. Enable a theme package to see it here."))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Picker(_L("主题", "Theme"), selection: Binding(
                        get: { currentThemeOptionID },
                        set: { store.selectThemeOption($0) }
                    )) {
                        ForEach(themeOptions) { t in
                            Text(t.subtitle.isEmpty ? t.name
                                 : _L("\(t.name)（\(t.subtitle)）", "\(t.name) (\(t.subtitle))"))
                                .tag(t.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Text(_L("主题全部来自插件包：选择任一项都会立即作用于窗口、侧栏、编辑器与预览。",
                        "All themes come from plugin packages: any selection applies immediately to the window, sidebar, editor, and preview."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(_L("窗口透明度由当前主题决定：\(Int(appAppearance.glass * 100))%",
                        "Window transparency is defined by the active theme: \(Int(appAppearance.glass * 100))%"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(_L("内置主题保持不透明；插件主题可自带玻璃强度，用户不再单独调节。",
                        "Built-in themes stay opaque; plugin themes can define their own glass level. No user slider."))
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
                                .foregroundStyle(active ? appAppearance.accent : .secondary)
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
        .onAppear { themeOptions = allThemeOptions }
        .onReceive(NotificationCenter.default.publisher(for: PluginManager.changedNotification)) { _ in
            themeOptions = allThemeOptions
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

/// 编辑设置：字号 / 预览缩放。字体完全由当前主题提供。
private struct EditorSettingsTab: View {
    @Binding var editorFontSize: Double
    @Binding var previewFontScale: Double

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
                Text(_L("源码字体由当前主题提供：\(appAppearance.codeFontFamily ?? "系统等宽")",
                        "Source font is provided by the active theme: \(appAppearance.codeFontFamily ?? "System Mono")"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(_L("主题推荐源码字号：\(Int(appAppearance.codeFontSize ?? editorFontSize)) pt",
                        "Theme-recommended source size: \(Int(appAppearance.codeFontSize ?? editorFontSize)) pt"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
                Text(_L("预览字体由当前主题提供：\(appAppearance.uiFontFamily ?? "系统字体")",
                        "Preview font is provided by the active theme: \(appAppearance.uiFontFamily ?? "System")"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding()
        .formStyle(.grouped)
    }
}


/// 插件设置：扫描包列表（工作台 .plugins/ + 全局），启用/禁用、Finder 显示
private struct PluginsSettingsTab: View {
    @State private var packages: [PluginPackage] = []
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
                            set: { _ in
                                switch PluginManager.shared.toggle(pkg.id) {
                                case .blockedLastTheme:
                                    note = _L("至少保留一个主题包兜底，无法关闭。", "At least one theme package must stay enabled.")
                                case .ok:
                                    note = ""
                                }
                                reload()
                            }
                        )) {
                            HStack(spacing: 8) {
                                Text(pkg.name).font(.callout.weight(.medium))
                                Text(pkg.version).font(.caption2).foregroundStyle(.tertiary)
                                Text(pkg.kind.displayName)
                                    .font(.caption2)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(appAppearance.accent.opacity(0.14), in: Capsule())
                                Text(pkg.isGlobal ? _L("全局", "Global") : _L("工作台", "Workspace"))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                }
                if !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding()
        .formStyle(.grouped)
        .onAppear {
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: PluginManager.changedNotification)) { _ in
            reload()
        }
    }

    private func reload() {
        packages = PluginManager.shared.allPackages()
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

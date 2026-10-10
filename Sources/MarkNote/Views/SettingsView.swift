import SwiftUI
import AppKit
import UniformTypeIdentifiers
/// 设置面板（⌘,）
struct SettingsView: View {
    @Environment(NotesStore.self) private var store
    @AppStorage("editorFontSize") private var editorFontSize = 13.0
    @AppStorage("previewFontScale") private var previewFontScale = 1.0
    @AppStorage("previewImageCaptions") private var previewImageCaptions = true
    @AppStorage("editorSpellCheck") private var editorSpellCheck = true
    @State private var appearanceToken = "-"

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .environment(store)
                .tabItem { Label(_LL("通用", "General"), systemImage: "gear") }
            EditorSettingsTab(editorFontSize: $editorFontSize, previewFontScale: $previewFontScale,
                              previewImageCaptions: $previewImageCaptions, spellCheck: $editorSpellCheck)
                .tabItem { Label(_LL("编辑", "Editor"), systemImage: "textformat.size") }
            PluginsSettingsTab()
                .tabItem { Label(_LL("插件", "Plugins"), systemImage: "puzzlepiece.extension") }
            DiagnosticsSettingsTab()
                .tabItem { Label(_LL("诊断", "Diagnostics"), systemImage: "stethoscope") }
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
            Section(_L("大模型", "Model")) {
                Picker(_L("模型", "Model"), selection: $llmModel) {
                    ForEach(LLM.availableModels, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .pickerStyle(.menu)
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
                Text(_L("密钥只保存在本机（UserDefaults），不写入仓库、不上传；请到模型服务商后台自行申请。没填 key 时 AI 面板会明确提示「API Key 无效」。",
                        "The key is stored only on this machine (UserDefaults) — never committed or uploaded. Get one from your model provider. Without a key, the AI panel says so explicitly."))
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
    @Binding var previewImageCaptions: Bool
    @Binding var spellCheck: Bool
    @AppStorage("cxxIntelEnabled") private var cxxIntel = true

    var body: some View {
        Form {
            Section(_L("代码智能", "Code Intelligence")) {
                Toggle(_L("C/C++ 智能提示（clangd）", "C/C++ intellisense (clangd)"), isOn: $cxxIntel)
                Text(_L("clangd 随 Xcode 自带、零安装：错误 / 警告下划线与语义补全（Tab 接受）。关掉后只留本地词表补全。",
                        "clangd ships with Xcode: diagnostics + semantic completion (Tab to accept). Off = local word list only."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Toggle(_L("拼写检查（英文，仅散文）", "Spell checking (English, prose only)"), isOn: $spellCheck)
                Text(_L("对 md / txt 的英文单词画点线提示；代码文件不开（避免把标识符全标上）。",
                        "Dot-underline misspelled English in prose only; code files excluded."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
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
                Toggle(_L("图片下方显示图注", "Show image captions"), isOn: $previewImageCaptions)
                Text(_L("图注只认显式写的说明：![图](路径 \"图注\") 或 {caption=图注}；关掉后图片本身不受影响。",
                        "Captions come from an explicit title or {caption=…} only."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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

/// "诊断"页：记录最近操作耗时 / 次数，可导出诊断包（纯本地生成，不上传）。
/// 用途：你说"这里卡了一下"时，能对照看出是哪类操作慢（打开 / 索引刷新 / 预览渲染 / 语法高亮）。
private struct DiagnosticsSettingsTab: View {
    @State private var snap = PerfLog.snapshot()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(_L("最近操作用时（毫秒）", "Recent operations (ms)"))
                    .font(.headline)
                Spacer()
                Button(_L("刷新", "Refresh")) { snap = PerfLog.snapshot() }
                    .controlSize(.small)
                Button(_L("导出诊断包…", "Export…")) { export() }
                    .controlSize(.small)
                Button(_L("清空", "Clear")) {
                    PerfLog.reset()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { snap = PerfLog.snapshot() }
                }
                .controlSize(.small)
            }
            .padding([.horizontal, .top], 12)
            .padding(.bottom, 6)

            List {
                Section(_L("慢操作排行", "Slowest first")) {
                    if snap.aggregates.isEmpty {
                        Text(_L("还没有数据 —— 用一会儿再回来看。", "No data yet — use the app and come back."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(snap.aggregates.prefix(10), id: \.label) { a in
                        HStack(spacing: 10) {
                            Text(a.label)
                                .font(.system(size: 12))
                            Spacer()
                            Text(_L("\(a.count) 次", "\(a.count)×"))
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.tertiary)
                            Text("均 \(ms(a.avgMs))")
                                .font(.system(size: 11).monospacedDigit())
                            Text("最大 \(ms(a.maxMs))")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(a.maxMs > 100 ? .orange : .secondary)
                            Text("最近 \(ms(a.lastMs))")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section(_L("计数", "Counters")) {
                    if snap.counters.isEmpty {
                        Text("—").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(Array(snap.counters.enumerated()), id: \.offset) { _, c in
                        HStack {
                            Text(c.name).font(.system(size: 12))
                            Spacer()
                            Text("\(c.count)")
                                .font(.system(size: 12).monospacedDigit())
                        }
                    }
                }
                Section(_L("最近记录", "Recent")) {
                    ForEach(Array(snap.recent.prefix(15).enumerated()), id: \.offset) { _, e in
                        HStack(spacing: 8) {
                            Text(clock(e.date))
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.tertiary)
                            Text(e.label).font(.system(size: 11))
                            Spacer()
                            Text(ms(e.ms)).font(.system(size: 11).monospacedDigit())
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .onAppear { snap = PerfLog.snapshot() }
    }

    private func ms(_ v: Double) -> String { String(format: "%.1f", v) }

    private func clock(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "marknote-diagnostics.json"
        panel.allowedContentTypes = [.json]
        panel.message = _L("导出诊断数据（本地生成，不上传）", "Export diagnostics (generated locally)")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let iso = ISO8601DateFormatter()
        var root: [String: Any] = [:]
        root["generatedAt"] = iso.string(from: snap.generatedAt)
        root["app"] = "随手 MarkNote"
        root["version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        root["operations"] = snap.aggregates.map {
            ["label": $0.label, "count": $0.count, "avgMs": $0.avgMs, "maxMs": $0.maxMs, "lastMs": $0.lastMs]
        }
        root["counters"] = Dictionary(uniqueKeysWithValues: snap.counters.map { ($0.name, $0.count) })
        root["recent"] = snap.recent.map { ["label": $0.label, "ms": $0.ms, "at": iso.string(from: $0.date)] }
        if let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
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

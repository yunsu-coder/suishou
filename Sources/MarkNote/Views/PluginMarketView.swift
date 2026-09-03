import SwiftUI
import AppKit

/// 插件市场 —— 居中宽面板（网格磁贴 + 详情栏，App Store 风格）
/// 由左侧功能栏 🧩 唤起；不局限窄侧栏。
struct PluginMarketView: View {
    @Environment(NotesStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var packages: [PluginPackage] = []
    @State private var selectedID: String?
    @State private var uninstallTarget: PluginPackage?
    @State private var note = ""

    private var selected: PluginPackage? {
        packages.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if packages.isEmpty {
                emptyHint
            } else {
                HSplitView {
                    gridPane
                        .frame(minWidth: 320, idealWidth: 420)
                    detailPane
                        .frame(minWidth: 300, idealWidth: 340)
                }
            }
            Divider()
            footer
        }
        .frame(width: 780, height: 560)
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: PluginManager.changedNotification)) { _ in reload() }
        .confirmationDialog(_L("卸载插件？", "Uninstall plugin?"),
                            isPresented: Binding(get: { uninstallTarget != nil },
                                                 set: { if !$0 { uninstallTarget = nil } }),
                            presenting: uninstallTarget) { pkg in
            Button(_LL("卸载（删除包目录）", "Uninstall (delete folder)"), role: .destructive) { uninstall(pkg) }
            Button(_LL("取消", "Cancel"), role: .cancel) {}
        } message: { pkg in
            Text(_L("将移除：\(pkg.displayName)", "Remove: \(pkg.displayName)"))
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(currentTheme.accent)
            Text(_LL("插件市场", "Plugin Market"))
                .font(.headline)
            Text("\(packages.count) " + _L("个插件", "plugins"))
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
            Button(_LL("关闭", "Close")) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    // MARK: - 左：磁贴网格

    private var gridPane: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 176), spacing: 12)], spacing: 12) {
                ForEach(packages) { pkg in
                    tile(pkg)
                }
            }
            .padding(14)
        }
    }

    /// 磁贴：大图标 + 名称 + 简介 + 启用角标（App Store 卡片）
    private func tile(_ pkg: PluginPackage) -> some View {
        Button {
            selectedID = pkg.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    pluginIcon(pkg, size: 44)
                    if pkg.enabled {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.green)
                            .padding(2)
                    }
                }
                Text(pkg.displayName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text(pkg.displayDesc.isEmpty ? _L("（暂无简介）", "(no summary)") : pkg.displayDesc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Text(pkg.kind.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(PluginPackage.tint(for: pkg.kind).opacity(0.16), in: Capsule())
                        .foregroundStyle(PluginPackage.tint(for: pkg.kind))
                    Text(pkg.version).font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                }
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor).opacity(selectedID == pkg.id ? 0 : 0.55),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(selectedID == pkg.id ? currentTheme.accent.opacity(0.6) : Color(nsColor: .separatorColor).opacity(0.5),
                        lineWidth: selectedID == pkg.id ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 右：详情栏

    private var detailPane: some View {
        Group {
            if let pkg = selected {
                detail(pkg)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "hand.point.up.left")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                    Text(_LL("选择一个插件查看详情", "Select a plugin for details"))
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func detail(_ pkg: PluginPackage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    pluginIcon(pkg, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(pkg.displayName).font(.title3.weight(.semibold))
                        Text("\(pkg.version) · \(pkg.kind.displayName)")
                            .font(.caption).foregroundStyle(.tertiary)
                        if !pkg.author.isEmpty {
                            Text(_L("作者", "By") + " " + pkg.author)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                // 启用大按钮
                Button {
                    PluginManager.shared.toggle(pkg.id); reload()
                } label: {
                    HStack {
                        Image(systemName: pkg.enabled ? "checkmark.square.fill" : "square")
                        Text(pkg.enabled ? _LL("已启用", "Enabled") : _LL("启用", "Enable"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(pkg.enabled ? Color.accentColor : Color.gray)
                .controlSize(.regular)

                Text(_LL("基础功能", "Features"))
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if pkg.displayFeatures.isEmpty {
                    Text(_L("（该包未声明功能清单）", "(no feature list)")).font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(pkg.displayFeatures, id: \.self) { f in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.circle")
                                .font(.caption).foregroundStyle(PluginPackage.tint(for: pkg.kind)).padding(.top, 1)
                            Text(f).font(.caption).foregroundStyle(.primary)
                        }
                    }
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(_LL("位置", "Location")).font(.caption2).foregroundStyle(.tertiary)
                        Text(pkg.isGlobal ? _L("全局", "Global") : _L("工作台", "Workspace")).font(.caption)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(_LL("最低版本", "Min App")).font(.caption2).foregroundStyle(.tertiary)
                        Text(pkg.minAppVersion.isEmpty ? "-" : pkg.minAppVersion).font(.caption)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(_LL("包目录", "Folder")).font(.caption2).foregroundStyle(.tertiary)
                        Text(pkg.dir.lastPathComponent).font(.caption).lineLimit(1)
                    }
                }

                HStack(spacing: 8) {
                    Button(_LL("在 Finder 中显示", "Reveal in Finder")) {
                        PluginManager.reveal(pkg.dir)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    Button(_LL("卸载…", "Uninstall…"), role: .destructive) {
                        uninstallTarget = pkg
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    Spacer()
                }
            }
            .padding(16)
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox").font(.system(size: 34)).foregroundStyle(.tertiary)
            Text(_LL("暂无插件", "No plugins")).font(.title3).foregroundStyle(.secondary)
            Text(_LL("用下方「导入包…」安装含 manifest.json 的本地插件包。",
                     "Use Import below to add a package folder with manifest.json."))
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Text(note).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            Spacer()
            Button(_LL("刷新预览", "Reload Preview")) {
                NotificationCenter.default.post(name: .renderForceRefresh, object: nil)
            }
            .buttonStyle(.bordered).controlSize(.small)
            .help(_L("启用/禁用后立即重新渲染预览", "Re-render preview after toggles"))
            Button(_LL("打开插件目录", "Open Plugins Dir")) {
                if let b = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                    let d = b.appendingPathComponent("MarkNote/plugins", isDirectory: true)
                    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
                    PluginManager.reveal(d)
                }
            }
            .buttonStyle(.bordered).controlSize(.small)
            Button(_LL("导入包…", "Import…")) { importPackage() }
                .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: - 动作

    private func reload() {
        packages = PluginManager.shared.allPackages()
        note = ""
        if let sel = selectedID, !packages.contains(where: { $0.id == sel }) { selectedID = nil }
    }

    private func uninstall(_ pkg: PluginPackage) {
        try? FileManager.default.removeItem(at: pkg.dir)
        UserDefaults.standard.removeObject(forKey: "pluginEnabled.\(pkg.id)")
        if selectedID == pkg.id { selectedID = nil }
        PluginManager.shared.scan(workspaceDir: store.notesDir)
        note = _L("已卸载：\(pkg.displayName)", "Uninstalled: \(pkg.displayName)")
    }

    private func importPackage() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = _L("选择包含 manifest.json 的插件包目录", "Choose a package folder with manifest.json")
        guard panel.runModal() == .OK, let srcDir = panel.url else { return }
        guard FileManager.default.fileExists(atPath: srcDir.appendingPathComponent("manifest.json").path) else {
            note = _L("该目录不是插件包（缺少 manifest.json）", "Not a package: manifest.json missing")
            return
        }
        let dest = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MarkNote/plugins/\(srcDir.lastPathComponent)", isDirectory: true)
        try? FileManager.default.removeItem(at: dest)
        func copyDir(_ s: URL, _ d: URL) {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            for e in (try? FileManager.default.contentsOfDirectory(at: s, includingPropertiesForKeys: nil)) ?? [] {
                let dd = d.appendingPathComponent(e.lastPathComponent)
                if e.hasDirectoryPath { copyDir(e, dd) } else { try? FileManager.default.copyItem(at: e, to: dd) }
            }
        }
        copyDir(srcDir, dest)
        PluginManager.shared.scan(workspaceDir: store.notesDir)
        note = _L("已导入：\(srcDir.lastPathComponent)", "Imported: \(srcDir.lastPathComponent)")
        reload()
    }
}

/// 插件图标（图片优先 / 类型色 SF Symbol）
private extension View {
    @ViewBuilder
    func pluginIcon(_ pkg: PluginPackage, size: CGFloat) -> some View {
        if let url = pkg.iconURL, let img = NSImage(contentsOf: url) {
            Image(nsImage: img).resizable().scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.22)
                    .fill(PluginPackage.tint(for: pkg.kind).opacity(0.16))
                    .frame(width: size, height: size)
                Image(systemName: pkg.iconSymbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(PluginPackage.tint(for: pkg.kind))
            }
        }
    }
}

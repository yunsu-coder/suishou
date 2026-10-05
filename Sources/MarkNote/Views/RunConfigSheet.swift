import SwiftUI
import AppKit

/// 运行配置（第三方库 / 编译参数）—— IDE 的 `tasks.json` 图形版。
/// 装库仍走包管理器（brew / pip / npm / go / cargo），这里声明"用哪些库"。
struct RunConfigSheet: View {
    @Environment(NotesStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var libs = ""
    @State private var cxxFlags = ""
    @State private var linkFlags = ""
    @State private var python = ""
    @State private var saved = false

    private var workspace: URL { store.notesDir }
    private var project: (kind: ProjectKind, root: URL) {
        guard let id = store.selectedNoteID else { return (.single, workspace) }
        return ProjectKind.detect(from: workspace.appendingPathComponent(id), workspace: workspace)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox")
                    .foregroundStyle(appAppearance.accent)
                Text(_LL("运行配置（第三方库）", "Run Configuration (Libraries)"))
                    .font(.headline)
                Spacer()
                Text(project.kind.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
            }

            Text(_LL("说明：装库还是用包管理器 —— brew install fmt / pip install requests / npm install axios；这里只告诉「运行当前文件」怎么带上它们。",
                     "Installing still uses your package manager — brew install fmt / pip install requests / npm install axios. This panel only tells Run how to link them."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
                row(_L("第三方库（pkg-config 名，逗号分隔）", "Libraries (pkg-config names, comma separated)"),
                    text: $libs, hint: "fmt, sdl2")
                row(_L("编译参数", "Compile flags"), text: $cxxFlags, hint: "-std=c++20 -O2 -Wall")
                row(_L("链接参数", "Link flags"), text: $linkFlags, hint: "-framework Cocoa -lpthread")
                row(_L("Python 解释器（可空）", "Python interpreter (optional)"), text: $python, hint: "留空则优先用工作台 .venv")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(_LL("将要执行", "Will run"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(previewCommand)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                if saved {
                    Label(_L("已保存", "Saved"), systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Spacer()
                Button(_L("取消", "Cancel")) { dismiss() }
                Button(_L("保存", "Save")) { save() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 560)
        .onAppear(perform: load)
    }

    private func row(_ title: String, text: Binding<String>, hint: String) -> some View {
        GridRow {
            Text(title).font(.caption)
            TextField(hint, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
        }
    }

    private var parsed: RunConfig {
        var cfg = RunConfig.load(from: workspace)
        cfg.libs = split(libs)
        cfg.cxxFlags = split(cxxFlags)
        cfg.linkFlags = split(linkFlags)
        let py = python.trimmingCharacters(in: .whitespaces)
        cfg.python = py.isEmpty ? nil : py
        return cfg
    }

    private var previewCommand: String {
        guard let id = store.selectedNoteID else { return _L("先在左侧选中一个代码文件", "Select a code file on the left first") }
        let file = workspace.appendingPathComponent(id)
        return RunCommand.command(forExt: (id as NSString).pathExtension,
                                  file: file.path, workspace: workspace) ?? "—"
    }

    private func load() {
        let cfg = RunConfig.load(from: workspace)
        libs = cfg.libs.joined(separator: ", ")
        cxxFlags = cfg.cxxFlags.joined(separator: " ")
        linkFlags = cfg.linkFlags.joined(separator: " ")
        python = cfg.python ?? ""
    }

    private func save() {
        var cfg = RunConfig.load(from: workspace)   // 保留 commands 等其它字段
        let p = parsed
        cfg.libs = p.libs
        cfg.cxxFlags = p.cxxFlags
        cfg.linkFlags = p.linkFlags
        cfg.python = p.python
        do {
            try cfg.save(to: workspace)
            saved = true
            store.showHint(_L("运行配置已保存到 .marknote/run.json", "Run config saved to .marknote/run.json"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismiss() }
        } catch {
            store.showHint(_L("保存失败：\(error.localizedDescription)", "Save failed: \(error.localizedDescription)"))
        }
    }

    /// 逗号或空格分隔 → 数组
    private func split(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

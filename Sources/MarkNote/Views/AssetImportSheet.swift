import SwiftUI
import AppKit

/// 跨工作台导入素材：唯一的跨库通道 —— 用户显式勾选，**复制**进当前工作台，原库只读。
///
/// 规则（docs/05-内置插件库.md · 插件隔离规则）：
/// · 不建立跨工作台引用、不自动同步、不批量改名；
/// · 同名自动加序号（Workspace.uniqueName），绝不覆盖；
/// · 主题适配：颜色与字体全部取主题变量。
struct AssetImportSheet: View {
    @Environment(NotesStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// 确认导入：回调选中的文件 URL（由调用方执行复制并刷新）
    let onImport: ([URL]) -> Void

    @State private var picked: Set<String> = []
    @State private var query = ""

    private struct Group: Identifiable {
        let id: String          // 工作台路径
        let name: String
        let items: [NotesStore.AttachmentItem]
    }

    private var groups: [Group] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return store.otherWorkspaces.map { path in
            let all = NotesStore.scanAssets(in: URL(fileURLWithPath: path))
            let list = q.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(q) }
            return Group(id: path, name: URL(fileURLWithPath: path).lastPathComponent, items: list)
        }
        .filter { !$0.items.isEmpty }
    }

    private var pickedURLs: [URL] {
        groups.flatMap { g in g.items.filter { picked.contains($0.url.path) } }.map(\.url)
    }

    private var pickedSize: Int {
        groups.flatMap { g in g.items.filter { picked.contains($0.url.path) } }
            .reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if groups.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray").font(.system(size: 24)).foregroundStyle(.tertiary)
                    Text(query.isEmpty
                         ? _L("没有其他工作台，或它们还没有素材", "No other workspaces with assets")
                         : _L("没有匹配的素材", "Nothing matches"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(groups) { group in
                            Text(group.name + " · \(group.items.count) " + _L("个素材", "assets"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            ForEach(group.items) { item in
                                row(item)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            Divider()
            footer
        }
        .frame(width: 620, height: 520)
        .background(Color(nsColor: appAppearance.editorBackground))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(_L("从其他工作台导入素材", "Import assets from another workspace"))
                .font(.system(size: 15, weight: .semibold))
            Text(_L("勾选后会复制进 \(store.notesDir.lastPathComponent)，原工作台不会被修改；同名自动加序号。",
                    "Selected assets are copied into \(store.notesDir.lastPathComponent). The source workspace is never modified; name clashes get a suffix."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.tertiary)
                TextField(_L("搜索文件名（跨工作台）", "Search across workspaces"), text: $query)
                    .textFieldStyle(.plain).font(.system(size: 12))
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: appAppearance.surface ?? appAppearance.editorBackground)))
        }
        .padding(16)
    }

    private func row(_ item: NotesStore.AttachmentItem) -> some View {
        let on = picked.contains(item.url.path)
        return HStack(spacing: 10) {
            Image(systemName: on ? "checkmark.square.fill" : "square")
                .font(.system(size: 14))
                .foregroundStyle(on ? appAppearance.accent : Color.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: appAppearance.surface ?? appAppearance.editorBackground))
                if item.isImage, let img = NSImage(contentsOf: item.url) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    Image(systemName: AssetGridView.symbol(for: item.url.pathExtension))
                        .font(.system(size: 13)).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 36, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                Text(AssetGridView.sizeLabel(item.size) + "　·　" + folderOf(item))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: appAppearance.surface ?? appAppearance.editorBackground).opacity(0.6)))
        .contentShape(Rectangle())
        .onTapGesture {
            if on { picked.remove(item.url.path) } else { picked.insert(item.url.path) }
        }
    }

    private func folderOf(_ item: NotesStore.AttachmentItem) -> String {
        item.url.deletingLastPathComponent().lastPathComponent
    }

    private var footer: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(_L("已勾选 \(picked.count) 个 · 约 \(AssetGridView.sizeLabel(pickedSize))",
                        "\(picked.count) selected · ~\(AssetGridView.sizeLabel(pickedSize))"))
                    .font(.system(size: 12, weight: .medium))
                Text(_L("导入后这些素材属于当前工作台，可单独备份 / 搬走",
                        "Imported assets belong to the current workspace"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(_L("取消", "Cancel")) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(_L("导入 \(picked.count) 个", "Import \(picked.count)")) {
                onImport(pickedURLs)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(picked.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding(14)
    }
}

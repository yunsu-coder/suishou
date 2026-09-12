import SwiftUI
import AppKit

/// 素材网格 —— 视图插件 `assetGrid` 的内置渲染器（侧栏面板）。
///
/// 规则（docs/05-内置插件库.md · 插件隔离规则）：
/// · 只读**当前工作台** `source/` 下的资源；不扫描别的工作台；
/// · 引用计数只算当前工作台；不做批量改名；不删文件（删除仍走原有删除入口）；
/// · 主题适配：颜色与字体全部取主题变量。
struct AssetGridView: View {
    let spec: PluginView

    @Environment(NotesStore.self) private var store
    @State private var items: [NotesStore.AttachmentItem] = []
    @State private var refCounts: [String: Int] = [:]
    @State private var query = ""
    @State private var onlyUnreferenced = false
    @State private var selected: NotesStore.AttachmentItem?
    @State private var reloadToken = 0
    @State private var showImport = false
    /// 导入后的轻提示（几秒后自动消失）
    @State private var toast: String?

    private var filtered: [NotesStore.AttachmentItem] {
        var list = items
        if onlyUnreferenced { list = list.filter { (refCounts[$0.name] ?? 0) == 0 } }
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(q) } }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if filtered.isEmpty {
                emptyState
            } else {
                grid
            }
            if let sel = selected {
                Divider()
                footer(sel)
            }
        }
        .background(Color(nsColor: appAppearance.editorBackground))
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: PluginManager.changedNotification)) { _ in
            reload()
        }
        .sheet(isPresented: $showImport) {
            AssetImportSheet { urls in
                let result = store.importAssets(from: urls)
                reload()
                toast = result.failed == 0
                    ? _L("已导入 \(result.ok) 个素材到 \(store.notesDir.lastPathComponent)",
                         "Imported \(result.ok) asset(s) into \(store.notesDir.lastPathComponent)")
                    : _L("导入 \(result.ok) 个，失败 \(result.failed) 个",
                         "Imported \(result.ok), failed \(result.failed)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { toast = nil }
            }
            .environment(store)
        }
    }

    // MARK: - 顶部：标题 + 搜索 + 未引用筛选

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(_L("素材", "Assets") + " · " + store.notesDir.lastPathComponent)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Spacer()
                // 跨工作台只有一个通道：显式勾选导入（原库只读）
                if spec.options.allowImport == true, !store.otherWorkspaces.isEmpty {
                    Button {
                        showImport = true
                    } label: {
                        Text(_L("从其他工作台导入…", "Import…"))
                            .font(.system(size: 10))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 7)
                                .fill(appAppearance.accent.opacity(0.18)))
                            .foregroundStyle(appAppearance.accent)
                    }
                    .buttonStyle(.plain)
                    .help(_L("复制其他工作台的素材进来（不改动原库）",
                             "Copy assets from another workspace (source stays read-only)"))
                }
                Text("\(items.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            if let toast {
                Text(toast)
                    .font(.system(size: 10))
                    .foregroundStyle(appAppearance.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField(_L("搜索素材", "Search assets"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: appAppearance.surface ?? appAppearance.editorBackground)))
            HStack(spacing: 6) {
                chip(_L("全部", "All"), on: !onlyUnreferenced) { onlyUnreferenced = false }
                chip(_L("未被引用", "Unreferenced"), on: onlyUnreferenced) { onlyUnreferenced = true }
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 30)   // 避让交通灯
        .padding(.bottom, 8)
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(on ? appAppearance.accent.opacity(0.18) : Color.clear))
                .foregroundStyle(on ? appAppearance.accent : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 网格

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)], spacing: 8) {
                ForEach(filtered) { item in
                    tile(item)
                }
            }
            .padding(10)
        }
    }

    private func tile(_ item: NotesStore.AttachmentItem) -> some View {
        let isSel = selected?.url == item.url
        let refs = refCounts[item.name] ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: appAppearance.surface ?? appAppearance.editorBackground))
                if item.isImage, let img = NSImage(contentsOf: item.url) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: Self.symbol(for: item.url.pathExtension))
                        .font(.system(size: 20))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: 64)
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(isSel ? appAppearance.accent : Color(nsColor: appAppearance.editorForeground.withAlphaComponent(0.12)),
                        lineWidth: isSel ? 2 : 1))
            Text(item.name)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(Color(nsColor: appAppearance.editorForeground))
            Text(refs > 0 ? _L("引用 \(refs)", "Used \(refs)") : _L("未引用", "Unused"))
                .font(.system(size: 9))
                .foregroundStyle(refs > 0 ? .secondary : .tertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture { selected = item }
        .help("\(item.name) · \(Self.sizeLabel(item.size))")
    }

    // MARK: - 底部：选中素材的操作

    private func footer(_ item: NotesStore.AttachmentItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(Self.sizeLabel(item.size) + "　·　" + relativePath(item))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 8) {
                Button(_L("插入到光标处", "Insert")) { insert(item) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button(_L("复制引用", "Copy")) { copyRef(item) }
                    .controlSize(.small)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Image(systemName: "folder")
                }
                .controlSize(.small)
                .help(_L("在 Finder 中显示", "Reveal in Finder"))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text(items.isEmpty
                 ? _L("这个工作台还没有素材。把图片拖进笔记窗口就会自动进来。",
                      "No assets yet — drop an image into the window and it lands here.")
                 : _L("没有符合条件的素材", "Nothing matches"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 行为

    private func reload() {
        items = store.listAttachments(for: "")
        refCounts = store.assetReferenceCounts()
        if let sel = selected, !items.contains(where: { $0.url == sel.url }) { selected = nil }
        reloadToken += 1
    }

    /// 图相对当前工作台的路径（`source/image/x.png` → `img/x.png`，与短引用约定一致）。
    private func relativePath(_ item: NotesStore.AttachmentItem) -> String {
        let root = store.notesDir.path
        var rel = item.url.path
        if rel.hasPrefix(root) { rel = String(rel.dropFirst(root.count)) }
        rel = rel.hasPrefix("/") ? String(rel.dropFirst()) : rel
        return rel.replacingOccurrences(of: "source/image/", with: "img/")
    }

    /// 插入短引用：交给编辑器在光标处插入（通知解耦，编辑器不在时自动忽略）。
    private func insert(_ item: NotesStore.AttachmentItem) {
        let ref = "![\(Self.title(item.name))](\(relativePath(item)))"
        NotificationCenter.default.post(name: .insertTextAtCursor, object: ref)
    }

    private func copyRef(_ item: NotesStore.AttachmentItem) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString("![\(Self.title(item.name))](\(relativePath(item)))", forType: .string)
    }

    static func title(_ fileName: String) -> String {
        (fileName as NSString).deletingPathExtension
    }

    static func sizeLabel(_ bytes: Int) -> String {
        if bytes > 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / 1024 / 1024) }
        if bytes > 1024 { return String(format: "%.0f KB", Double(bytes) / 1024) }
        return "\(bytes) B"
    }

    static func symbol(for ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "doc.richtext"
        case "mp4", "mov", "m4v", "webm", "mkv": return "film"
        case "mp3", "m4a", "wav", "flac", "aac", "ogg": return "waveform"
        case "zip", "rar", "7z", "gz", "tar": return "archivebox"
        default: return "doc"
        }
    }
}

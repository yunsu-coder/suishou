import SwiftUI
import AppKit
import AVFoundation

/// 素材多选规则（纯函数，便于单测）：
/// 普通点击 = 单选；⌘ 点击 = 切换该项；⇧ 点击 = 选中与锚点之间的区间（连续 ⇧ 可继续扩）。
enum AssetSelection {
    static func apply(current: Set<String>, clicked: String, ordered: [String],
                      anchor: String?, command: Bool, shift: Bool) -> (selection: Set<String>, anchor: String) {
        if shift, let anchor,
           let a = ordered.firstIndex(of: anchor), let b = ordered.firstIndex(of: clicked) {
            let range = a <= b ? a...b : b...a
            return (Set(ordered[range]), anchor)
        }
        if command {
            var next = current
            if next.contains(clicked) { next.remove(clicked) } else { next.insert(clicked) }
            return (next, clicked)
        }
        return ([clicked], clicked)
    }
}

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
    /// 上方面板的大图（QuickLook 异步生成，避免在 body 里同步解码）
    @State private var previewImage: NSImage?
    /// 右侧「原图」：更大尺寸的 QuickLook 结果（4096 已覆盖任何屏幕的 1:1 查看）
    @State private var originalImage: NSImage?
    @State private var originalFit = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotionGrid
    /// 多选（批量删除用）：存 url.path
    @State private var selectedIDs: Set<String> = []
    /// ⇧ 区间选择的锚点
    @State private var selectionAnchor: String?
    @State private var reloadToken = 0
    @State private var showImport = false
    @State private var showCollector = false
    /// 导入后的轻提示（几秒后自动消失）
    @State private var toast: String?
    /// 待确认删除的素材（可单个、可批量；确认后再移入废纸篓）
    @State private var pendingTrash: [NotesStore.AttachmentItem] = []
    /// 大图 / 播放预览
    @State private var previewItem: NotesStore.AttachmentItem?

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
                // 参考用户的设计稿：左侧浏览器（工具条 / 平铺大预览 / 胶片条 / 信息操作条），
                // 右侧一整列专门看原图。面板太窄（例如挂在侧栏里）自动退回单列。
                GeometryReader { geo in
                    let twoPane = geo.size.width >= 620
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            previewPane
                            Divider()
                            strip
                            if let sel = selected {
                                Divider()
                                footer(sel)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        if twoPane, selected != nil {
                            Divider()
                            originalPane
                                .frame(minWidth: 300, idealWidth: 380)
                                .transition(AppMotion.panelTransition(reduceMotionGrid, edge: .trailing))
                        }
                    }
                    .animation(AppMotion.panel(reduceMotionGrid), value: selected?.id)
                }
            }
        }
        .background(Color(nsColor: appAppearance.editorBackground))
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: PluginManager.changedNotification)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .assetsChanged)) { _ in
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
        .sheet(isPresented: $showCollector) {
            CollectorView()
                .environment(store)
        }
        .sheet(item: $previewItem) { item in
            let kind = AssetSyntax.kind(forExt: item.url.pathExtension)
            MediaPreviewSheet(title: item.name,
                              subtitle: relativePath(item),
                              imageURL: kind == .image ? item.url : nil,
                              videoURL: kind == .video ? item.url : nil,
                              pageURL: nil)
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
                // 采集插件启用时出现：AI 找素材 → 候选勾选 → 入当前工作台素材库
                if PluginManager.shared.allViews().contains(where: { $0.type == .collector }) {
                    Button {
                        showCollector = true
                    } label: {
                        Text(_L("采集…", "Collect…"))
                            .font(.system(size: 10))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 7)
                                .fill(appAppearance.accent.opacity(0.18)))
                            .foregroundStyle(appAppearance.accent)
                    }
                    .buttonStyle(.plain)
                    .help(_L("描述你想要的素材，AI 帮你找（图片/视频）",
                             "Describe what you need and let AI find it (images/videos)"))
                }
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
                // 批量清理：选中 N 个一起删 / 一键清理当前列表里所有「未被引用」
                Button {
                    pendingTrash = unreferencedInList()
                    trashPending()
                } label: {
                    Text(_L("清理未引用", "Clean unused"))
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(unreferencedInList().isEmpty ? Color.secondary : appAppearance.accent)
                .disabled(unreferencedInList().isEmpty)
                .help(_L("把当前列表里所有未被引用的素材移到废纸篓",
                         "Move every unreferenced asset in the list to Trash"))
            }
            if !selectedIDs.isEmpty {
                HStack(spacing: 8) {
                    Text(_L("已选 \(selectedIDs.count) 个", "\(selectedIDs.count) selected"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(appAppearance.accent)
                    Spacer()
                    Button(_L("全选", "Select all")) {
                        selectedIDs = Set(filtered.map(\.id))
                        selectionAnchor = filtered.first?.id
                    }
                    .buttonStyle(.plain)
                    Button(_L("删除选中", "Delete selected"), role: .destructive) {
                        pendingTrash = filtered.filter { selectedIDs.contains($0.id) }
                        trashPending()
                    }
                    .buttonStyle(.plain)
                    Button(_L("取消选择", "Clear")) { clearSelection() }
                        .buttonStyle(.plain)
                }
                .font(.system(size: 10))
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

    // MARK: - 上：预览区（剪映式：选中什么就在这里看什么）

    private var previewPane: some View {
        ZStack {
            Color(nsColor: appAppearance.surface ?? appAppearance.editorBackground)
            if let item = selected {
                let kind = AssetSyntax.kind(forExt: item.url.pathExtension)
                if kind == .video {
                    // 本地视频直接放；远程的交给预览窗口（要带防盗链头先本地化）
                    if item.url.isFileURL {
                        MediaPlayerBox(url: item.url)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        previewPlaceholder(item, symbol: "play.rectangle")
                    }
                } else if kind == .image {
                    if let img = previewImage {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .padding(8)
                    } else {
                        previewPlaceholder(item, symbol: Self.symbol(for: item.url.pathExtension))
                    }
                } else {
                    previewPlaceholder(item, symbol: Self.symbol(for: item.url.pathExtension))
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 26))
                        .foregroundStyle(.tertiary)
                    Text(_LL("点下面的素材看大图", "Pick an asset below to preview"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 180)
        // 换素材时上面的预览交叉淡入，而不是"啪"地换一张
        .id(selected?.id ?? "none")
        .transition(.opacity)
        .animation(AppMotion.content(reduceMotionGrid), value: selected?.id)
        .contentShape(Rectangle())
        .task(id: selected?.id) {
            guard let item = selected, AssetSyntax.kind(forExt: item.url.pathExtension) == .image else {
                previewImage = nil
                originalImage = nil
                return
            }
            previewImage = await AssetThumbnail.image(for: item.url, maxPixel: 2048)
            originalImage = await AssetThumbnail.image(for: item.url, maxPixel: 4096)
            originalFit = true
        }
        .onTapGesture(count: 2) { if let item = selected { openPreview(item) } }
        .overlay(alignment: .topTrailing) {
            if let item = selected {
                let kind = AssetSyntax.kind(forExt: item.url.pathExtension)
                if kind == .image || kind == .video {
                    Button {
                        openPreview(item)
                    } label: {
                        Label(kind == .video ? _L("播放", "Play") : _L("看原图", "Full Size"),
                              systemImage: kind == .video ? "play.circle" : "arrow.up.left.and.arrow.down.right")
                            .font(.caption)
                    }
                    .controlSize(.small)
                    .padding(8)
                    .help(_L("打开大图预览（双击预览区同样可以）", "Open full preview (or double-click the preview)"))
                }
            }
        }
    }

    /// 右侧：原图查看（支持滚动；适应 / 100% 切换；双击此处开完整预览窗口）
    private var originalPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(_L("原图", "Original"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                if let img = originalImage {
                    let px = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
                        .map { "\($0.width)×\($0.height)" } ?? ""
                    Text(px)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button(originalFit ? _L("100%", "100%") : _L("适应", "Fit")) {
                    originalFit.toggle()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(appAppearance.accent)
                if let item = selected {
                    Button {
                        openPreview(item)
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .help(_L("打开完整预览（可 1:1 缩放）", "Open full preview (zoomable)"))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            Divider()
            ZStack {
                Color(nsColor: appAppearance.surface ?? appAppearance.editorBackground)
                if let img = originalImage, let item = selected {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: originalFit ? .infinity : nil, maxHeight: originalFit ? .infinity : nil)
                            .frame(width: originalFit ? nil : img.size.width,
                                   height: originalFit ? nil : img.size.height)
                            .padding(originalFit ? 8 : 0)
                    }
                    .id("\(item.id)-\(originalFit)")
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 22))
                            .foregroundStyle(.tertiary)
                        Text(_L("选一张图看原图", "Pick an image to inspect"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .background(Color(nsColor: appAppearance.surface ?? appAppearance.editorBackground))
    }

    private func previewPlaceholder(_ item: NotesStore.AttachmentItem, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text(item.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(_L("这个类型没有内嵌预览，用下面的「插入 / 复制 / Finder」处理",
                    "No inline preview for this type — use the buttons below"))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
    }

    // MARK: - 下：横向素材条（剪映式胶片条）

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            LazyHStack(spacing: 8) {
                ForEach(filtered) { item in
                    stripTile(item)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(height: 104)
    }

    private func stripTile(_ item: NotesStore.AttachmentItem) -> some View {
        let isSel = selectedIDs.contains(item.id)
        return VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: appAppearance.surface ?? appAppearance.editorBackground))
                AssetThumbView(item: item, symbol: Self.symbol(for: item.url.pathExtension))
                if isSel, selectedIDs.count > 1 {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(appAppearance.accent)
                        .padding(2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(width: 68, height: 62)
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(isSel ? appAppearance.accent : Color(nsColor: appAppearance.editorForeground.withAlphaComponent(0.12)),
                        lineWidth: isSel ? 2 : 1))
            Text(item.name)
                .font(.system(size: 9))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 68)
                .foregroundStyle(isSel ? Color.primary : Color.secondary)
        }
        .animation(AppMotion.item(reduceMotionGrid), value: isSel)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { selectedIDs = [item.id]; selectionAnchor = item.id; selected = item; openPreview(item) }
        .onTapGesture { select(item) }
        .onDrag {
            NSItemProvider(object: AssetSyntax.reference(name: item.name, path: relativePath(item)) as NSString)
        }
        .contextMenu { tileMenu(item) }
        .help("\(item.name) · \(Self.sizeLabel(item.size))")
    }


    /// 打开大图预览：图片/视频 → 预览窗口；其它类型 → 在 Finder 中显示
    private func openPreview(_ item: NotesStore.AttachmentItem) {
        let kind = AssetSyntax.kind(forExt: item.url.pathExtension)
        guard kind == .image || kind == .video else {
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
            return
        }
        previewItem = item
    }


    /// 选中一个素材（⌘/⇧ 多选）
    private func select(_ item: NotesStore.AttachmentItem) {
        let mods = NSEvent.modifierFlags
        let result = AssetSelection.apply(current: selectedIDs, clicked: item.id,
                                          ordered: filtered.map(\.id), anchor: selectionAnchor,
                                          command: mods.contains(.command),
                                          shift: mods.contains(.shift))
        selectedIDs = result.selection
        selectionAnchor = result.anchor
        selected = result.selection.contains(item.id) ? item : filtered.first { selectedIDs.contains($0.id) }
    }

    @ViewBuilder
    private func tileMenu(_ item: NotesStore.AttachmentItem) -> some View {
        let k = AssetSyntax.kind(forExt: item.url.pathExtension)
        if k == .image || k == .video {
            Button(k == .video ? _L("播放", "Play") : _L("预览大图", "Preview")) { openPreview(item) }
        }
        Button(_L("插入到光标处", "Insert")) { insert(item) }
        Button(_L("复制引用", "Copy Reference")) { copyRef(item) }
        Divider()
        Button(_L("在 Finder 中显示", "Reveal in Finder")) {
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        }
    }

    fileprivate final class PosterInfo: NSObject, @unchecked Sendable {
        let image: NSImage
        let duration: String?
        init(image: NSImage, duration: String?) {
            self.image = image
            self.duration = duration
            super.init()
        }
    }

    /// 首帧缓存：滚出/滚回视口不重复解码（按文件路径缓存，仅内存）。
    private static let posterCache = NSCache<NSString, PosterInfo>()

    /// 首帧（0.3s，避开片头黑帧）+ 时长文案；失败返回 nil（回退为类型图标）。
    fileprivate static func poster(for url: URL) async -> PosterInfo? {
        let key = url.path as NSString
        if let hit = posterCache.object(forKey: key) { return hit }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 360)
        let time = CMTime(seconds: 0.3, preferredTimescale: 600)
        let cg: CGImage? = await withCheckedContinuation { cont in
            generator.generateCGImageAsynchronously(for: time) { image, _, _ in
                cont.resume(returning: image)
            }
        }
        guard let cg else { return nil }
        var label: String?
        if let d = try? await asset.load(.duration) {
            let secs = CMTimeGetSeconds(d)
            if secs.isFinite, secs > 0 { label = durationLabel(secs) }
        }
        let info = PosterInfo(image: NSImage(cgImage: cg, size: .zero), duration: label)
        posterCache.setObject(info, forKey: key)
        return info
    }

    /// 秒 → 「3:05」/「1:02:03」
    static func durationLabel(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
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
                let kind = AssetSyntax.kind(forExt: item.url.pathExtension)
                if kind == .image || kind == .video {
                    Button {
                        previewItem = item
                    } label: {
                        Label(kind == .video ? _L("播放", "Play") : _L("预览", "Preview"),
                              systemImage: kind == .video ? "play.circle" : "plus.magnifyingglass")
                    }
                    .controlSize(.small)
                }
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
                Button {
                    pendingTrash = [item]
                    trashPending()
                } label: {
                    Image(systemName: "trash")
                }
                .controlSize(.small)
                .help(_L("删除素材（移到废纸篓）", "Delete asset (moves to Trash)"))
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
        NotificationCenter.default.post(name: .insertTextAtCursor,
                                        object: AssetSyntax.reference(name: item.name, path: relativePath(item)))
    }

    private func copyRef(_ item: NotesStore.AttachmentItem) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(AssetSyntax.reference(name: item.name, path: relativePath(item)), forType: .string)
    }

    /// 当前列表里「未被引用」的素材（清理用）
    private func unreferencedInList() -> [NotesStore.AttachmentItem] {
        filtered.filter { (refCounts[$0.name] ?? 0) == 0 }
    }

    private func clearSelection() {
        selectedIDs = []
        selectionAnchor = nil
        selected = nil
    }

    /// 删除确认文案：引用计数提示（被 N 篇笔记引用 → 引用会失效）+ 可恢复说明。
    private func batchDeleteWarning(_ list: [NotesStore.AttachmentItem]) -> String {
        let recover = _L("文件会移到废纸篓，可随时恢复。", "Files move to Trash and can be recovered.")
        let referenced = list.filter { (refCounts[$0.name] ?? 0) > 0 }.count
        if list.count == 1, let item = list.first {
            let refs = refCounts[item.name] ?? 0
            if refs > 0 {
                return _L("该素材被 \(refs) 篇笔记引用，删除后这些引用会失效。" + recover,
                          "Referenced by \(refs) note(s); those references will break. " + recover)
            }
            return _L("未被任何笔记引用。" + recover, "Not referenced by any note. " + recover)
        }
        if referenced > 0 {
            return _L("共 \(list.count) 个素材，其中 \(referenced) 个被笔记引用，删除后这些引用会失效。" + recover,
                      "\(list.count) assets, \(referenced) referenced by notes; those references will break. " + recover)
        }
        return _L("共 \(list.count) 个素材，都没有被笔记引用。" + recover,
                  "\(list.count) assets, none referenced by notes. " + recover)
    }

    /// 批量删除 → 逐个移到废纸篓（可恢复）；刷新网格与选中态。
    private func trashPending() {
        let list = pendingTrash
        pendingTrash = []
        var failed = 0
        for item in list where !store.trashAsset(item.url) { failed += 1 }
        clearSelection()
        reload()
        let okCount = list.count - failed
        if failed == 0 {
            toast = _L("已移到废纸篓 \(okCount) 个", "\(okCount) moved to Trash")
        } else {
            toast = _L("已移到废纸篓 \(okCount) 个，失败 \(failed) 个",
                       "\(okCount) moved, \(failed) failed")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { toast = nil }
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

/// 单个素材的缩略图单元：图片直接读；视频异步取首帧 + 时长角标；其余显示类型图标。
/// 缩略图状态放在子视图内部 —— 加载完成只刷新自己，**不触发整个网格重建**
/// （网格重建发生在拖拽会话开始时会让拖拽携带错误的素材引用）。
private struct AssetThumbView: View {
    let item: NotesStore.AttachmentItem
    let symbol: String
    @State private var poster: AssetGridView.PosterInfo?
    /// 图片缩略图：后台降采样（不再在主线程全量解码原图）
    @State private var thumbImage: NSImage?

    private var kind: AssetSyntax.Kind { AssetSyntax.kind(forExt: item.url.pathExtension) }

    var body: some View {
        ZStack {
            if let img = thumbImage {
                thumb(img)
            } else if kind == .video, let poster {
                thumb(poster.image)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(.tertiary)
            }
            if kind == .video {
                HStack(spacing: 3) {
                    Image(systemName: "play.fill").font(.system(size: 7))
                    if let d = poster?.duration {
                        Text(d).font(.system(size: 8, weight: .medium))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(0.58)))
                .padding(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .task(id: item.url) {
            // 缩略图：交给系统 QuickLook（图片 / 视频 / PDF / Office / 文本都能出图）；
            // 出不来再退回视频首帧或类型图标
            if thumbImage == nil {
                thumbImage = await AssetThumbnail.image(for: item.url, maxPixel: 512)
            }
            if kind == .video, poster == nil {
                poster = await AssetGridView.poster(for: item.url)
            }
        }
    }

    private func thumb(_ img: NSImage) -> some View {
        Image(nsImage: img)
            .resizable()
            .interpolation(.high)          // 降采样后的图再缩放也不发糊
            .antialiased(true)
            // 完整显示整张图（不裁切）——缩略图被裁掉一半时很像"图坏了"
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

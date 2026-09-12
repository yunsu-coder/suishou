import SwiftUI
import AppKit
import AVFoundation

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
        let kind = Self.kind(forExt: item.url.pathExtension)
        return VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: appAppearance.surface ?? appAppearance.editorBackground))
                AssetThumbView(item: item, symbol: Self.symbol(for: item.url.pathExtension))
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
        // 拖到编辑器：携带**短引用文本**（不是文件 URL —— 否则编辑器会再存一份素材）
        .onDrag {
            NSItemProvider(object: Self.reference(name: item.name, path: relativePath(item)) as NSString)
        }
        .help("\(item.name) · \(Self.sizeLabel(item.size))")
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
        NotificationCenter.default.post(name: .insertTextAtCursor,
                                        object: Self.reference(name: item.name, path: relativePath(item)))
    }

    private func copyRef(_ item: NotesStore.AttachmentItem) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(Self.reference(name: item.name, path: relativePath(item)), forType: .string)
    }

    /// 素材类型：决定插入语法、缩略图与图标策略。
    enum AssetKind: Equatable {
        case image, video, audio, file
    }

    static func kind(forExt ext: String) -> AssetKind {
        switch ext.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "avif", "tiff", "tif", "bmp", "svg":
            return .image
        case "mp4", "mov", "m4v", "mv4", "webm", "mkv", "avi":
            return .video
        case "mp3", "m4a", "wav", "flac", "aac", "ogg", "aiff":
            return .audio
        default:
            return .file
        }
    }

    /// 素材引用文本（插入 / 复制 / 拖拽三处共用一套写法）——按类型给**语义正确**的语法：
    /// · 图片 → `![名](路径)` 行内图片
    /// · 视频 → `<video src="路径" controls></video>` 预览内嵌播放器
    /// · 音频 → `<audio src="路径" controls></audio>` 预览内嵌播放器
    /// · 其他（pdf/zip/docx…）→ `@[名](路径)` 附件卡（点击打开）
    static func reference(name: String, path: String) -> String {
        let p = escapePath(path)
        switch kind(forExt: (name as NSString).pathExtension) {
        case .image: return "![\(title(name))](\(p))"
        case .video: return "<video src=\"\(p)\" controls></video>"
        case .audio: return "<audio src=\"\(p)\" controls></audio>"
        case .file:  return "@[\(title(name))](\(p))"
        }
    }

    /// 链接路径里的空格 / 括号 / # 等会破坏 Markdown 与附件卡语法解析 → 百分号编码（保留中文，便于阅读）。
    static func escapePath(_ path: String) -> String {
        var out = path
        for (raw, enc) in [(" ", "%20"), ("(", "%28"), (")", "%29"),
                           ("#", "%23"), ("[", "%5B"), ("]", "%5D")] {
            out = out.replacingOccurrences(of: raw, with: enc)
        }
        return out
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

    private var kind: AssetGridView.AssetKind { AssetGridView.kind(forExt: item.url.pathExtension) }

    var body: some View {
        ZStack {
            if item.isImage, let img = NSImage(contentsOf: item.url) {
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
            guard kind == .video, poster == nil else { return }
            poster = await AssetGridView.poster(for: item.url)
        }
    }

    private func thumb(_ img: NSImage) -> some View {
        Image(nsImage: img)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

import AppKit
import QuickLookThumbnailing

/// 素材缩略图 —— 用 **macOS 自带的 QuickLook**（Finder / 访达预览用的同一套），
/// 而不是自己 ImageIO/AVAssetImageGenerator 拼：
/// - 图片、视频、PDF、Office 文档、文本…… 系统都认，缩略图质量与 Finder 一致
/// - 自动应用 EXIF 方向、自动处理 HDR/宽色域、自带高 DPI（scale 直接给屏幕倍率）
/// - 生成在系统侧完成，主线程不做解码
/// 我们只做两件事：按「路径 + 修改时间 + 尺寸 + 倍率」缓存，以及把异步结果交回 SwiftUI。
enum AssetThumbnail {

    private static let cache = NSCache<NSString, NSImage>()

    /// 同步命中缓存用（视图 body 里可以直接读，不触发异步）
    static func cached(for url: URL, maxPixel: CGFloat) -> NSImage? {
        cache.object(forKey: key(url, maxPixel))
    }

    /// 取缩略图（异步；QuickLook 生成）。maxPixel = 最长边像素目标值。
    static func image(for url: URL, maxPixel: CGFloat) async -> NSImage? {
        let k = key(url, maxPixel)
        if let hit = cache.object(forKey: k) { return hit }

        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2 }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: maxPixel / scale, height: maxPixel / scale),   // 点为单位，×scale = 像素
            scale: scale,
            representationTypes: .all
        )
        let image: NSImage? = await withCheckedContinuation { cont in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                guard let rep else { cont.resume(returning: nil); return }
                cont.resume(returning: rep.nsImage)
            }
        }
        if let image { cache.setObject(image, forKey: k) }
        return image
    }

    static func clearCache() { cache.removeAllObjects() }

    private static func key(_ url: URL, _ maxPixel: CGFloat) -> NSString {
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate)?.timeIntervalSince1970 ?? 0
        return "\(url.path)|\(Int(mtime))|\(Int(maxPixel))" as NSString
    }
}

import AppKit
import ImageIO

/// 素材缩略图：**降采样**而不是把原图塞进小格子。
///
/// 之前网格里是 `NSImage(contentsOf:)` 读原图：
/// - 一张 4000×3000 的照片每次都要全量解码（网格滑动直接卡）
/// - 让 SwiftUI 自己缩到 120px，边缘发糊
/// - 手机竖拍的照片还可能因为没走 EXIF 方向而躺着
///
/// 换成 ImageIO 的缩略图 API：只解码到目标尺寸、顺带应用 EXIF 方向，并按
/// 「路径 + 修改时间 + 尺寸」缓存。大图小图都用它，预览大图另有原图通道。
enum AssetThumbnail {

    private static let cache = NSCache<NSString, NSImage>()

    /// 取缩略图（同步；调用方放到后台线程）。maxPixel = 最长边像素。
    static func image(for url: URL, maxPixel: CGFloat = 512) -> NSImage? {
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)|\(Int(mtime))|\(Int(maxPixel))" as NSString
        if let hit = cache.object(forKey: key) { return hit }

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // EXIF 方向（竖拍不再躺着）
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(img, forKey: key)
        return img
    }

    /// 只清内存缓存（换工作台/刷新素材时用）
    static func clearCache() { cache.removeAllObjects() }
}

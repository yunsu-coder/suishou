import XCTest
import AppKit
@testable import MarkNote

/// 素材缩略图：降采样（不读原图）+ 缓存 + EXIF 方向交给 ImageIO
final class AssetThumbnailTests: XCTestCase {

    /// 造一张 1200×800 的测试图，验证缩略图最长边被压到 maxPixel 以内
    private func makeTempImage() throws -> URL {
        let size = NSSize(width: 1200, height: 800)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.systemTeal.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.systemOrange.setFill()
        NSRect(x: 0, y: 0, width: 400, height: 400).fill()
        img.unlockFocus()
        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw XCTSkip("无法生成测试图片")
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("asset-thumb-\(UUID().uuidString).png")
        try png.write(to: url)
        return url
    }

    /// 用真实 CGImage 像素尺寸判断（NSImage.pixelSize 在 Retina 下会报 2× 点数，不代表解码尺寸）
    private func cgSize(_ img: NSImage) -> CGSize {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .zero }
        return CGSize(width: cg.width, height: cg.height)
    }

    @MainActor
    func testDownsamplesToRequestedMaxPixel() async throws {
        let url = try makeTempImage()
        defer { try? FileManager.default.removeItem(at: url) }
        let thumb0 = await AssetThumbnail.image(for: url, maxPixel: 256)
        let thumb = try XCTUnwrap(thumb0)
        let px = cgSize(thumb)
        XCTAssertLessThanOrEqual(max(px.width, px.height), 256.5, "最长边应压到 256 以内，实际 \(px)")
        XCTAssertEqual(px.width / px.height, 1.5, accuracy: 0.02, "宽高比保持不变")
    }

    @MainActor
    func testCacheReturnsSameInstance() async throws {
        let url = try makeTempImage()
        defer { try? FileManager.default.removeItem(at: url) }
        let a0 = await AssetThumbnail.image(for: url, maxPixel: 128)
        let b0 = await AssetThumbnail.image(for: url, maxPixel: 128)
        let a = try XCTUnwrap(a0)
        let b = try XCTUnwrap(b0)
        XCTAssertTrue(a === b, "同样参数应命中缓存，返回同一实例")
        let c0 = await AssetThumbnail.image(for: url, maxPixel: 64)
        let c = try XCTUnwrap(c0)
        XCTAssertFalse(a === c, "不同尺寸是不同缓存条目")
        let cs = cgSize(c)
        XCTAssertLessThanOrEqual(max(cs.width, cs.height), 64.5)
    }

    /// QuickLook 连文本都能出缩略图（系统能力）；这里只保证"不认识的二进制"不会崩
    @MainActor
    func testUnknownBinaryDoesNotCrash() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("junk-\(UUID().uuidString).bin")
        try Data(repeating: 0xAB, count: 4096).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        _ = await AssetThumbnail.image(for: url, maxPixel: 128)   // 允许 nil，允许系统给个通用图标
    }
}

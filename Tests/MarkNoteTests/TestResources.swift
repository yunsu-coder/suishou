import Foundation
#if canImport(XCTest)
import XCTest
#endif

/// 测试用的构建产物定位。
///
/// SPM 的产物布局会随工具链/构建方式变化（`.build/arm64-apple-macosx/debug/…`
/// ↔ `.build/out/Products/Debug/…`），预览渲染类测试写死单一路径会集体“假失败”。
/// 这里按候选路径探测 + 有界扫描兜底，只为拿到真实的 `MarkNote_MarkNote.bundle`。
enum TestResources {

    /// 仓库根目录（本文件位于 `<root>/Tests/MarkNoteTests/`）
    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // MarkNoteTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // <root>

    /// 资源包（MarkNote_MarkNote.bundle）目录；找不到返回 nil
    static func appResourceBundle() -> URL? {
        let candidates = [
            ".build/out/Products/Debug/MarkNote_MarkNote.bundle",
            ".build/out/Products/Release/MarkNote_MarkNote.bundle",
            ".build/arm64-apple-macosx/debug/MarkNote_MarkNote.bundle",
            ".build/arm64-apple-macosx/release/MarkNote_MarkNote.bundle",
            ".build/x86_64-apple-macosx/debug/MarkNote_MarkNote.bundle",
            ".build/debug/MarkNote_MarkNote.bundle",
        ]
        for rel in candidates {
            let url = repoRoot.appendingPathComponent(rel)
            if previewIndex(in: url) != nil { return url }
        }
        // 兜底：构建布局再变时，在 .build 下做一次有界深度扫描
        return scanForBundle(in: repoRoot.appendingPathComponent(".build"), depth: 6)
    }

    /// 预览资源目录（含 preview.html / preview.js / preview.css / renders / vendor）
    static func previewResources() -> URL? {
        guard let bundle = appResourceBundle() else { return nil }
        return previewIndex(in: bundle)
    }

    /// 预览资源目录缺失时抛 XCTSkip（而不是让整组测试红给你看）
    static func requirePreviewResources() throws -> URL {
        guard let dir = previewResources() else {
            throw XCTSkip("预览资源包未构建：.build 下找不到含 preview.html 的 MarkNote_MarkNote.bundle（先 swift build）")
        }
        return dir
    }

    // MARK: - 私有

    /// 资源包内 preview.html 所在目录（不同布局：bundle/Resources 或 bundle/Contents/Resources/Resources）
    private static func previewIndex(in bundle: URL) -> URL? {
        let probes = [
            bundle.appendingPathComponent("Contents/Resources/Resources", isDirectory: true),
            bundle.appendingPathComponent("Resources", isDirectory: true),
        ]
        return probes.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("preview.html").path)
        }
    }

    private static func scanForBundle(in dir: URL, depth: Int) -> URL? {
        guard depth > 0 else { return nil }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        for e in entries where e.lastPathComponent.hasSuffix("MarkNote_MarkNote.bundle") {
            if previewIndex(in: e) != nil { return e }
        }
        for e in entries where (try? e.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            if let hit = scanForBundle(in: e, depth: depth - 1) { return hit }
        }
        return nil
    }
}

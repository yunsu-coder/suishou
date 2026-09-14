import XCTest
@testable import MarkNote

/// 真机网络测试（默认跳过；`RUN_NET_TESTS=1 swift test` 才跑）：
/// B 站解析 → 下载 → 落进 source/mp4，证明「视频能变成本地视频」这条链路真的通。
final class CollectorVideoLiveTests: XCTestCase {

    @MainActor
    func testBilibiliResolveAndDownloadToLocalVideo() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_NET_TESTS"] != nil,
                          "网络测试默认跳过（设置 RUN_NET_TESTS=1 再跑）")
        let page = try XCTUnwrap(URL(string: "https://www.bilibili.com/video/BV1cL411V7Nf/"))
        let resolved = await CollectorVideoResolver.resolve(pageURL: page)
        let r = try XCTUnwrap(resolved, "B 站应能解析出直链")
        print("LIVE resolved quality=\(r.quality ?? "-") host=\(r.url.host ?? "-")")
        XCTAssertTrue(r.url.absoluteString.hasPrefix("http"))

        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let rel = await store.downloadCollectedVideo(from: r.url, preferredName: "城市夜景", referer: page)
        let relPath = try XCTUnwrap(rel, "应能下载到 source/mp4")
        print("LIVE downloaded rel=\(relPath) quality=\(r.quality ?? "-")")
        let file = dir.appendingPathComponent(relPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "本地视频文件要真的存在")
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        XCTAssertGreaterThan(size ?? 0, 100 * 1024, "本地视频不该是空文件")
        // 收藏条目里要带上本地路径
        XCTAssertTrue(store.appendVideoFavorite(title: "城市夜景", pageURL: page, duration: "03:34",
                                                coverRel: nil, localRel: relPath))
        let fav = try String(contentsOf: dir.appendingPathComponent("视频收藏.md"), encoding: .utf8)
        XCTAssertTrue(fav.contains(relPath), "收藏条目要记录本地视频路径")
    }
}

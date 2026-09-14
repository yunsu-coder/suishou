import XCTest
@testable import MarkNote

/// 真机网络诊断（默认跳过，`RUN_NET_TESTS=1 swift test --filter CollectorImageLiveTests` 才跑）：
/// 走一遍「Bing 图片搜索 → 下载前几张大图」，把**每条的结果与失败原因**打出来。
/// 用途：用户报「选了 4 个只下来 2 个」时，能当场看见另外 2 个卡在哪一步。
@MainActor
final class CollectorImageLiveTests: XCTestCase {

    func testBingImageSearchDownloadDiagnostics() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_NET_TESTS"] != nil,
                          "网络测试默认跳过（设置 RUN_NET_TESTS=1 再跑）")
        let query = ProcessInfo.processInfo.environment["LIVE_QUERY"] ?? "三体动画实景 写实摄影 横图 1080p"
        let candidates = await CollectorSearch.searchImages(query: query, count: 12)
        print("LIVE candidates=\(candidates.count) query=\(query)")
        XCTAssertFalse(candidates.isEmpty, "Bing 应该能搜到候选")

        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        var saved = 0
        var failed: [String] = []
        for (i, c) in candidates.prefix(6).enumerated() {
            let name = "诊断\(i + 1)"
            let result = await store.downloadCollectedImage(from: c.fullURL ?? c.thumbURL ?? c.pageURL!,
                                                            preferredName: name, referer: c.pageURL)
            switch result {
            case .saved(let rel):
                saved += 1
                print("LIVE [\(i + 1)] OK \(rel)  ← \(c.fullURL?.host ?? "-")")
            case .failed(let why):
                failed.append("\(i + 1): \(why)")
                print("LIVE [\(i + 1)] FAIL \(why)  ← \(c.fullURL?.host ?? "-") \(c.fullURL?.absoluteString ?? "-")")
            }
        }
        print("LIVE 结果：成功 \(saved) / 尝试 \(min(6, candidates.count))；失败原因：\(failed)")
        XCTAssertGreaterThan(saved, 0, "至少该下来一张（否则是整条链路的问题）")
    }
}

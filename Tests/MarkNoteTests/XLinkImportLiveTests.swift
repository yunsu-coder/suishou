import XCTest
@testable import MarkNote

/// 贴链接导入的**真机验证**（需系统代理已开；X 在国内直连不可达）。
///
///   RUN_NET_TESTS=1 swift test --filter XLinkImportLiveTests
///   RUN_NET_TESTS=1 LIVE_X_URL="https://x.com/某人/status/123…" swift test --filter XLinkImportLiveTests
///
/// 会读取本机 App 里的 X 登录 cookie（只复制到测试进程，不打印内容）。
@MainActor
final class XLinkImportLiveTests: XCTestCase {

    func testFetchXPageAndExtractMedia() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_NET_TESTS"] != nil,
                          "网络测试默认跳过（RUN_NET_TESTS=1）")
        // 1) 把 App 的 X 登录态复制到测试进程（真实使用时 app 内本来就有）
        if let appDefaults = UserDefaults(suiteName: "com.gzhysu.marknote"),
           let cookie = CollectAccountStore(defaults: appDefaults).cookie("x") {
            UserDefaults.standard.set(cookie, forKey: "collectorCookie.x")
            print("LIVE-X 已带上本机 X 登录态（长度 \(cookie.count)，不打印内容）")
        } else {
            print("LIVE-X 本机没有 X 登录态，按游客抓（部分内容会看不到）")
        }
        defer { UserDefaults.standard.removeObject(forKey: "collectorCookie.x") }

        // 2) 抓一个 X 页面：默认用官方账号主页（无需具体帖子也能验证链路）
        let target = ProcessInfo.processInfo.environment["LIVE_X_URL"] ?? "https://x.com/X"
        let url = try XCTUnwrap(URL(string: target))
        let plain = await CollectorSearch.fetch(url)
        print("LIVE-X 普通抓取：\(plain.map { "\($0.count) 字节" } ?? "失败")")
        if let plain {
            let media = CollectorLinkImport.mediaURLs(inHTML: plain, base: url)
            print("LIVE-X 普通抓取解析：video=\(media.video?.host ?? "-") image=\(media.image?.host ?? "-")")
        }

        // 3) 走完整入口（普通抓不到会自动用应用内浏览器渲染一遍）
        let candidate = await CollectorLinkImport.candidate(for: url)
        print("LIVE-X 候选：kind=\(candidate?.kind ?? "-") title=\(candidate?.title.prefix(40) ?? "-")"
              + " thumb=\(candidate?.thumbURL?.host ?? "-") video=\(candidate?.videoURL?.host ?? "-")")
        let rendered = await CollectorWebRender.render(url, minChars: 200, timeout: 20)
        print("LIVE-X 应用内浏览器渲染：\(rendered.map { "\($0.count) 字节" } ?? "失败")")
        if let rendered {
            let media = CollectorLinkImport.mediaURLs(inHTML: rendered, base: url)
            print("LIVE-X 渲染后解析：video=\(media.video?.absoluteString.prefix(70) ?? "-")"
                  + " image=\(media.image?.absoluteString.prefix(70) ?? "-")")
        }
        XCTAssertTrue(plain != nil || rendered != nil, "开着代理时至少有一条路径能取到页面")
    }

    /// 登录态时间线里能不能看到媒体直链（LIVE_X_TIMELINE=1 才跑）
    func testHomeTimelineContainsMediaDirectLinks() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_NET_TESTS"] != nil
                          && ProcessInfo.processInfo.environment["LIVE_X_TIMELINE"] != nil,
                          "需要 RUN_NET_TESTS=1 且 LIVE_X_TIMELINE=1")
        if let appDefaults = UserDefaults(suiteName: "com.gzhysu.marknote"),
           let cookie = CollectAccountStore(defaults: appDefaults).cookie("x") {
            UserDefaults.standard.set(cookie, forKey: "collectorCookie.x")
        }
        defer { UserDefaults.standard.removeObject(forKey: "collectorCookie.x") }
        let url = try XCTUnwrap(URL(string: "https://x.com/home"))
        guard let html = await CollectorWebRender.render(url, minChars: 500, timeout: 25) else {
            return XCTFail("渲染失败（确认系统代理已开）")
        }
        let videoHosts = html.ranges(of: "video.twimg.com").count
        let photoCount = html.ranges(of: "pbs.twimg.com/media").count
        print("LIVE-X 时间线渲染 \(html.count) 字节 · video.twimg 出现 \(videoHosts) 次 · media 图 \(photoCount) 次")
        let media = CollectorLinkImport.mediaURLs(inHTML: html, base: url)
        print("LIVE-X 时间线解析：video=\(media.video?.absoluteString.prefix(90) ?? "-")"
              + " image=\(media.image?.absoluteString.prefix(80) ?? "-")")
        XCTAssertGreaterThan(videoHosts + photoCount, 0, "登录态下应能看到媒体直链")
        // 说明：时间线里出现的 video.twimg.com 多半是 CSP 白名单；真正的帖子媒体要打开单条帖子页才拿得到，
        // 所以这里只做信息输出，不断言（单条帖子的解析由 unit test + 手动贴链接验证）。
    }
}

private extension String {
    /// 子串出现次数（诊断用）
    func ranges(of needle: String) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        var start = startIndex
        while let r = range(of: needle, range: start..<endIndex) {
            out.append(r)
            start = r.upperBound
        }
        return out
    }
}

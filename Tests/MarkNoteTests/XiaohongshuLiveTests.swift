import XCTest
import WebKit
@testable import MarkNote

/// 小红书专用接口实测（页面内签名请求）：搜索笔记 + 取笔记图集。
///
/// 需要本机 App 里登录过小红书；测试进程有自己的 WebKit store，
/// 所以这里把 App 存的 cookie **注入测试进程**再跑（只读 App 的 cookie，不打印内容）。
///   RUN_NET_TESTS=1 LIVE_APP_COOKIES=1 swift test --filter XiaohongshuLiveTests
@MainActor
final class XiaohongshuLiveTests: XCTestCase {

    func testSearchThenFetchNoteImages() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_NET_TESTS"] != nil,
                          "网络测试默认跳过")
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LIVE_APP_COOKIES"] != nil,
                          "需要本机登录 cookie（LIVE_APP_COOKIES=1）")
        guard let defaults = UserDefaults(suiteName: "com.gzhysu.marknote"),
              let header = CollectAccountStore(defaults: defaults).cookie("xiaohongshu") else {
            throw XCTSkip("本机没登录小红书，跳过")
        }
        await inject(cookieHeader: header, domain: ".xiaohongshu.com")

        let keyword = ProcessInfo.processInfo.environment["LIVE_XHS_KEYWORD"] ?? "露营装备 分享"
        let hits = await XiaohongshuAPI.search(keyword: keyword, count: 12)
        print("LIVE-XHS 搜索「\(keyword)」→ \(hits.count) 条")
        for c in hits.prefix(6) {
            print("LIVE-XHS   \(c.title.prefix(36)) · \(c.metaLine ?? "-") · \(c.pageURL?.absoluteString.prefix(60) ?? "-")")
        }
        XCTAssertFalse(hits.isEmpty, "登录后小红书搜索接口该有结果（空 = 签名/登录态没生效）")

        guard let first = hits.first else { return }
        let token = first.pageURL?.query?.split(separator: "&")
            .first { $0.hasPrefix("xsec_token=") }?
            .split(separator: "=").last.map(String.init)
        var images = await XiaohongshuAPI.noteImages(noteID: first.id, xsecToken: token)
        if images.isEmpty {
            print("LIVE-XHS 接口方式没拿到，改用「点开笔记」方式")
            images = await XiaohongshuAPI.noteImagesByClicking(noteID: first.id, keyword: keyword)
        }
        print("LIVE-XHS 笔记「\(first.title.prefix(24))」→ \(images.count) 张图（token \(token == nil ? "无" : "有")）")
        for u in images.prefix(3) { print("LIVE-XHS   \(u.host ?? "-") \(u.absoluteString.prefix(70))") }
        XCTAssertFalse(images.isEmpty, "笔记详情该能取到图片列表")
    }

    /// 把 cookie 头注入测试进程的 WebKit store（页面上下文才带得上登录态）
    private func inject(cookieHeader: String, domain: String) async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        for pair in cookieHeader.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2, !parts[0].isEmpty else { continue }
            guard let cookie = HTTPCookie(properties: [
                .name: parts[0], .value: parts[1], .domain: domain, .path: "/", .secure: "TRUE",
            ]) else { continue }
            await withCheckedContinuation { cont in
                store.setCookie(cookie) { cont.resume() }
            }
        }
    }
}

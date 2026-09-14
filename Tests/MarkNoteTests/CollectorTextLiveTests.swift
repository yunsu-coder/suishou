import XCTest
@testable import MarkNote

/// 真机网络诊断（默认跳过，`RUN_NET_TESTS=1 swift test --filter CollectorTextLiveTests` 才跑）：
/// 走一遍「网页搜索 → 打开页面 → 提正文 / 抽章节」，把结果打出来，
/// 用来确认真实站点上「文章→.md」「小说→.md」这两条链路真的能用。
@MainActor
final class CollectorTextLiveTests: XCTestCase {

    func testArticleFetchAndConvert() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_NET_TESTS"] != nil,
                          "网络测试默认跳过（设置 RUN_NET_TESTS=1 再跑）")
        let query = ProcessInfo.processInfo.environment["LIVE_ARTICLE_QUERY"] ?? "三体 黑暗森林 结构分析 长文"
        let found = await CollectorSearch.searchWeb(query: query, count: 12)
        print("LIVE-ARTICLE candidates=\(found.count)")
        var ok = 0
        for c in found.prefix(4) {
            guard let page = c.pageURL else { continue }
            guard let html = await CollectorSearch.fetch(page) else {
                print("LIVE-ARTICLE [\(page.host ?? "-")] 打不开")
                continue
            }
            let md = HTMLToMarkdown.convert(html, baseURL: page)
            let words = HTMLToMarkdown.wordCount(md)
            print("LIVE-ARTICLE [\(page.host ?? "-")] \(words) 字 · \(md.prefix(60).replacingOccurrences(of: "\n", with: " "))")
            if words >= 200 {
                print("LIVE-ARTICLE 正文开头：\n\(md.prefix(500))")
            }
            if words >= 200 { ok += 1 }
        }
        XCTAssertGreaterThan(ok, 0, "至少该有一篇能提出 200 字以上正文")
    }

    func testNovelIndexChaptersAndFirstChapter() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_NET_TESTS"] != nil,
                          "网络测试默认跳过（设置 RUN_NET_TESTS=1 再跑）")
        let query = ProcessInfo.processInfo.environment["LIVE_NOVEL_QUERY"] ?? "三体 小说 在线阅读 目录"
        let found = await CollectorSearch.searchWeb(query: query, count: 12)
        for c in found.prefix(6) {
            guard let page = c.pageURL, let html = await CollectorSearch.fetch(page) else { continue }
            let chapters = NovelCollector.chapters(inHTML: html, base: page)
            print("LIVE-NOVEL [\(page.host ?? "-")] \(c.title.prefix(24)) → 章节 \(chapters.count)")
            guard chapters.count >= 3 else { continue }
            let first = chapters[0]
            guard let chHTML = await CollectorSearch.fetch(first.url) else {
                print("LIVE-NOVEL 第一章打不开：\(first.url)")
                continue
            }
            let body = HTMLToMarkdown.convert(chHTML, baseURL: first.url)
            let words = HTMLToMarkdown.wordCount(body)
            print("LIVE-NOVEL 第一章「\(first.title)」→ \(words) 字\n\(body.prefix(120))")
            XCTAssertGreaterThan(words, 200, "第一章正文该有 200 字以上")
            return
        }
        XCTSkip("这轮搜索里没找到能解析出章节目录的站点（网络/站点结构问题，不算失败）")
    }

    /// 诊断：把搜索结果原样打出来（标题 / 站点 / 章节数），用来调搜索词
    func testPrintSearchResults() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LIVE_DIAG"] != nil,
                          "诊断用，设置 LIVE_DIAG=1 才跑")
        let queries = (ProcessInfo.processInfo.environment["LIVE_DIAG_QUERIES"] ?? "三体 小说 在线阅读 目录")
            .components(separatedBy: "|")
        for q in queries {
            let found = await CollectorSearch.searchWeb(query: q, count: 12)
            print("LIVE-DIAG 查询「\(q)」→ \(found.count) 条")
            for c in found.prefix(10) {
                var chapters = 0
                if let page = c.pageURL, let html = await CollectorSearch.fetch(page) {
                    chapters = NovelCollector.chapters(inHTML: html, base: page).count
                }
                print("LIVE-DIAG   [\(c.pageURL?.host ?? "-")] 章\(chapters) · \(c.kind) · \(c.title.prefix(40))")
            }
        }
    }

    /// 诊断：搜狗这条路到底卡在哪（抓不到页面 / 解析不出块 / 解不出真实地址）
    func testSogouDiagnostics() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LIVE_DIAG"] != nil,
                          "诊断用，设置 LIVE_DIAG=1 才跑")
        let query = ProcessInfo.processInfo.environment["LIVE_NOVEL_QUERY"] ?? "三体 小说 在线阅读"
        var comp = URLComponents(string: "https://www.sogou.com/web")!
        comp.queryItems = [.init(name: "query", value: query)]
        guard let url = comp.url else { return XCTFail("URL 坏了") }
        guard let html = await CollectorSearch.fetch(url) else {
            print("LIVE-SOGOU 抓不到页面 \(url)")
            return
        }
        print("LIVE-SOGOU 页面 \(html.count) 字节 · 含 vr-title：\(html.contains("vr-title"))")
        print("LIVE-SOGOU 开头：\(html.prefix(300).replacingOccurrences(of: "\n", with: " "))")
        // 先访问首页拿 cookie 再搜（很多站这样才给正常结果）
        _ = await CollectorSearch.fetch(URL(string: "https://www.sogou.com/")!)
        if let again = await CollectorSearch.fetch(url) {
            print("LIVE-SOGOU 带 cookie 再来：\(again.count) 字节 · 含 vr-title：\(again.contains("vr-title"))")
            print("LIVE-SOGOU 开头：\(again.prefix(200).replacingOccurrences(of: "\n", with: " "))")
        }
        let parsed = CollectorSearch.parseSogouResults(html)
        print("LIVE-SOGOU 解析出 \(parsed.count) 条")
        for c in parsed.prefix(5) {
            print("LIVE-SOGOU   [\(c.sourceLabel ?? "-")] \(c.kind) · \(c.title.prefix(40)) · \(c.pageURL?.absoluteString.prefix(60) ?? "-")")
        }
        let resolved = await CollectorSearch.resolveRedirectLinks(parsed, referer: url)
        for c in resolved.prefix(5) {
            print("LIVE-SOGOU 解出 → [\(c.sourceLabel ?? "-")] \(c.pageURL?.absoluteString.prefix(70) ?? "-")")
        }
    }
}

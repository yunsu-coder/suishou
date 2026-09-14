import XCTest
@testable import MarkNote

/// 真机实测：**登录到底让采集好多少** —— 同一批页面分别用「游客」与「你本机的登录 cookie」抓一次，
/// 对比正文提取字数 / 图片数 / 是否撞登录墙。
///
/// 只在 `LIVE_APP_COOKIES=1` 时跑（会读取本机 App 的登录 cookie，但**只读不打印**内容）。
///   RUN_NET_TESTS=1 LIVE_APP_COOKIES=1 swift test --filter CollectorLoginEffectLiveTests
@MainActor
final class CollectorLoginEffectLiveTests: XCTestCase {

    /// 读 App 自己的 UserDefaults 域（测试进程的 standard 是另一个域，读不到真实登录）
    private var appStore: CollectAccountStore? {
        guard let defaults = UserDefaults(suiteName: "com.gzhysu.marknote") else { return nil }
        return CollectAccountStore(defaults: defaults)
    }

    private struct Probe {
        var site: String
        var url: URL
    }

    func testGuestVsLoggedIn() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_NET_TESTS"] != nil,
                          "网络测试默认跳过（RUN_NET_TESTS=1）")
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LIVE_APP_COOKIES"] != nil,
                          "需要本机登录 cookie（LIVE_APP_COOKIES=1）")
        guard let store = appStore else { return XCTFail("读不到 App 的 UserDefaults 域") }

        // 每个站搜一条真实页面（用采集器自己的搜索链路）
        let queries: [(site: String, query: String)] = [
            ("juejin.cn", "site:juejin.cn 前端性能优化 实践"),
            ("sspai.com", "site:sspai.com 效率工具 评测"),
            ("douban.com", "site:douban.com 书评 长文"),
            ("zhuanlan.zhihu.com", "site:zhuanlan.zhihu.com 深度长文"),
            ("xiaohongshu.com", "site:xiaohongshu.com/explore 笔记 分享"),
        ]
        var probes: [Probe] = []
        // 指定 URL 直接测（LIVE_PROBE_URLS="https://a,https://b"），否则按站点搜一条
        if let raw = ProcessInfo.processInfo.environment["LIVE_PROBE_URLS"], !raw.isEmpty {
            for s in raw.split(separator: ",") {
                let t = s.trimmingCharacters(in: .whitespaces)
                if let u = URL(string: t) { probes.append(Probe(site: u.host ?? "-", url: u)) }
            }
        } else {
            for q in queries {
                let found = await CollectorSearch.searchWeb(query: q.query, count: 8)
                guard let hit = found.first(where: {
                    $0.pageURL?.host?.contains(q.site.split(separator: ".")[0]) == true
                }), let url = hit.pageURL else {
                    print("LIVE-LOGIN 搜不到 \(q.site) 的可测页面，跳过")
                    continue
                }
                probes.append(Probe(site: q.site, url: url))
            }
        }
        XCTAssertFalse(probes.isEmpty, "至少该搜到一条可测页面")

        print("LIVE-LOGIN 站点 | 游客字数 → 登录字数 | 图片数 | 登录墙 | 结论")
        var improved = 0
        for p in probes {
            let site = CollectAccounts.site(for: p.url)
            let cookie = site.flatMap { store.cookie($0.id) }
            let logged = site.map { CollectAccounts.looksLoggedIn($0, cookieHeader: cookie) } ?? false
            let guest = await fetch(p.url, cookie: nil)
            let member = await fetch(p.url, cookie: cookie)
            func stats(_ html: String?) -> (words: Int, images: Int, wall: Bool) {
                guard let html else { return (0, 0, true) }
                let md = HTMLToMarkdown.convert(html, baseURL: p.url)
                let wall = ["登录后查看", "请先登录", "扫码登录", "登录/注册", "Sign in to continue",
                            "verify", "安全验证"].contains { html.contains($0) }
                return (HTMLToMarkdown.wordCount(md),
                        md.components(separatedBy: "![").count - 1, wall)
            }
            let g = stats(guest), m = stats(member)
            if m.words > g.words { improved += 1 }
            print("LIVE-LOGIN [\(site?.name ?? "-")\(logged ? "✓" : "·")] \(p.site)"
                  + " | \(g.words) → \(m.words) 字 | \(g.images) → \(m.images) 图"
                  + " | 墙 \(g.wall ? "有" : "无")→\(m.wall ? "有" : "无")"
                  + " | \(m.words > g.words ? "登录更好" : (m.words == g.words ? "无差别" : "登录更差？"))"
                  + "  \(p.url.absoluteString.prefix(70))")
        }
        print("LIVE-LOGIN 小结：\(improved)/\(probes.count) 条在登录后正文更多")

        // —— 第二部分之前的对照：JS 站用「应用内浏览器渲染」能不能救回来 ——
        print("LIVE-LOGIN 渲染兜底：站点 | 普通 HTTP 字数 → 浏览器渲染字数")
        for p in probes {
            let plain = await fetch(p.url, cookie: nil)
            let plainWords = plain.map {
                HTMLToMarkdown.wordCount(HTMLToMarkdown.convert($0, baseURL: p.url))
            } ?? 0
            let rendered = await CollectorWebRender.render(p.url)
            let renderedWords = rendered.map {
                HTMLToMarkdown.wordCount(HTMLToMarkdown.convert($0, baseURL: p.url))
            } ?? 0
            let site = CollectAccounts.site(for: p.url)
            print("LIVE-LOGIN [\(site?.name ?? "-")] \(p.url.host ?? "-")"
                  + " 普通 \(plainWords) 字 → 渲染 \(renderedWords) 字"
                  + "（\(renderedWords > plainWords ? "渲染更全" : "无提升")）")
            if let rendered, renderedWords < 400 {
                let md = HTMLToMarkdown.convert(rendered, baseURL: p.url)
                print("LIVE-LOGIN   渲染结果片段：\(md.prefix(180).replacingOccurrences(of: "\n", with: " "))")
            }
        }

        // —— 第三部分：图片（素材的真正战场）——
        print("LIVE-LOGIN 图片下载：站点 | 游客成功/尝试（字节） → 登录成功/尝试（字节）")
        for p in probes {
            let site = CollectAccounts.site(for: p.url)
            let cookie = site.flatMap { store.cookie($0.id) }
            guard let html = await fetch(p.url, cookie: cookie) else { continue }
            let md = HTMLToMarkdown.convert(html, baseURL: p.url)
            let urls = imageURLs(inMarkdown: md).prefix(6)
            guard !urls.isEmpty else {
                print("LIVE-LOGIN [\(site?.name ?? "-")] \(p.site)：页面里没解析出图片，跳过")
                continue
            }
            var guestOK = 0, guestBytes = 0, memberOK = 0, memberBytes = 0
            for u in urls {
                let g = await fetchImage(u, cookie: nil, referer: p.url)
                let m = await fetchImage(u, cookie: cookie, referer: p.url)
                if g.bytes >= 2048 { guestOK += 1; guestBytes += g.bytes }
                if m.bytes >= 2048 { memberOK += 1; memberBytes += m.bytes }
                if g.bytes != m.bytes || g.status != m.status {
                    print("LIVE-LOGIN   差异：\(u.host ?? "-") 游客 \(g.status)/\(g.bytes)B → 登录 \(m.status)/\(m.bytes)B")
                }
            }
            print("LIVE-LOGIN [\(site?.name ?? "-")] \(p.site)：游客 \(guestOK)/\(urls.count)（\(guestBytes / 1024)KB）"
                  + " → 登录 \(memberOK)/\(urls.count)（\(memberBytes / 1024)KB）")
        }
    }

    /// Markdown 里的图片地址（顺序去重）
    private func imageURLs(inMarkdown md: String) -> [URL] {
        var seen = Set<String>()
        var out: [URL] = []
        guard let re = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\((https?://[^)]+)\)"#) else { return [] }
        let range = NSRange(md.startIndex..<md.endIndex, in: md)
        for m in re.matches(in: md, range: range) {
            guard let r = Range(m.range(at: 1), in: md) else { continue }
            let s = String(md[r])
            guard seen.insert(s).inserted, let u = URL(string: s) else { continue }
            out.append(u)
        }
        return out
    }

    /// 下载一张图（只看状态码与字节数，判断「给不给原图」）
    private func fetchImage(_ url: URL, cookie: String?, referer: URL) async -> (status: Int, bytes: Int) {
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue(NotesStore.collectorUA, forHTTPHeaderField: "User-Agent")
        req.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        if let cookie, !cookie.isEmpty { req.setValue(cookie, forHTTPHeaderField: "Cookie") }
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return (0, 0) }
        return ((resp as? HTTPURLResponse)?.statusCode ?? 0, data.count)
    }

    /// 抓一次页面（cookie 为 nil = 游客）
    private func fetch(_ url: URL, cookie: String?) async -> String? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 25
        req.setValue(NotesStore.collectorUA, forHTTPHeaderField: "User-Agent")
        req.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        if let cookie, !cookie.isEmpty { req.setValue(cookie, forHTTPHeaderField: "Cookie") }
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

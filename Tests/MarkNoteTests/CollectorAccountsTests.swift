import XCTest
@testable import MarkNote

/// 站点账号：域名归属、cookie 拼接、登录态判定、本地存取（含老键迁移）。
/// 注意：全部用独立 UserDefaults suite，绝不碰用户真实的登录 cookie。
final class CollectorAccountsTests: XCTestCase {

    private func makeStore() -> (CollectAccountStore, UserDefaults) {
        let name = "collector-accounts-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return (CollectAccountStore(defaults: defaults), defaults)
    }

    // MARK: - 域名归属

    /// 站点表体检：新加站点最容易犯的错（域名写错 / 登录页不在自己域名下 / 分组漏填）一次性拦住
    func testSiteTableIsWellFormed() {
        var ids = Set<String>()
        var domains = Set<String>()
        for site in CollectAccounts.sites {
            XCTAssertTrue(ids.insert(site.id).inserted, "站点 id 重复：\(site.id)")
            XCTAssertFalse(site.name.isEmpty, "\(site.id) 缺名字")
            XCTAssertFalse(site.hint.isEmpty, "\(site.id) 缺「登录收益」说明")
            XCTAssertFalse(site.icon.isEmpty, "\(site.id) 缺图标")
            XCTAssertFalse(site.domains.isEmpty, "\(site.id) 缺域名")
            for d in site.domains {
                XCTAssertFalse(d.contains("http"), "\(site.id) 的域名别带协议：\(d)")
                XCTAssertTrue(domains.insert(d).inserted,
                              "域名 \(d) 被两个站点共用 → cookie 会认错站")
            }
            // 登录页本身必须落在该站域名内（否则登录完读不到 cookie）
            XCTAssertTrue(site.covers(site.loginURL),
                          "\(site.id) 的登录页 \(site.loginURL.host ?? "?") 不在自己的域名里")
            if case .cookie(let name) = site.check {
                XCTAssertFalse(name.isEmpty, "\(site.id) 的 cookie 名不能为空")
            }
        }
        // 每个分组都要有站点（面板分组标题不能是空的）
        for group in SiteGroup.allCases {
            XCTAssertFalse(CollectAccounts.sites(in: group).isEmpty, "分组 \(group.rawValue) 是空的")
        }
    }

    func testQuickSitesFollowRequestKind() {
        let none: (CollectSite) -> Bool = { _ in false }
        let imageSites = CollectAccounts.sites(forKind: "image", signedIn: none).map(\.id)
        XCTAssertTrue(imageSites.contains("pixiv"))
        XCTAssertTrue(imageSites.contains("huaban"))
        XCTAssertFalse(imageSites.contains("fanqie"), "图片采集不必列小说站")
        let novelSites = CollectAccounts.sites(forKind: "novel", signedIn: none).map(\.id)
        XCTAssertTrue(novelSites.contains("fanqie"))
        XCTAssertTrue(novelSites.contains("qidian"))
        XCTAssertFalse(novelSites.contains("pixiv"))
        // 登录过的站点永远算相关，而且排在最前
        let signedInFanqie: (CollectSite) -> Bool = { $0.id == "fanqie" }
        let mixed = CollectAccounts.sites(forKind: "image", signedIn: signedInFanqie).map(\.id)
        XCTAssertEqual(mixed.first, "fanqie", "自己登录过的站要顶到最前")
    }

    /// 母域与子域同表时，取更具体的那个（否则 cookie 会认错站）；顺序无关
    func testMostSpecificDomainWins() throws {
        let adobeGeneral = CollectSite(id: "adobe", name: "Adobe", icon: "a.square",
                                       loginURL: URL(string: "https://www.adobe.com/login")!,
                                       domains: ["adobe.com"], hint: "x", check: .cookieOnly)
        let adobeStock = CollectSite(id: "adobestock", name: "Adobe Stock", icon: "a.square",
                                     loginURL: URL(string: "https://stock.adobe.com/login")!,
                                     domains: ["stock.adobe.com"], hint: "x", check: .cookieOnly)
        for list in [[adobeGeneral, adobeStock], [adobeStock, adobeGeneral]] {
            XCTAssertEqual(CollectAccounts.site(for: URL(string: "https://stock.adobe.com/x")!,
                                                in: list)?.id,
                           "adobestock", "子域更具体 → 归它")
            XCTAssertEqual(CollectAccounts.site(for: URL(string: "https://www.adobe.com/x")!,
                                                in: list)?.id,
                           "adobe", "母域仍归母站")
        }
    }

    /// 免登录来源预设：按采集类型给，域名不重复
    func testFreeSourcePresets() {
        let image = CollectPresets.sources(forKind: "image").map(\.domain)
        XCTAssertTrue(image.contains("unsplash.com"))
        XCTAssertTrue(image.contains("wikimedia.org"))
        XCTAssertFalse(image.contains("mixkit.co"), "图片不该带纯视频站")
        let video = CollectPresets.sources(forKind: "video").map(\.domain)
        XCTAssertTrue(video.contains("mixkit.co"))
        XCTAssertTrue(video.contains("pexels.com"), "Pexels 图 + 视频都有")
        XCTAssertFalse(video.contains("unsplash.com"))
        XCTAssertTrue(CollectPresets.sources(forKind: "novel").isEmpty, "小说用不上免登录图库")
        var seen = Set<String>()
        for p in CollectPresets.sources {
            XCTAssertTrue(seen.insert(p.domain).inserted, "预设域名重复：\(p.domain)")
            XCTAssertFalse(p.domain.contains("http"), "预设域名别带协议：\(p.domain)")
        }
    }

    func testSiteMatchingByDomain() throws {
        XCTAssertEqual(CollectAccounts.site(for: URL(string: "https://m.weibo.com/u/1")!)?.id, "weibo")
        XCTAssertEqual(CollectAccounts.site(for: URL(string: "https://weibo.com/x")!)?.id, "weibo")
        XCTAssertEqual(CollectAccounts.site(for: URL(string: "https://i0.hdslb.com/a.jpg")!)?.id, "bilibili",
                       "B 站图床也要算 B 站")
        XCTAssertEqual(CollectAccounts.site(for: URL(string: "https://www.xiaohongshu.com/explore/1")!)?.id,
                       "xiaohongshu")
        XCTAssertNil(CollectAccounts.site(for: URL(string: "https://example.com/a")!))
        // 后缀必须落在域名边界上，不能把伪装域名当成站点
        XCTAssertNil(CollectAccounts.site(for: URL(string: "https://weibo.com.evil.example/x")!))
    }

    // MARK: - cookie 拼接

    func testCookieHeaderPicksOnlyMatchingDomains() {
        let cookies = [
            (name: "SUB", value: "abc", domain: ".weibo.com"),
            (name: "SUBP", value: "id1", domain: ".weibo.com"),
            (name: "z_c0", value: "zhihu-token", domain: ".zhihu.com"),
            (name: "empty", value: "", domain: ".weibo.com"),
        ]
        let header = CollectAccounts.cookieHeader(from: cookies, domains: ["weibo.com", "sinaimg.cn"])
        XCTAssertEqual(header, "SUB=abc; SUBP=id1", "只要微博域、丢掉空值，按名字排序")
        XCTAssertNil(CollectAccounts.cookieHeader(from: cookies, domains: ["github.com"]))
        XCTAssertNil(CollectAccounts.cookieHeader(from: [], domains: ["weibo.com"]))
    }

    func testCookieHeaderPrefersMoreSpecificDomain() {
        let header = CollectAccounts.cookieHeader(from: [
            (name: "SESSDATA", value: "generic", domain: ".bilibili.com"),
            (name: "SESSDATA", value: "specific", domain: ".passport.bilibili.com"),
        ], domains: ["bilibili.com"])
        XCTAssertEqual(header, "SESSDATA=specific", "同名 cookie 取域更具体的那条")
    }

    func testCookiePresenceCheck() {
        XCTAssertTrue(CollectAccounts.header("SUB=abc; SUBP=1", containsCookie: "SUB"))
        XCTAssertFalse(CollectAccounts.header("SUBP=1", containsCookie: "SUB"),
                       "前缀相同的另一个 cookie 不能误判")
        XCTAssertFalse(CollectAccounts.header("SUB=", containsCookie: "SUB"), "空值不算登录")
        XCTAssertFalse(CollectAccounts.header(nil, containsCookie: "SUB"))
    }

    func testLooksLoggedInPerSite() {
        let weibo = CollectAccounts.site(id: "weibo")!
        XCTAssertTrue(CollectAccounts.looksLoggedIn(weibo, cookieHeader: "SUB=abc"))
        XCTAssertFalse(CollectAccounts.looksLoggedIn(weibo, cookieHeader: "SUBP=abc"))
        let xhs = CollectAccounts.site(id: "xiaohongshu")!
        XCTAssertTrue(CollectAccounts.looksLoggedIn(xhs, cookieHeader: "web_session=xyz"))
        let huaban = CollectAccounts.site(id: "huaban")!
        XCTAssertTrue(CollectAccounts.looksLoggedIn(huaban, cookieHeader: "anything=1"),
                      "花瓣这类看不出名字的：有 cookie 就算已保存登录")
        XCTAssertFalse(CollectAccounts.looksLoggedIn(huaban, cookieHeader: nil))
    }

    // MARK: - 本地存取

    func testStoreRoundTripAndClear() {
        let (store, _) = makeStore()
        XCTAssertNil(store.cookie("weibo"))
        store.setCookie("SUB=abc", for: "weibo")
        XCTAssertEqual(store.cookie("weibo"), "SUB=abc")
        XCTAssertEqual(store.loggedInSites().map(\.id), ["weibo"])
        store.clear("weibo")
        XCTAssertNil(store.cookie("weibo"))
        XCTAssertTrue(store.loggedInSites().isEmpty)
    }

    func testLegacyBilibiliCookieStillReadable() {
        let (store, defaults) = makeStore()
        // 老版本只写了 collectorBilibiliCookie
        defaults.set("SESSDATA=legacy", forKey: "collectorBilibiliCookie")
        XCTAssertEqual(store.cookie("bilibili"), "SESSDATA=legacy", "老用户的 B 站登录不能丢")
        // 新写入会同步老键（旧代码路径仍能读到）
        store.setCookie("SESSDATA=new", for: "bilibili")
        XCTAssertEqual(defaults.string(forKey: "collectorBilibiliCookie"), "SESSDATA=new")
        store.clear("bilibili")
        XCTAssertNil(store.cookie("bilibili"))
        XCTAssertNil(defaults.string(forKey: "collectorBilibiliCookie"))
    }

    // MARK: - 取 cookie 的三条路径

    func testCookieForURLAndReferer() {
        let (store, _) = makeStore()
        store.setCookie("SESSDATA=bili", for: "bilibili")
        store.setCookie("SUB=weibo", for: "weibo")
        // 图床（hdslb）→ 用 B 站的 cookie
        XCTAssertEqual(CollectAccounts.cookieHeader(
            for: URL(string: "https://i0.hdslb.com/bfs/a.jpg")!, store: store), "SESSDATA=bili")
        // 直链不认识的域名，但 referer 是微博 → 借微博的 cookie
        XCTAssertEqual(CollectAccounts.requestCookie(
            for: URL(string: "https://wx1.sinaimg.cn/a.jpg")!,
            referer: URL(string: "https://weibo.com/u/1")!, store: store), "SUB=weibo")
        // 都不认识 → nil（不加任何 cookie）
        XCTAssertNil(CollectAccounts.requestCookie(
            for: URL(string: "https://example.com/a.jpg")!, referer: nil, store: store))
    }
}

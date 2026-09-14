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

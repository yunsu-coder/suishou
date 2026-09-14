import Foundation

extension Notification.Name {
    /// 站点账号登录 / 退出后广播（采集面板据此刷新「已登录」显示）
    static let collectorAccountsChanged = Notification.Name("collectorAccountsChanged")
}

/// 采集用的**站点账号**：不少站点（微博、小红书、知乎、花瓣…）不登录就只能看到缩略图、
/// 或者直接反爬挡住；登录后 cookie 带上，抓正文与下载素材的成功率会明显好一截。
///
/// 原则：cookie **只存本机**（UserDefaults），只在该站自己的域名上用；退出即清。
struct CollectSite: Identifiable, Equatable {
    var id: String
    /// 显示名（中文优先）
    var name: String
    var icon: String
    var loginURL: URL
    /// 归属域名（后缀匹配：`weibo.com` 匹配 `weibo.com` / `m.weibo.com` / `.weibo.com`）
    var domains: [String]
    /// 登录收益的一句话说明
    var hint: String
    /// 登录态判定方式
    var check: Check

    enum Check: Equatable {
        /// B 站 nav 接口（能拿到用户名）
        case bilibiliNav
        /// 只要存在这个 cookie 就算登录（微博 SUB / 小红书 web_session / 知乎 z_c0…）
        case cookie(String)
        /// 有 cookie 就算「已保存登录」，但无法验证
        case cookieOnly
    }

    /// 这个站点是否覆盖某个 URL
    func covers(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

/// 站点目录 + 登录态 / cookie 工具（纯函数为主，便于测试）
enum CollectAccounts {

    /// 内置站点表（顺序 = 面板里的展示顺序）
    static let sites: [CollectSite] = [
        CollectSite(id: "bilibili", name: "B 站", icon: "play.rectangle",
                    loginURL: URL(string: "https://passport.bilibili.com/login")!,
                    domains: ["bilibili.com", "bilivideo.com", "hdslb.com"],
                    hint: _L("登录后才能下 1080P（不登录只有 360P）",
                             "Sign in to download 1080p (360p otherwise)"),
                    check: .bilibiliNav),
        CollectSite(id: "weibo", name: "微博", icon: "bubble.left.and.bubble.right",
                    loginURL: URL(string: "https://passport.weibo.com/sso/signin")!,
                    domains: ["weibo.com", "weibo.cn", "sinaimg.cn", "sina.com.cn"],
                    hint: _L("登录后微博图/长文能原图抓取，不再只给缩略图",
                             "Sign in to fetch full-size Weibo images/long posts"),
                    check: .cookie("SUB")),
        CollectSite(id: "xiaohongshu", name: "小红书", icon: "book.closed",
                    loginURL: URL(string: "https://www.xiaohongshu.com/login")!,
                    domains: ["xiaohongshu.com", "xhscdn.com"],
                    hint: _L("登录后笔记图与正文可抓（未登录常只返回封面）",
                             "Sign in to fetch note images and text"),
                    check: .cookie("web_session")),
        CollectSite(id: "zhihu", name: "知乎", icon: "questionmark.circle",
                    loginURL: URL(string: "https://www.zhihu.com/signin")!,
                    domains: ["zhihu.com", "zhimg.com"],
                    hint: _L("登录后回答/专栏正文与配图可完整提取",
                             "Sign in to extract full answers and images"),
                    check: .cookie("z_c0")),
        CollectSite(id: "douyin", name: "抖音", icon: "music.note.tv",
                    loginURL: URL(string: "https://www.douyin.com/")!,
                    domains: ["douyin.com", "douyinpic.com", "douyinvod.com", "snssdk.com"],
                    hint: _L("登录后视频直链与图集更稳（未登录常 403）",
                             "Sign in for stabler video URLs and photo sets"),
                    check: .cookie("sessionid")),
        CollectSite(id: "huaban", name: "花瓣", icon: "leaf",
                    loginURL: URL(string: "https://huaban.com/auth/")!,
                    domains: ["huaban.com", "huabanimg.com"],
                    hint: _L("登录后才能下载原图（未登录只有预览图）",
                             "Sign in to download originals"),
                    check: .cookieOnly),
        CollectSite(id: "douban", name: "豆瓣", icon: "film",
                    loginURL: URL(string: "https://accounts.douban.com/passport/login")!,
                    domains: ["douban.com", "doubanio.com"],
                    hint: _L("登录后书影音资料与长评更全，且不易被限流",
                             "Sign in for fuller reviews and fewer rate limits"),
                    check: .cookie("dbcl2")),
    ]

    static func site(id: String) -> CollectSite? { sites.first { $0.id == id } }

    /// 这个 URL 属于哪个站点（找不到 = nil，按游客抓取）
    static func site(for url: URL) -> CollectSite? { sites.first { $0.covers(url) } }

    /// 该 URL 能用的 cookie（按域名取；找不到站点就 nil）
    static func cookieHeader(for url: URL,
                             store: CollectAccountStore = .standard) -> String? {
        guard let site = site(for: url) else { return nil }
        return store.cookie(site.id)
    }

    /// 请求头 cookie：先看 URL 自己，再看 referer（防盗链常按来源站判定）
    static func requestCookie(for url: URL, referer: URL?,
                              store: CollectAccountStore = .standard) -> String? {
        cookieHeader(for: url, store: store) ?? referer.flatMap { cookieHeader(for: $0, store: store) }
    }

    // MARK: - cookie 拼接（纯函数）

    /// 只取这些域名下的 cookie，按名字去重（域越具体越优先），拼成请求头
    static func cookieHeader(from cookies: [(name: String, value: String, domain: String)],
                             domains: [String]) -> String? {
        let picked = cookies.filter { c in
            guard !c.value.isEmpty else { return false }
            let d = c.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return domains.contains { d == $0 || d.hasSuffix("." + $0) }
        }
        guard !picked.isEmpty else { return nil }
        var byName: [String: String] = [:]
        for c in picked.sorted(by: { $0.domain.count < $1.domain.count }) { byName[c.name] = c.value }
        let header = byName.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "; ")
        return header.isEmpty ? nil : header
    }

    /// cookie 头里有没有某个 cookie（登录态判定的字符串版）
    static func header(_ header: String?, containsCookie name: String) -> Bool {
        guard let header else { return false }
        return header.split(separator: ";").contains {
            let pair = $0.trimmingCharacters(in: .whitespaces)
            return pair.hasPrefix("\(name)=") && pair.count > name.count + 1
        }
    }

    /// 用 cookie 头判断登录态（B 站那种要打接口的用 `.bilibiliNav`，这里只处理看得出名字的）
    static func looksLoggedIn(_ site: CollectSite, cookieHeader: String?) -> Bool {
        switch site.check {
        case .cookie(let name): return header(cookieHeader, containsCookie: name)
        case .cookieOnly: return !(cookieHeader ?? "").isEmpty
        case .bilibiliNav: return header(cookieHeader, containsCookie: "SESSDATA")
        }
    }
}

/// cookie 本地存储：按站点键存 UserDefaults（只存本机，退出即清）
struct CollectAccountStore {
    var defaults: UserDefaults = .standard

    static let standard = CollectAccountStore()

    private func key(_ id: String) -> String { "collectorCookie.\(id)" }
    /// 老版本只存了 B 站一个 cookie，读的时候兜底迁移
    private static let legacyBilibiliKey = "collectorBilibiliCookie"

    func cookie(_ id: String) -> String? {
        let s = defaults.string(forKey: key(id)) ?? ""
        if !s.isEmpty { return s }
        if id == "bilibili" {
            let legacy = defaults.string(forKey: Self.legacyBilibiliKey) ?? ""
            return legacy.isEmpty ? nil : legacy
        }
        return nil
    }

    func setCookie(_ value: String?, for id: String) {
        let v = value ?? ""
        defaults.set(v, forKey: key(id))
        if id == "bilibili" { defaults.set(v, forKey: Self.legacyBilibiliKey) }
        NotificationCenter.default.post(name: .collectorAccountsChanged, object: nil)
    }

    func clear(_ id: String) {
        defaults.removeObject(forKey: key(id))
        if id == "bilibili" { defaults.removeObject(forKey: Self.legacyBilibiliKey) }
        NotificationCenter.default.post(name: .collectorAccountsChanged, object: nil)
    }

    /// 已保存登录的站点（cookie 非空）
    func loggedInSites() -> [CollectSite] {
        CollectAccounts.sites.filter { !(cookie($0.id) ?? "").isEmpty }
    }
}

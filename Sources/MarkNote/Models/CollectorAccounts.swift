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
    /// 面板分组（越常用的排越前）
    var group: SiteGroup = .media
    /// 对哪些采集类型有意义（界面据此给快捷 chip 排序；空 = 都算）
    var kinds: Set<String> = []

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

/// 站点分组：面板按组展示，快捷 chip 按采集类型挑
enum SiteGroup: String, CaseIterable {
    case media      // 图片 / 视频素材
    case reading    // 文章 / 小说
    case other      // 综合

    var title: String {
        switch self {
        case .media: return _L("图片 / 视频素材", "Images & video")
        case .reading: return _L("文章 / 小说", "Articles & novels")
        case .other: return _L("综合", "General")
        }
    }
}

/// 站点目录 + 登录态 / cookie 工具（纯函数为主，便于测试）
enum CollectAccounts {

    /// 内置站点表（顺序 = 面板里的展示顺序）。
    ///
    /// **2026-09-14 精简**：只保留用户实际登录的站点（17 个新登录 + 早前登录过的 B 站），
    /// 其余未登录的站先摘掉 —— 列表里只留「现在就能用」的，不留一堆要登录才有效果的。
    /// （想加回来直接往下面补一条即可；被否掉的域名另见 `rejected`。）
    ///
    /// 进表门槛：一手来源 / 登录确实多拿到东西 / 内容抓得到 / 不吃版权风险。
    static let sites: [CollectSite] = [
        // —— 图片 / 视频素材 ——
        CollectSite(id: "bilibili", name: "B 站", icon: "play.rectangle",
                    loginURL: URL(string: "https://passport.bilibili.com/login")!,
                    domains: ["bilibili.com", "bilivideo.com", "hdslb.com"],
                    hint: _L("登录后才能下 1080P（不登录只有 360P）",
                             "Sign in to download 1080p (360p otherwise)"),
                    check: .bilibiliNav, group: .media, kinds: ["video", "article"]),
        CollectSite(id: "youtube", name: "YouTube", icon: "play.square.stack",
                    loginURL: URL(string: "https://www.youtube.com/signin")!,
                    domains: ["youtube.com", "googlevideo.com", "ytimg.com"],
                    hint: _L("登录后可看会员/年龄限制内容（需要能访问 Google）",
                             "Sign in for restricted videos (needs Google access)"),
                    check: .cookie("SAPISID"), group: .media, kinds: ["video"]),
        CollectSite(id: "vimeo", name: "Vimeo", icon: "v.square",
                    loginURL: URL(string: "https://vimeo.com/log_in")!,
                    domains: ["vimeo.com", "vimeocdn.com"],
                    hint: _L("登录后可下原片（作者允许下载时）",
                             "Sign in to download originals when allowed"),
                    check: .cookieOnly, group: .media, kinds: ["video"]),
        CollectSite(id: "douyin", name: "抖音", icon: "music.note.tv",
                    loginURL: URL(string: "https://www.douyin.com/")!,
                    domains: ["douyin.com", "douyinpic.com", "douyinvod.com", "snssdk.com"],
                    hint: _L("登录后视频直链与图集更稳（未登录常 403）",
                             "Sign in for stabler video URLs and photo sets"),
                    check: .cookie("sessionid"), group: .media, kinds: ["video", "image"]),
        CollectSite(id: "xiaohongshu", name: "小红书", icon: "book.closed",
                    loginURL: URL(string: "https://www.xiaohongshu.com/login")!,
                    domains: ["xiaohongshu.com", "xhscdn.com"],
                    hint: _L("登录后笔记图与正文可抓（未登录常只返回封面）",
                             "Sign in to fetch note images and text"),
                    check: .cookie("web_session"), group: .media, kinds: ["image", "video", "article"]),
        CollectSite(id: "huaban", name: "花瓣", icon: "leaf",
                    loginURL: URL(string: "https://huaban.com/auth/")!,
                    domains: ["huaban.com", "huabanimg.com"],
                    hint: _L("登录后才能下载原图（未登录只有预览图）",
                             "Sign in to download originals"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),
        CollectSite(id: "zcool", name: "站酷", icon: "paintpalette",
                    loginURL: URL(string: "https://passport.zcool.com.cn/login.jsp")!,
                    domains: ["zcool.com.cn", "zcool.cn"],
                    hint: _L("登录后可看大图并下载设计稿（未登录只有预览）",
                             "Sign in for large previews and design assets"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),
        CollectSite(id: "tuchong", name: "图虫", icon: "photo.on.rectangle.angled",
                    loginURL: URL(string: "https://tuchong.com/login/")!,
                    domains: ["tuchong.com"],
                    hint: _L("登录后可下原图并看作者参数（未登录只有压缩图）",
                             "Sign in for originals and EXIF"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),
        CollectSite(id: "pixiv", name: "Pixiv", icon: "paintbrush.pointed",
                    loginURL: URL(string: "https://accounts.pixiv.net/login")!,
                    domains: ["pixiv.net", "pximg.net"],
                    hint: _L("登录后才能看原图 / 动图（未登录只给压缩图）",
                             "Sign in for full-size illustrations and ugoira"),
                    check: .cookie("PHPSESSID"), group: .media, kinds: ["image"]),
        CollectSite(id: "tumblr", name: "Tumblr", icon: "t.square",
                    loginURL: URL(string: "https://www.tumblr.com/login")!,
                    domains: ["tumblr.com"],
                    hint: _L("登录后可看高清图与长贴（未登录常限流）",
                             "Sign in for full-resolution images"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),

        // —— 文章 / 小说 ——
        CollectSite(id: "zhihu", name: "知乎", icon: "questionmark.circle",
                    loginURL: URL(string: "https://www.zhihu.com/signin")!,
                    domains: ["zhihu.com", "zhimg.com"],
                    hint: _L("登录后回答/专栏正文与配图可完整提取",
                             "Sign in to extract full answers and images"),
                    check: .cookie("z_c0"), group: .reading, kinds: ["article"]),
        CollectSite(id: "douban", name: "豆瓣", icon: "film",
                    loginURL: URL(string: "https://accounts.douban.com/passport/login")!,
                    domains: ["douban.com", "doubanio.com"],
                    hint: _L("登录后书影音资料与长评更全，且不易被限流",
                             "Sign in for fuller reviews and fewer rate limits"),
                    check: .cookie("dbcl2"), group: .reading, kinds: ["article", "novel"]),
        CollectSite(id: "sspai", name: "少数派", icon: "doc.richtext",
                    loginURL: URL(string: "https://sspai.com/login")!,
                    domains: ["sspai.com", "sspai.net"],
                    hint: _L("登录后会员文章正文与配图可提取",
                             "Sign in for member-only articles"),
                    check: .cookieOnly, group: .reading, kinds: ["article"]),
        CollectSite(id: "juejin", name: "掘金", icon: "hammer",
                    loginURL: URL(string: "https://juejin.cn/login")!,
                    domains: ["juejin.cn"],
                    hint: _L("登录后文章正文与代码块可完整提取",
                             "Sign in for full articles and code blocks"),
                    check: .cookieOnly, group: .reading, kinds: ["article"]),
        CollectSite(id: "weread", name: "微信读书", icon: "book",
                    loginURL: URL(string: "https://weread.qq.com/")!,
                    domains: ["weread.qq.com", "wrcdn.cn"],
                    hint: _L("登录后才能读章节正文（未登录只有简介）",
                             "Sign in to read chapters"),
                    check: .cookie("wr_vid"), group: .reading, kinds: ["novel", "article"]),
        CollectSite(id: "fanqie", name: "番茄小说", icon: "book.pages",
                    loginURL: URL(string: "https://fanqienovel.com/")!,
                    domains: ["fanqienovel.com", "fqnovel.com"],
                    hint: _L("登录后章节更全、不易被反爬拦（免费正版）",
                             "Sign in for fuller chapters (free & licensed)"),
                    check: .cookie("sessionid"), group: .reading, kinds: ["novel"]),
        CollectSite(id: "zongheng", name: "纵横中文网", icon: "square.and.pencil",
                    loginURL: URL(string: "https://www.zongheng.com/")!,
                    domains: ["zongheng.com"],
                    hint: _L("登录后章节更全、目录页更完整",
                             "Sign in for fuller chapter lists"),
                    check: .cookieOnly, group: .reading, kinds: ["novel"]),

        // —— 综合 ——
        CollectSite(id: "x", name: "X / Twitter", icon: "bird",
                    loginURL: URL(string: "https://x.com/i/flow/login")!,
                    domains: ["x.com", "twitter.com", "twimg.com"],
                    hint: _L("登录后才能看推文图与视频原图（需要能访问 X）",
                             "Sign in for tweet media (needs X access)"),
                    check: .cookie("auth_token"), group: .other, kinds: ["image", "video", "article"]),
    ]

    /// **被否掉的站点**（记下来，防止以后手滑加回来）——
    /// 「只要优质网站」这条规矩的可执行版本：`testRejectedDomainsAreNotInTable` 会检查它们没混进表里。
    static let rejected: [(domain: String, why: String)] = [
        ("58pic.com", "水印素材站：未登录只给带水印预览，登录也多为会员制"),
        ("ooopic.com", "水印素材站，同上"),
        ("ibaotu.com", "水印素材站，同上"),
        ("51miz.com", "水印素材站，同上"),
        ("699pic.com", "水印素材站，同上"),
        ("nipic.com", "水印素材站，同上"),
        ("gaoding.com", "在线设计工具：模板元素多不可导出，抓不到可用原图"),
        ("canva.com", "在线设计工具，同上"),
        ("vcg.com", "商业图库：未授权抓图有版权风险"),
        ("shutterstock.com", "商业图库，同上"),
        ("csdn.net", "内容农场化严重、正文大量需登录/展开，采集质量不稳定"),
        ("jianshu.com", "内容质量下滑（营销号占多），不再作为优质来源"),
        ("baidu.com", "搜索引擎而非素材来源；百科/贴吧图质量不达门槛"),
        ("qimao.com", "免费小说平台：站点反爬强、正文质量参差"),
        ("faloo.com", "网文站：试读为主，登录后仍需逐章付费"),
        ("ciweimao.com", "网文站：同上"),
        ("zhangyue.com", "阅读平台：DRM 章节，抓不到可用正文"),
        ("17k.com", "网文站：章节大量需付费，站点陈旧"),
        ("mgtv.com", "长视频平台：DRM 加密，取不到可下载源"),
        ("youku.com", "长视频平台：同上"),
        ("iqiyi.com", "长视频平台：同上"),
        ("v.qq.com", "长视频平台：同上"),
        ("sohu.com", "长视频平台：画质与稳定性不达门槛"),
        ("ixigua.com", "短视频聚合：内容重复度高、质量参差"),
        ("miyoushe.com", "游戏社区：以攻略为主，素材价值低（同人图走 Pixiv/LOFTER）"),
        ("hoyolab.com", "游戏社区：同上"),
        ("nga.cn", "游戏论坛：附件图需登录且大量转载，质量不达门槛"),
    ]
    /// 按分组取站点（面板展示顺序）
    static func sites(in group: SiteGroup) -> [CollectSite] {
        sites.filter { $0.group == group }
    }

    /// 与某个采集类型相关的站点（登录过的永远算相关 → 快捷 chip 不丢自己登过的站）
    static func sites(forKind kind: String?, signedIn: (CollectSite) -> Bool) -> [CollectSite] {
        let k = kind ?? "image"
        return sites
            .filter { $0.kinds.isEmpty || $0.kinds.contains(k) || signedIn($0) }
            .sorted { (signedIn($0) ? 0 : 1, $0.name) < (signedIn($1) ? 0 : 1, $1.name) }
    }

    static func site(id: String) -> CollectSite? { sites.first { $0.id == id } }

    /// 这个 URL 属于哪个站点（找不到 = nil，按游客抓取）。
    /// 多个站点都命中时取**域名更具体**的那个（例：`stock.adobe.com` 归到 Adobe 系，而不是 `adobe.com` 那条）。
    /// `list` 可注入：便于测试「更具体域名优先」，也方便将来加用户自定义站点。
    static func site(for url: URL, in list: [CollectSite] = CollectAccounts.sites) -> CollectSite? {
        guard let host = url.host?.lowercased() else { return nil }
        var best: (site: CollectSite, length: Int)?
        for site in list {
            for domain in site.domains where host == domain || host.hasSuffix("." + domain) {
                if best == nil || domain.count > best!.length { best = (site, domain.count) }
            }
        }
        return best?.site
    }

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

/// 免登录的优质来源：点一下就写进「只看站点」，跟账号无关。
/// （这些站不登录也能下载，做素材时优先从这里搜，质量与授权都更省心。）
struct CollectSourcePreset: Identifiable, Equatable {
    var id: String
    var name: String
    var domain: String
    var kinds: Set<String>
}

enum CollectPresets {
    static let sources: [CollectSourcePreset] = [
        .init(id: "unsplash", name: "Unsplash", domain: "unsplash.com", kinds: ["image"]),
        .init(id: "pexels", name: "Pexels", domain: "pexels.com", kinds: ["image", "video"]),
        .init(id: "pixabay", name: "Pixabay", domain: "pixabay.com", kinds: ["image", "video"]),
        .init(id: "wikimedia", name: "Wikimedia", domain: "wikimedia.org", kinds: ["image"]),
        .init(id: "nasa", name: "NASA", domain: "nasa.gov", kinds: ["image", "video"]),
        .init(id: "openverse", name: "Openverse", domain: "openverse.org", kinds: ["image"]),
        .init(id: "mixkit", name: "Mixkit", domain: "mixkit.co", kinds: ["video"]),
        .init(id: "coverr", name: "Coverr", domain: "coverr.co", kinds: ["video"]),
        .init(id: "videvo", name: "Videvo", domain: "videvo.net", kinds: ["video"]),
    ]

    /// 与当前采集类型相关的免登录来源（文章 / 小说用不上）
    static func sources(forKind kind: String?) -> [CollectSourcePreset] {
        let k = kind ?? "image"
        return sources.filter { $0.kinds.contains(k) }
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

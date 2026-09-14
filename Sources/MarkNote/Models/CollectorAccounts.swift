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

    /// 内置站点表（顺序 = 面板里的展示顺序）
    static let sites: [CollectSite] = [
        CollectSite(id: "bilibili", name: "B 站", icon: "play.rectangle",
                    loginURL: URL(string: "https://passport.bilibili.com/login")!,
                    domains: ["bilibili.com", "bilivideo.com", "hdslb.com"],
                    hint: _L("登录后才能下 1080P（不登录只有 360P）",
                             "Sign in to download 1080p (360p otherwise)"),
                    check: .bilibiliNav, group: .media, kinds: ["video", "article"]),
        CollectSite(id: "weibo", name: "微博", icon: "bubble.left.and.bubble.right",
                    loginURL: URL(string: "https://passport.weibo.com/sso/signin")!,
                    domains: ["weibo.com", "weibo.cn", "sinaimg.cn", "sina.com.cn"],
                    hint: _L("登录后微博图/长文能原图抓取，不再只给缩略图",
                             "Sign in to fetch full-size Weibo images/long posts"),
                    check: .cookie("SUB"), group: .media, kinds: ["image", "video", "article"]),
        CollectSite(id: "xiaohongshu", name: "小红书", icon: "book.closed",
                    loginURL: URL(string: "https://www.xiaohongshu.com/login")!,
                    domains: ["xiaohongshu.com", "xhscdn.com"],
                    hint: _L("登录后笔记图与正文可抓（未登录常只返回封面）",
                             "Sign in to fetch note images and text"),
                    check: .cookie("web_session"), group: .media, kinds: ["image", "video", "article"]),
        CollectSite(id: "zhihu", name: "知乎", icon: "questionmark.circle",
                    loginURL: URL(string: "https://www.zhihu.com/signin")!,
                    domains: ["zhihu.com", "zhimg.com"],
                    hint: _L("登录后回答/专栏正文与配图可完整提取",
                             "Sign in to extract full answers and images"),
                    check: .cookie("z_c0"), group: .reading, kinds: ["article"]),
        CollectSite(id: "douyin", name: "抖音", icon: "music.note.tv",
                    loginURL: URL(string: "https://www.douyin.com/")!,
                    domains: ["douyin.com", "douyinpic.com", "douyinvod.com", "snssdk.com"],
                    hint: _L("登录后视频直链与图集更稳（未登录常 403）",
                             "Sign in for stabler video URLs and photo sets"),
                    check: .cookie("sessionid"), group: .media, kinds: ["video", "image"]),
        CollectSite(id: "huaban", name: "花瓣", icon: "leaf",
                    loginURL: URL(string: "https://huaban.com/auth/")!,
                    domains: ["huaban.com", "huabanimg.com"],
                    hint: _L("登录后才能下载原图（未登录只有预览图）",
                             "Sign in to download originals"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),
        CollectSite(id: "douban", name: "豆瓣", icon: "film",
                    loginURL: URL(string: "https://accounts.douban.com/passport/login")!,
                    domains: ["douban.com", "doubanio.com"],
                    hint: _L("登录后书影音资料与长评更全，且不易被限流",
                             "Sign in for fuller reviews and fewer rate limits"),
                    check: .cookie("dbcl2"), group: .reading, kinds: ["article", "novel"]),

        // —— 图片 / 视频素材 ——
        CollectSite(id: "pixiv", name: "Pixiv", icon: "paintbrush.pointed",
                    loginURL: URL(string: "https://accounts.pixiv.net/login")!,
                    domains: ["pixiv.net", "pximg.net"],
                    hint: _L("登录后才能看原图 / 动图（未登录只给压缩图）",
                             "Sign in for full-size illustrations and ugoira"),
                    check: .cookie("PHPSESSID"), group: .media, kinds: ["image"]),
        CollectSite(id: "pinterest", name: "Pinterest", icon: "pin",
                    loginURL: URL(string: "https://www.pinterest.com/login/")!,
                    domains: ["pinterest.com", "pinimg.com"],
                    hint: _L("登录后才能下载原图、看完整相关推荐",
                             "Sign in to download originals and browse related pins"),
                    check: .cookie("_pinterest_sess"), group: .media, kinds: ["image"]),
        CollectSite(id: "zcool", name: "站酷", icon: "paintpalette",
                    loginURL: URL(string: "https://passport.zcool.com.cn/login.jsp")!,
                    domains: ["zcool.com.cn", "zcool.cn"],
                    hint: _L("登录后可看大图并下载设计稿（未登录只有预览）",
                             "Sign in for large previews and design assets"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),
        CollectSite(id: "58pic", name: "千图网", icon: "square.grid.2x2",
                    loginURL: URL(string: "https://www.58pic.com/login")!,
                    domains: ["58pic.com", "58pic.net"],
                    hint: _L("登录后素材可下载原图（未登录只给带水印预览）",
                             "Sign in to download full assets (watermarked preview otherwise)"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),
        CollectSite(id: "artstation", name: "ArtStation", icon: "cube.transparent",
                    loginURL: URL(string: "https://www.artstation.com/login")!,
                    domains: ["artstation.com", "artstation-cdn.com"],
                    hint: _L("登录后能看大图与过程稿（未登录常限流）",
                             "Sign in for full-size art and process shots"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),
        CollectSite(id: "behance", name: "Behance", icon: "rectangle.on.rectangle.angled",
                    loginURL: URL(string: "https://www.behance.net/login")!,
                    domains: ["behance.net", "adobe.com"],
                    hint: _L("登录后项目大图与源文件更全",
                             "Sign in for full project images"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),
        CollectSite(id: "kuaishou", name: "快手", icon: "video.badge.waveform",
                    loginURL: URL(string: "https://www.kuaishou.com/")!,
                    domains: ["kuaishou.com", "gifshow.com", "kspkg.com"],
                    hint: _L("登录后视频直链更稳、可看高清",
                             "Sign in for stabler video URLs"),
                    check: .cookieOnly, group: .media, kinds: ["video"]),
        CollectSite(id: "vqq", name: "腾讯视频", icon: "play.tv",
                    loginURL: URL(string: "https://v.qq.com/")!,
                    domains: ["v.qq.com", "qpic.cn", "gtimg.cn"],
                    hint: _L("登录后能取到更高清的源（未登录只有低清）",
                             "Sign in for higher-quality sources"),
                    check: .cookieOnly, group: .media, kinds: ["video"]),
        CollectSite(id: "youtube", name: "YouTube", icon: "play.square.stack",
                    loginURL: URL(string: "https://www.youtube.com/signin")!,
                    domains: ["youtube.com", "googlevideo.com", "ytimg.com"],
                    hint: _L("登录后可看会员/年龄限制内容（需要能访问 Google）",
                             "Sign in for restricted videos (needs Google access)"),
                    check: .cookie("SAPISID"), group: .media, kinds: ["video"]),

        // —— 文章 / 小说 ——
        CollectSite(id: "jianshu", name: "简书", icon: "doc.text",
                    loginURL: URL(string: "https://www.jianshu.com/sign_in")!,
                    domains: ["jianshu.com", "jianshu.io"],
                    hint: _L("登录后文章正文与配图更完整",
                             "Sign in for full article text and images"),
                    check: .cookie("remember_user_token"), group: .reading, kinds: ["article"]),
        CollectSite(id: "weread", name: "微信读书", icon: "book",
                    loginURL: URL(string: "https://weread.qq.com/")!,
                    domains: ["weread.qq.com", "wrcdn.cn"],
                    hint: _L("登录后才能读章节正文（未登录只有简介）",
                             "Sign in to read chapters"),
                    check: .cookie("wr_vid"), group: .reading, kinds: ["novel", "article"]),
        CollectSite(id: "qidian", name: "起点", icon: "text.book.closed",
                    loginURL: URL(string: "https://www.qidian.com/")!,
                    domains: ["qidian.com", "yuewen.com"],
                    hint: _L("登录后已购/免费章节正文可抓",
                             "Sign in to fetch chapters you own"),
                    check: .cookieOnly, group: .reading, kinds: ["novel"]),
        CollectSite(id: "fanqie", name: "番茄小说", icon: "book.pages",
                    loginURL: URL(string: "https://fanqienovel.com/")!,
                    domains: ["fanqienovel.com", "fqnovel.com"],
                    hint: _L("登录后章节更全、不易被反爬拦",
                             "Sign in for fuller chapters"),
                    check: .cookie("sessionid"), group: .reading, kinds: ["novel"]),

        // —— 综合 ——
        CollectSite(id: "baidu", name: "百度", icon: "magnifyingglass.circle",
                    loginURL: URL(string: "https://passport.baidu.com/v2/?login")!,
                    domains: ["baidu.com", "bdimg.com", "bdstatic.com"],
                    hint: _L("登录后贴吧/百科大图与图集更少被限流",
                             "Sign in for fewer rate limits on Baidu pages"),
                    check: .cookie("BDUSS"), group: .other, kinds: ["image", "article"]),
        CollectSite(id: "x", name: "X / Twitter", icon: "bird",
                    loginURL: URL(string: "https://x.com/i/flow/login")!,
                    domains: ["x.com", "twitter.com", "twimg.com"],
                    hint: _L("登录后才能看推文图与视频原图（需要能访问 X）",
                             "Sign in for tweet media (needs X access)"),
                    check: .cookie("auth_token"), group: .other, kinds: ["image", "video", "article"]),

        // —— 第二批（2026-09 续）——
        CollectSite(id: "uicn", name: "UI 中国", icon: "uiwindow.split.2x1",
                    loginURL: URL(string: "https://www.ui.cn/login.html")!,
                    domains: ["ui.cn"],
                    hint: _L("登录后可看作品大图与源文件（未登录只有预览）",
                             "Sign in for full-size works and source files"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),
        CollectSite(id: "miyoushe", name: "米游社", icon: "gamecontroller",
                    loginURL: URL(string: "https://user.mihoyo.com/#/login")!,
                    domains: ["miyoushe.com", "mihoyo.com"],
                    hint: _L("登录后同人图 / 攻略正文可完整抓取",
                             "Sign in for fan art and guide posts"),
                    check: .cookieOnly, group: .media, kinds: ["image", "article"]),
        CollectSite(id: "nga", name: "NGA", icon: "bubble.middle.bottom",
                    loginURL: URL(string: "https://bbs.nga.cn/nuke.php?func=login")!,
                    domains: ["nga.cn", "ngacn.cc"],
                    hint: _L("登录后帖子附件图才能看（未登录只给「登录可见」）",
                             "Sign in to see attachments"),
                    check: .cookieOnly, group: .media, kinds: ["image", "article"]),
        CollectSite(id: "tumblr", name: "Tumblr", icon: "t.square",
                    loginURL: URL(string: "https://www.tumblr.com/login")!,
                    domains: ["tumblr.com"],
                    hint: _L("登录后可看高清图与长贴（未登录常限流）",
                             "Sign in for full-resolution images"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),
        CollectSite(id: "px500", name: "500px", icon: "camera.aperture",
                    loginURL: URL(string: "https://500px.com/login")!,
                    domains: ["500px.com"],
                    hint: _L("登录后可下载授权尺寸的原片（未登录只有水印预览）",
                             "Sign in to download licensed originals"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),
        CollectSite(id: "flickr", name: "Flickr", icon: "photo.stack",
                    loginURL: URL(string: "https://identity.flickr.com/signin")!,
                    domains: ["flickr.com", "staticflickr.com"],
                    hint: _L("登录后可取各尺寸原图（含 Commons 免版权老照片）",
                             "Sign in for all sizes incl. Commons"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),
        CollectSite(id: "youku", name: "优酷", icon: "play.rectangle.on.rectangle",
                    loginURL: URL(string: "https://www.youku.com/")!,
                    domains: ["youku.com", "ykimg.com"],
                    hint: _L("登录后能取到更高清的源（未登录只有低清预览）",
                             "Sign in for higher-quality sources"),
                    check: .cookieOnly, group: .media, kinds: ["video"]),
        CollectSite(id: "iqiyi", name: "爱奇艺", icon: "sparkles.tv",
                    loginURL: URL(string: "https://www.iqiyi.com/")!,
                    domains: ["iqiyi.com", "iqiyipic.com", "qy.net"],
                    hint: _L("登录后剧集/片花可跨集抓取，画质更高",
                             "Sign in for more episodes and higher quality"),
                    check: .cookieOnly, group: .media, kinds: ["video"]),
        CollectSite(id: "ixigua", name: "西瓜视频", icon: "watermelon",
                    loginURL: URL(string: "https://www.ixigua.com/")!,
                    domains: ["ixigua.com", "ixiguavideo.com"],
                    hint: _L("登录后视频直链更稳（未登录常 403）",
                             "Sign in for stabler video URLs"),
                    check: .cookieOnly, group: .media, kinds: ["video"]),
        CollectSite(id: "jjwxc", name: "晋江文学城", icon: "book.and.wrench",
                    loginURL: URL(string: "https://www.jjwxc.net/")!,
                    domains: ["jjwxc.net", "jjwxc.com"],
                    hint: _L("登录后已购章节才能抓（未登录只有免费章）",
                             "Sign in to fetch chapters you own"),
                    check: .cookieOnly, group: .reading, kinds: ["novel"]),
        CollectSite(id: "zongheng", name: "纵横中文网", icon: "square.and.pencil",
                    loginURL: URL(string: "https://www.zongheng.com/")!,
                    domains: ["zongheng.com"],
                    hint: _L("登录后章节更全、目录页更完整",
                             "Sign in for fuller chapter lists"),
                    check: .cookieOnly, group: .reading, kinds: ["novel"]),
        CollectSite(id: "juejin", name: "掘金", icon: "hammer",
                    loginURL: URL(string: "https://juejin.cn/login")!,
                    domains: ["juejin.cn"],
                    hint: _L("登录后文章正文与代码块可完整提取",
                             "Sign in for full articles and code blocks"),
                    check: .cookieOnly, group: .reading, kinds: ["article"]),
        CollectSite(id: "csdn", name: "CSDN", icon: "chevron.left.forwardslash.chevron.right",
                    loginURL: URL(string: "https://passport.csdn.net/login")!,
                    domains: ["csdn.net", "csdnimg.cn"],
                    hint: _L("登录后「关注可见 / 展开全文」的文章才抓得到",
                             "Sign in for members-only article bodies"),
                    check: .cookieOnly, group: .reading, kinds: ["article"]),
        CollectSite(id: "sspai", name: "少数派", icon: "doc.richtext",
                    loginURL: URL(string: "https://sspai.com/login")!,
                    domains: ["sspai.com", "sspai.net"],
                    hint: _L("登录后会员文章正文与配图可提取",
                             "Sign in for member-only articles"),
                    check: .cookieOnly, group: .reading, kinds: ["article"]),
        CollectSite(id: "medium", name: "Medium", icon: "m.square",
                    loginURL: URL(string: "https://medium.com/m/signin")!,
                    domains: ["medium.com"],
                    hint: _L("登录后会员文章可读全文（未登录常被截断）",
                             "Sign in to read member-only stories"),
                    check: .cookieOnly, group: .reading, kinds: ["article"]),

        // —— 第三批：图片 / 设计素材站 ——
        CollectSite(id: "tuchong", name: "图虫", icon: "photo.on.rectangle.angled",
                    loginURL: URL(string: "https://tuchong.com/login/")!,
                    domains: ["tuchong.com"],
                    hint: _L("登录后可下原图并看作者参数（未登录只有压缩图）",
                             "Sign in for originals and EXIF"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),
        CollectSite(id: "nipic", name: "昵图网", icon: "photo.stack",
                    loginURL: URL(string: "https://www.nipic.com/")!,
                    domains: ["nipic.com"],
                    hint: _L("登录后才能下原图（未登录只给带水印预览）",
                             "Sign in to download originals"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),
        CollectSite(id: "vcg", name: "视觉中国", icon: "camera.metering.center.weighted",
                    loginURL: URL(string: "https://www.vcg.com/")!,
                    domains: ["vcg.com"],
                    hint: _L("登录后可看大图与授权信息（商用请走正规授权）",
                             "Sign in for large previews and licensing info"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),
        CollectSite(id: "ooopic", name: "我图网", icon: "square.stack.3d.up",
                    loginURL: URL(string: "https://www.ooopic.com/")!,
                    domains: ["ooopic.com"],
                    hint: _L("登录后可下素材原图（未登录只有缩略图）",
                             "Sign in to download assets"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),
        CollectSite(id: "ibaotu", name: "包图网", icon: "shippingbox",
                    loginURL: URL(string: "https://ibaotu.com/")!,
                    domains: ["ibaotu.com"],
                    hint: _L("登录后（会员）可下原图与源文件",
                             "Sign in (member) to download originals"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),
        CollectSite(id: "51miz", name: "觅知网", icon: "wand.and.stars",
                    loginURL: URL(string: "https://www.51miz.com/")!,
                    domains: ["51miz.com"],
                    hint: _L("登录后可下设计素材（未登录只给预览）",
                             "Sign in to download design assets"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),
        CollectSite(id: "699pic", name: "摄图网", icon: "photo.artframe",
                    loginURL: URL(string: "https://699pic.com/")!,
                    domains: ["699pic.com"],
                    hint: _L("登录后可下高清图（未登录有水印）",
                             "Sign in for HD images without watermark"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),
        CollectSite(id: "gaoding", name: "稿定设计", icon: "paintbrush",
                    loginURL: URL(string: "https://www.gaoding.com/")!,
                    domains: ["gaoding.com"],
                    hint: _L("登录后模板大图与元素可导出",
                             "Sign in to export templates and elements"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),
        CollectSite(id: "canva", name: "Canva", icon: "rectangle.3.group",
                    loginURL: URL(string: "https://www.canva.com/login")!,
                    domains: ["canva.com"],
                    hint: _L("登录后模板元素可下载（未登录只有预览）",
                             "Sign in to download template elements"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),
        CollectSite(id: "freepik", name: "Freepik", icon: "sparkles.rectangle.stack",
                    loginURL: URL(string: "https://www.freepik.com/login")!,
                    domains: ["freepik.com"],
                    hint: _L("登录后可下矢量/PSD（免费额度内）",
                             "Sign in to download vectors and PSDs"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),
        CollectSite(id: "vecteezy", name: "Vecteezy", icon: "scribble.variable",
                    loginURL: URL(string: "https://www.vecteezy.com/login")!,
                    domains: ["vecteezy.com"],
                    hint: _L("登录后可下矢量素材（注意授权范围）",
                             "Sign in to download vectors"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),
        CollectSite(id: "dribbble", name: "Dribbble", icon: "basketball",
                    loginURL: URL(string: "https://dribbble.com/session/new")!,
                    domains: ["dribbble.com"],
                    hint: _L("登录后可看高清稿与可下载附件",
                             "Sign in for hi-res shots and attachments"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),
        CollectSite(id: "deviantart", name: "DeviantArt", icon: "theatermasks",
                    loginURL: URL(string: "https://www.deviantart.com/users/login")!,
                    domains: ["deviantart.com", "deviantart.net"],
                    hint: _L("登录后可下原图（未登录只有预览尺寸）",
                             "Sign in to download full-size deviations"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),
        CollectSite(id: "giphy", name: "GIPHY", icon: "rectangle.stack.badge.play",
                    loginURL: URL(string: "https://giphy.com/login")!,
                    domains: ["giphy.com", "giphyusercontent.com"],
                    hint: _L("登录后可下无水印 GIF / 视频（未登录带水印）",
                             "Sign in for watermark-free GIFs"),
                    check: .cookieOnly, group: .media, kinds: ["image", "video"]),
        CollectSite(id: "lofter", name: "LOFTER", icon: "text.below.photo",
                    loginURL: URL(string: "https://www.lofter.com/login")!,
                    domains: ["lofter.com", "lf127.net"],
                    hint: _L("登录后可看大图与长文（未登录常只给缩略图）",
                             "Sign in for full images and posts"),
                    check: .cookieOnly, group: .media, kinds: ["image", "article"]),
        CollectSite(id: "shutterstock", name: "Shutterstock", icon: "photo.circle",
                    loginURL: URL(string: "https://accounts.shutterstock.com/login")!,
                    domains: ["shutterstock.com"],
                    hint: _L("登录后可看大图预览（下载需订阅授权）",
                             "Sign in for large previews (license required)"),
                    check: .cookieOnly, group: .media, kinds: ["image"]),

        // —— 第三批：视频 ——
        CollectSite(id: "acfun", name: "AcFun", icon: "play.rectangle.fill",
                    loginURL: URL(string: "https://www.acfun.cn/login/")!,
                    domains: ["acfun.cn", "aixifan.com"],
                    hint: _L("登录后可看高清与会员内容",
                             "Sign in for HD and member content"),
                    check: .cookieOnly, group: .media, kinds: ["video"]),
        CollectSite(id: "mgtv", name: "芒果 TV", icon: "tv",
                    loginURL: URL(string: "https://www.mgtv.com/")!,
                    domains: ["mgtv.com", "hunantv.com"],
                    hint: _L("登录后可抓剧集/综艺更多集与更高清源",
                             "Sign in for more episodes and HD sources"),
                    check: .cookieOnly, group: .media, kinds: ["video"]),
        CollectSite(id: "sohutv", name: "搜狐视频", icon: "play.square",
                    loginURL: URL(string: "https://tv.sohu.com/")!,
                    domains: ["sohu.com", "itc.cn"],
                    hint: _L("登录后视频直链更稳（未登录常被限流）",
                             "Sign in for stabler video URLs"),
                    check: .cookieOnly, group: .media, kinds: ["video"]),
        CollectSite(id: "vimeo", name: "Vimeo", icon: "v.square",
                    loginURL: URL(string: "https://vimeo.com/log_in")!,
                    domains: ["vimeo.com", "vimeocdn.com"],
                    hint: _L("登录后可下原片（作者允许下载时）",
                             "Sign in to download originals when allowed"),
                    check: .cookieOnly, group: .media, kinds: ["video"]),

        // —— 第三批：文章 ——
        CollectSite(id: "36kr", name: "36 氪", icon: "chart.line.uptrend.xyaxis",
                    loginURL: URL(string: "https://36kr.com/login")!,
                    domains: ["36kr.com"],
                    hint: _L("登录后可读全文（未登录常只给开头）",
                             "Sign in for full articles"),
                    check: .cookieOnly, group: .reading, kinds: ["article"]),
        CollectSite(id: "huxiu", name: "虎嗅", icon: "newspaper",
                    loginURL: URL(string: "https://www.huxiu.com/")!,
                    domains: ["huxiu.com"],
                    hint: _L("登录后可读会员文章与完整正文",
                             "Sign in for member articles"),
                    check: .cookieOnly, group: .reading, kinds: ["article"]),
        CollectSite(id: "ifanr", name: "爱范儿", icon: "iphone",
                    loginURL: URL(string: "https://www.ifanr.com/")!,
                    domains: ["ifanr.com"],
                    hint: _L("登录后正文与配图更完整",
                             "Sign in for fuller articles"),
                    check: .cookieOnly, group: .reading, kinds: ["article"]),
        CollectSite(id: "segmentfault", name: "思否", icon: "curlybraces",
                    loginURL: URL(string: "https://segmentfault.com/user/login")!,
                    domains: ["segmentfault.com"],
                    hint: _L("登录后技术文章与代码块可完整提取",
                             "Sign in for full technical posts"),
                    check: .cookieOnly, group: .reading, kinds: ["article"]),
        CollectSite(id: "cnblogs", name: "博客园", icon: "text.alignleft",
                    loginURL: URL(string: "https://account.cnblogs.com/signin")!,
                    domains: ["cnblogs.com"],
                    hint: _L("登录后部分仅登录可见的文章才抓得到",
                             "Sign in for members-only posts"),
                    check: .cookieOnly, group: .reading, kinds: ["article"]),
        CollectSite(id: "infoq", name: "InfoQ", icon: "info.square",
                    loginURL: URL(string: "https://www.infoq.cn/login")!,
                    domains: ["infoq.cn", "infoq.com"],
                    hint: _L("登录后深度文章可读全文",
                             "Sign in for full-length articles"),
                    check: .cookieOnly, group: .reading, kinds: ["article"]),
        CollectSite(id: "v2ex", name: "V2EX", icon: "bubble.left.and.bubble.right",
                    loginURL: URL(string: "https://www.v2ex.com/signin")!,
                    domains: ["v2ex.com"],
                    hint: _L("登录后可看隐藏内容与附件",
                             "Sign in to see hidden content"),
                    check: .cookieOnly, group: .other, kinds: ["article"]),

        // —— 第三批：小说 ——
        CollectSite(id: "qimao", name: "七猫小说", icon: "cat",
                    loginURL: URL(string: "https://www.qimao.com/")!,
                    domains: ["qimao.com"],
                    hint: _L("登录后章节更全、不易被反爬拦",
                             "Sign in for fuller chapters"),
                    check: .cookieOnly, group: .reading, kinds: ["novel"]),
        CollectSite(id: "faloo", name: "飞卢小说", icon: "bird",
                    loginURL: URL(string: "https://b.faloo.com/")!,
                    domains: ["faloo.com"],
                    hint: _L("登录后已购章节才能抓（未登录只有试读）",
                             "Sign in to fetch purchased chapters"),
                    check: .cookieOnly, group: .reading, kinds: ["novel"]),
        CollectSite(id: "ciweimao", name: "刺猬猫", icon: "pawprint",
                    loginURL: URL(string: "https://www.ciweimao.com/")!,
                    domains: ["ciweimao.com"],
                    hint: _L("登录后已购/免费章节正文可抓",
                             "Sign in for readable chapters"),
                    check: .cookieOnly, group: .reading, kinds: ["novel"]),
        CollectSite(id: "zhangyue", name: "掌阅", icon: "book.closed.fill",
                    loginURL: URL(string: "https://www.zhangyue.com/")!,
                    domains: ["zhangyue.com", "zhangyuecdn.com"],
                    hint: _L("登录后可读书城章节正文",
                             "Sign in to read chapters"),
                    check: .cookieOnly, group: .reading, kinds: ["novel"]),
        CollectSite(id: "17k", name: "17K 小说网", icon: "number.square",
                    loginURL: URL(string: "https://www.17k.com/")!,
                    domains: ["17k.com"],
                    hint: _L("登录后章节更全、目录页更完整",
                             "Sign in for fuller chapters"),
                    check: .cookieOnly, group: .reading, kinds: ["novel"]),
        CollectSite(id: "hoyolab", name: "HoYoLAB", icon: "gamecontroller.fill",
                    loginURL: URL(string: "https://www.hoyolab.com/login")!,
                    domains: ["hoyolab.com"],
                    hint: _L("登录后同人图与攻略正文可完整抓取",
                             "Sign in for fan art and guides"),
                    check: .cookieOnly, group: .media, kinds: ["image", "article"]),
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

import XCTest
@testable import MarkNote

/// 素材采集：需求卡片校验 + 搜索结果解析（离线，用真实页面结构片段）。
final class CollectorTests: XCTestCase {

    // MARK: 需求卡片

    func testRequestRequiredFieldsAndQueryComposition() {
        var r = CollectRequest()
        XCTAssertEqual(r.missing, ["kind", "subject"], "类型与主题都是必填")
        XCTAssertFalse(r.isReady)
        r.kind = "image"
        XCTAssertEqual(r.missing, ["subject"])
        r.subject = "赛博朋克霓虹街道"
        XCTAssertTrue(r.isReady)
        XCTAssertEqual(r.composedQueries().count, 2, "默认中英各一条")
        XCTAssertTrue(r.composedQueries()[0].hasPrefix("赛博朋克霓虹街道"), "中文词以主题开头")
        r.styles = ["极简", "赛博朋克"]
        r.tones = ["冷色"]
        r.palette = ["蓝"]
        r.orientation = CollectOrientation.landscape.rawValue
        let zh = r.chineseQuery()
        XCTAssertTrue(zh.contains("极简"), "风格要进中文搜索词：\(zh)")
        XCTAssertTrue(zh.contains("冷色"), "色调要进搜索词：\(zh)")
        XCTAssertTrue(zh.contains("蓝色"), "主色要进搜索词：\(zh)")
        XCTAssertTrue(zh.contains("横图"), "方向要进搜索词：\(zh)")
        let en = r.englishQuery()
        XCTAssertTrue(en.contains("minimal"), "风格要有英文关键词：\(en)")
        XCTAssertTrue(en.contains("landscape"), "横图要有 landscape：\(en)")
        XCTAssertTrue(en.contains("blue"), "主色要有英文：\(en)")
        r.queries = ["cyberpunk neon street", "赛博朋克 霓虹 街道"]
        XCTAssertEqual(r.composedQueries().count, 2, "AI 给了关键词优先使用")
    }

    // MARK: 详细选项

    func testOptionCatalogIsConsistent() {
        // 每个选项都要有中英对照（搜索词两侧都靠它）
        for list in [CollectOptions.styles, CollectOptions.tones, CollectOptions.palette,
                     CollectOptions.moods, CollectOptions.compositions,
                     CollectOptions.contents, CollectOptions.platforms] {
            XCTAssertFalse(list.isEmpty)
            for item in list {
                XCTAssertFalse(item.zh.isEmpty)
                XCTAssertFalse(item.en.isEmpty, "「\(item.zh)」缺英文关键词")
            }
            XCTAssertEqual(Set(list.map(\.zh)).count, list.count, "选项不能重名")
        }
        XCTAssertEqual(CollectOptions.english("极简", in: CollectOptions.styles), "minimal")
        XCTAssertEqual(CollectOptions.english("不存在的选项", in: CollectOptions.styles), "不存在的选项")
    }

    /// 详细选项要真的变成搜索词与站点筛选参数
    func testDetailedOptionsBecomeQueriesAndFilters() {
        var r = CollectRequest()
        r.kind = "image"
        r.subject = "雪山"
        r.minSize = CollectMinSize.uhd2160.rawValue
        r.orientation = CollectOrientation.portrait.rawValue
        r.imageType = CollectImageType.photo.rawValue
        r.license = CollectLicense.commercial.rawValue
        r.recency = CollectRecency.month.rawValue
        r.transparent = true
        let filters = r.imageFilterParams()
        XCTAssertTrue(filters.contains("imagesize-large"), "尺寸筛选：\(filters)")
        XCTAssertTrue(filters.contains("aspect-tall"), "竖图筛选：\(filters)")
        XCTAssertTrue(filters.contains("photo-photo"), "照片类型：\(filters)")
        XCTAssertTrue(filters.contains("license-L2_L3_L4"), "可商用授权：\(filters)")
        XCTAssertTrue(filters.contains("age-lt43200"), "最近一月：\(filters)")
        XCTAssertTrue(filters.contains("photo-transparent"), "透明背景：\(filters)")
        XCTAssertTrue(r.englishQuery().contains("4k"), "4K 要进英文词：\(r.englishQuery())")

        // 站点限定/排除拼进最终查询
        r.siteFilter = "unsplash.com, pexels.com"
        r.excludeSites = "pinterest.com"
        let q = try? XCTUnwrap(r.searchQueries().first)
        XCTAssertTrue(q?.contains("site:unsplash.com") ?? false, "只看站点：\(q ?? "")")
        XCTAssertTrue(q?.contains("-site:pinterest.com") ?? false, "排除站点：\(q ?? "")")

        // 视频侧：时长 / 清晰度 / 声音 / 字幕 / 平台
        var v = CollectRequest()
        v.kind = "video"
        v.subject = "城市夜景"
        v.videoDuration = CollectVideoDuration.short.rawValue
        v.videoResolution = CollectVideoResolution.fhd.rawValue
        v.videoAudio = CollectVideoAudio.with.rawValue
        v.videoSubtitle = CollectVideoSubtitle.with.rawValue
        v.platforms = ["哔哩哔哩"]
        XCTAssertTrue(v.videoFilterParams().contains("duration-short"))
        let ven = v.englishQuery()
        XCTAssertTrue(ven.contains("1080p"), "清晰度：\(ven)")
        XCTAssertTrue(ven.contains("with audio"), "声音：\(ven)")
        XCTAssertTrue(ven.contains("subtitles"), "字幕：\(ven)")
        XCTAssertTrue(ven.contains("bilibili"), "平台：\(ven)")
    }

    func testDefaultOptionsAreUnrestricted() {
        let r = CollectRequest()
        XCTAssertEqual(r.orientation, CollectOrientation.any.rawValue)
        XCTAssertEqual(r.aspect, CollectAspect.any.rawValue)
        XCTAssertEqual(r.minSize, CollectMinSize.any.rawValue)
        XCTAssertEqual(r.license, CollectLicense.any.rawValue)
        XCTAssertEqual(r.recency, CollectRecency.any.rawValue)
        XCTAssertEqual(r.strictness, CollectStrictness.balanced.rawValue)
        XCTAssertTrue(r.imageFilterParams().isEmpty, "默认不加任何站点筛选")
        XCTAssertTrue(r.videoFilterParams().isEmpty)
        XCTAssertTrue(r.noWatermark, "默认过滤带水印")
        XCTAssertTrue(r.skipDuplicates)
        XCTAssertTrue(r.safeSearch)
        XCTAssertEqual(r.maxImport, 20)
    }

    func testShortNameSanitizesTitle() {
        XCTAssertEqual(CollectorView.shortName("Cyberpunk: Neon / Street | Art"), "Cyberpunk- Neon - Street - Art")
        let long = String(repeating: "a", count: 50)
        XCTAssertEqual(CollectorView.shortName(long).count, 30, "标题截断到 30 字")
        XCTAssertEqual(CollectorView.shortName("   "), "采集", "空标题兜底")
    }

    // MARK: 解析（真实结构片段）

    func testParseImageCandidates() throws {
        // 取自 cn.bing.com/images/async 的真实结构（m 属性为 &quot; 转义 JSON）
        let html = """
        <a class="iusc" href="/images/search?q=x" m="{&quot;cid&quot;:&quot;A1&quot;,&quot;turl&quot;:&quot;https://tse1.mm.bing.net/th?id=O1&quot;,&quot;murl&quot;:&quot;https://example.com/pic/neon.jpg&quot;,&quot;purl&quot;:&quot;https://example.com/post/1&quot;,&quot;t&quot;:&quot;赛博朋克霓虹街道&quot;}"></a>
        <a class="iusc" m="{&quot;cid&quot;:&quot;A2&quot;,&quot;turl&quot;:&quot;https://tse1.mm.bing.net/th?id=O2&quot;,&quot;murl&quot;:&quot;https://example.com/pic/cyber.png&quot;,&quot;purl&quot;:&quot;https://example.org/post/2&quot;,&quot;t&quot;:&quot;Cyber neon&quot;}"></a>
        <a class="iusc" m="{&quot;murl&quot;:&quot;https://example.com/pic/neon.jpg&quot;}"></a>
        """
        let list = CollectorSearch.parseImages(html)
        XCTAssertEqual(list.count, 2, "第三条是重复 murl，应去重；不完整卡片应丢弃")
        XCTAssertEqual(list[0].kind, "image")
        XCTAssertEqual(list[0].title, "赛博朋克霓虹街道")
        XCTAssertEqual(list[0].fullURL?.absoluteString, "https://example.com/pic/neon.jpg")
        XCTAssertEqual(list[0].pageURL?.host, "example.com")
        XCTAssertEqual(list[1].thumbURL.absoluteString, "https://tse1.mm.bing.net/th?id=O2")
    }

    func testParseVideoCandidates() throws {
        // 取自 cn.bing.com/videos/search 的 mmeta 结构
        let html = """
        <div class="mc_vtvc" mmeta="{&quot;mid&quot;:&quot;A654&quot;,&quot;murl&quot;:&quot;https://www.douyin.com/shipin/729752&quot;,&quot;pgurl&quot;:&quot;https://www.douyin.com/shipin/729752&quot;,&quot;turl&quot;:&quot;https://ts2.mm.bing.net/th?id=OVP.abc&amp;pid=15.1&quot;,&quot;vt&quot;:&quot;赛博朋克城市漫游&quot;,&quot;du&quot;:&quot;03:24&quot;}"></div>
        """
        let list = CollectorSearch.parseVideos(html)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].kind, "video")
        XCTAssertEqual(list[0].title, "赛博朋克城市漫游")
        XCTAssertEqual(list[0].duration, "03:24")
        XCTAssertNil(list[0].fullURL, "视频不下载文件本体")
        XCTAssertEqual(list[0].pageURL?.absoluteString, "https://www.douyin.com/shipin/729752")
        XCTAssertTrue(list[0].thumbURL.absoluteString.contains("pid=15.1"), "转义 &amp; 必须还原")
    }

    func testImageExtensionFromMimeAndURL() {
        XCTAssertEqual(NotesStore.imageExt(mime: "image/png", url: URL(string: "https://x/a")!), "png")
        XCTAssertEqual(NotesStore.imageExt(mime: "image/webp; charset=binary", url: URL(string: "https://x/a")!), "webp")
        XCTAssertEqual(NotesStore.imageExt(mime: "", url: URL(string: "https://x/a.jpeg")!), "jpg", "jpeg 归一为 jpg")
        XCTAssertEqual(NotesStore.imageExt(mime: "", url: URL(string: "https://x/a")!), "jpg", "未知默认 jpg")
    }
}

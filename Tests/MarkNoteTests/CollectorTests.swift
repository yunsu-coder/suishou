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
        XCTAssertEqual(r.safetyEnum, .strict, "默认严格过滤（可切适中 / 关闭）")
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
        XCTAssertEqual(list[1].thumbURL?.absoluteString, "https://tse1.mm.bing.net/th?id=O2")
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
        XCTAssertTrue(list[0].thumbURL?.absoluteString.contains("pid=15.1") == true, "转义 &amp; 必须还原")
    }

    func testImageExtensionFromMimeAndURL() {
        XCTAssertEqual(NotesStore.imageExt(mime: "image/png", url: URL(string: "https://x/a")!), "png")
        XCTAssertEqual(NotesStore.imageExt(mime: "image/webp; charset=binary", url: URL(string: "https://x/a")!), "webp")
        XCTAssertEqual(NotesStore.imageExt(mime: "", url: URL(string: "https://x/a.jpeg")!), "jpg", "jpeg 归一为 jpg")
        XCTAssertEqual(NotesStore.imageExt(mime: "", url: URL(string: "https://x/a")!), "jpg", "未知默认 jpg")
    }
}

/// 采集提示词历史：手动输入 + 选项总结都能存、能复用、按工作台隔离
final class CollectHistoryTests: XCTestCase {

    private func makeRequest() -> CollectRequest {
        var r = CollectRequest()
        r.kind = "image"
        r.subject = "赛博朋克霓虹街道"
        r.styles = ["赛博朋克", "电影感"]
        r.tones = ["冷色"]
        r.orientation = CollectOrientation.landscape.rawValue
        r.minSize = CollectMinSize.uhd2160.rawValue
        r.count = 12
        return r
    }

    func testPromptSummaryCoversOptions() {
        let s = makeRequest().promptSummary()
        XCTAssertTrue(s.contains("12"), "数量：\(s)")
        XCTAssertTrue(s.contains("图片"), "类型：\(s)")
        XCTAssertTrue(s.contains("赛博朋克霓虹街道"), "主题：\(s)")
        XCTAssertTrue(s.contains("横图") || s.contains("landscape"), "方向：\(s)")
        XCTAssertTrue(s.contains("4K"), "尺寸：\(s)")
        XCTAssertTrue(s.contains("冷色"), "色调：\(s)")
        XCTAssertTrue(s.contains("无水印"), "默认过滤水印：\(s)")
        XCTAssertFalse(s.contains("（)"), "不该出现空括号：\(s)")
    }

    func testAddingDedupesAndCaps() {
        var r = makeRequest()
        var list: [CollectHistoryEntry] = []
        let first = CollectHistoryEntry(text: "找点赛博朋克图", summary: r.promptSummary(), request: r)
        list = CollectHistoryStore.adding(first, to: list)
        XCTAssertEqual(list.count, 1)
        // 同提示词 + 同摘要 → 更新（不新增）
        var second = first
        second.id = UUID().uuidString
        second.importedCount = 5
        list = CollectHistoryStore.adding(second, to: list)
        XCTAssertEqual(list.count, 1, "同一条提示词只保留一条")
        XCTAssertEqual(list[0].importedCount, 5, "保留最新结果")
        // 不同选项 → 新增，且新条目在最前
        r.count = 30
        let third = CollectHistoryEntry(text: "找点赛博朋克图", summary: r.promptSummary(), request: r)
        list = CollectHistoryStore.adding(third, to: list)
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].summary, third.summary, "新记录排最前")
        // 上限
        for i in 0..<(CollectHistoryStore.limit + 5) {
            var x = CollectRequest()
            x.kind = "image"; x.subject = "主题\(i)"
            list = CollectHistoryStore.adding(CollectHistoryEntry(summary: x.promptSummary(), request: x), to: list)
        }
        XCTAssertEqual(list.count, CollectHistoryStore.limit, "历史有上限")
    }

    func testSaveLoadRoundTripAndWorkspaceIsolation() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("collect-history-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let wsA = URL(fileURLWithPath: "/tmp/工作台A", isDirectory: true)
        let wsB = URL(fileURLWithPath: "/tmp/工作台B", isDirectory: true)
        let entry = CollectHistoryEntry(text: "手打的提示词", summary: "找 8 个图片：猫",
                                        queries: ["猫", "cat"], request: makeRequest())
        XCTAssertTrue(CollectHistoryStore.save([entry], workspace: wsA, baseDir: base))
        let back = CollectHistoryStore.load(workspace: wsA, baseDir: base)
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back[0].text, "手打的提示词")
        XCTAssertEqual(back[0].queries, ["猫", "cat"])
        XCTAssertEqual(back[0].request.subject, "赛博朋克霓虹街道", "整张需求卡都要能恢复")
        XCTAssertTrue(CollectHistoryStore.load(workspace: wsB, baseDir: base).isEmpty,
                      "不同工作台的历史互不干扰")
        XCTAssertNotEqual(CollectHistoryStore.fileURL(workspace: wsA, baseDir: base),
                          CollectHistoryStore.fileURL(workspace: wsB, baseDir: base))
    }
}

/// 图片格式嗅探 + 视频直链识别（修「只有 jpg」「图显示不全」「视频不能播放」）
final class CollectMediaFormatTests: XCTestCase {

    func testSniffedImageFormatByBytes() {
        XCTAssertEqual(NotesStore.sniffedImageFormat(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0])), "png")
        XCTAssertEqual(NotesStore.sniffedImageFormat(Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0])), "jpg")
        XCTAssertEqual(NotesStore.sniffedImageFormat(Data(Array("GIF89a".utf8) + [0, 0])), "gif")
        var webp = Array("RIFF".utf8); webp += [0, 0, 0, 0]; webp += Array("WEBP".utf8)
        XCTAssertEqual(NotesStore.sniffedImageFormat(Data(webp)), "webp")
        let avif: [UInt8] = [0, 0, 0, 0x20] + Array("ftypavif".utf8)
        XCTAssertEqual(NotesStore.sniffedImageFormat(Data(avif)), "avif")
        XCTAssertEqual(NotesStore.sniffedImageFormat(Data([0x42, 0x4D, 0, 0])), "bmp")
        XCTAssertNil(NotesStore.sniffedImageFormat(Data([1, 2, 3, 4])))
    }

    /// WebP 字节伪装成 .jpg：MIME 必须按字节给出，否则 WebView 用 jpeg 解码 → 图裂/显示不全
    func testSniffedMimePrefersBytesOverExtension() {
        var webp = Array("RIFF".utf8); webp += [0, 0, 0, 0]; webp += Array("WEBP".utf8)
        XCTAssertEqual(NotesStore.sniffedMime(Data(webp), fallbackPath: "a.jpg"), "image/webp")
        XCTAssertEqual(NotesStore.sniffedMime(Data([1, 2, 3]), fallbackPath: "a.png"), "image/png",
                       "嗅探不出来时按扩展名兜底")
        XCTAssertNil(NotesStore.sniffedMime(Data([1, 2, 3]), fallbackPath: nil))
    }

    func testImageExtFallsBackToUrlThenJpg() {
        XCTAssertEqual(NotesStore.imageExt(mime: "image/png", url: URL(string: "https://x/a")!), "png")
        XCTAssertEqual(NotesStore.imageExt(mime: "", url: URL(string: "https://x/a.webp")!), "webp")
        XCTAssertEqual(NotesStore.imageExt(mime: "", url: URL(string: "https://x/a")!), "jpg")
    }

    /// 下载回来的字节：图片收、HTML 错误页丢（不然库里会多出「坏图」）
    func testDownloadedBytesMustLookLikeImage() {
        XCTAssertTrue(NotesStore.isProbablyImage(data: Data([0xFF, 0xD8, 0xFF, 0, 0]), mime: ""),
                      "JPEG 头 → 图片")
        XCTAssertTrue(NotesStore.isProbablyImage(data: Data([1, 2, 3]), mime: "image/png"),
                      "Content-Type 说是图片也收")
        XCTAssertFalse(NotesStore.isProbablyImage(
            data: Data(Array("<!DOCTYPE html><html><body>404</body></html>".utf8)), mime: "text/html"),
                       "HTML 错误页必须丢")
        XCTAssertFalse(NotesStore.isProbablyImage(data: Data([1, 2, 3]), mime: "application/octet-stream"),
                       "既认不出又没说图片 → 不收，避免存成坏图")
    }

    func testVideoCandidateKeepsDirectPlayURL() {
        let html = """
        <div class="mc_vtvc" mmeta="{&quot;murl&quot;:&quot;https://cdn.example.com/clip.mp4&quot;,&quot;pgurl&quot;:&quot;https://www.bilibili.com/video/BV1&quot;,&quot;turl&quot;:&quot;https://ts2.mm.bing.net/th?id=O&amp;pid=1&quot;,&quot;vt&quot;:&quot;城市夜景&quot;,&quot;du&quot;:&quot;00:42&quot;}"></div>
        <div class="mc_vtvc" mmeta="{&quot;murl&quot;:&quot;https://www.douyin.com/shipin/729&quot;,&quot;turl&quot;:&quot;https://ts2.mm.bing.net/th?id=O2&quot;,&quot;vt&quot;:&quot;没有直链&quot;}"></div>
        """
        let list = CollectorSearch.parseVideos(html)
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].videoURL?.absoluteString, "https://cdn.example.com/clip.mp4", "直链要留下用于播放")
        XCTAssertEqual(list[0].pageURL?.host, "www.bilibili.com", "页面优先 pgurl")
        XCTAssertNil(list[1].videoURL, "页面地址不是媒体直链，不能当播放源")
        XCTAssertEqual(list[1].pageURL?.host, "www.douyin.com")
        XCTAssertTrue(CollectCandidate.looksLikeMediaURL("https://x/a.MP4?x=1"))
        XCTAssertFalse(CollectCandidate.looksLikeMediaURL("https://x/watch?video=1"))
    }
}

/// 视频卡片解析（真实结构）+ 可播放直链解析
final class CollectVideoPipelineTests: XCTestCase {

    /// 真实 Bing 视频卡片：vrhm 结构化 JSON + data-src-hq 高清封面 + meta 行
    func testParseRealBingVideoCard() {
        let html = """
        <div id="mc_vtvc_video_2" class="mc_vtvc b_canvas isv creator fbc" mmeta="{&quot;mid&quot;:&quot;D982&quot;,&quot;murl&quot;:&quot;https://www.bilibili.com/video/BV1cL411V7Nf/&quot;,&quot;pgurl&quot;:&quot;https://www.bilibili.com/video/BV1cL411V7Nf/&quot;,&quot;turl&quot;:&quot;https://ts4.mm.bing.net/th?id=OVP.aa&amp;pid=15.1&amp;W=160&amp;H=99&quot;,&quot;md5&quot;:&quot;6e25&quot;}">
          <a aria-label="超高质量【城市夜景】来源: bilibili · 时长: 3 分钟34 秒 · 单击以播放。">
            <img height="199" width="354" data-src-hq="https://ts1.tc.mm.bing.net/th/id/OVP.aa?w=354&amp;h=199&amp;qlt=70&amp;pid=2.1" alt="超高质量【城市夜景】" />
            <div class="mc_bc_rc items">3:34</div>
          </a>
          <div class="mc_vtvc_title b_promtxt" title="超高质量【城市夜景】"><strong>超高质量【城市夜景】</strong></div>
          <span class="meta_vc_content">已浏览 20.7万 次</span><span class="meta_pd_content">2021年10月20日</span>
          <span>bilibili</span>
          <div class="vrhdata" vrhm="{&quot;du&quot;:&quot;03:34&quot;,&quot;vt&quot;:&quot;超高质量【城市夜景】&quot;,&quot;purl&quot;:&quot;https://www.bilibili.com/video/BV1cL411V7Nf/&quot;,&quot;pgurl&quot;:&quot;https://www.bilibili.com/video/BV1cL411V7Nf/&quot;,&quot;thid&quot;:&quot;OVP.aa&quot;,&quot;mid&quot;:&quot;D982&quot;,&quot;bv&quot;:8}"></div>
        </div>
        """
        let list = CollectorSearch.parseVideos(html)
        XCTAssertEqual(list.count, 1)
        let c = list[0]
        XCTAssertEqual(c.title, "超高质量【城市夜景】", "标题要来自 vrhm.title")
        XCTAssertEqual(c.duration, "03:34", "时长要来自 vrhm.du")
        XCTAssertEqual(c.sourceLabel, "bilibili")
        XCTAssertTrue(c.thumbURL?.absoluteString.contains("w=354") == true, "要用高清封面 data-src-hq：\(c.thumbURL?.absoluteString ?? "-")")
        XCTAssertEqual(c.pageURL?.host, "www.bilibili.com")
        XCTAssertTrue(c.metaLine?.contains("20.7万") ?? false, "带播放量：\(c.metaLine ?? "")")
        XCTAssertNil(c.videoURL, "B 站卡片没有直链")
    }

    func testVideoResolverExtractsPlayableURL() {
        let base = URL(string: "https://example.com/watch/1")!
        // og:video（property 在前）
        XCTAssertEqual(
            CollectorVideoResolver.playableURL(inHTML:
                #"<meta property="og:video:secure_url" content="https://cdn.example.com/v.mp4">"#, base: base)?.absoluteString,
            "https://cdn.example.com/v.mp4")
        // og:video（content 在前）
        XCTAssertEqual(
            CollectorVideoResolver.playableURL(inHTML:
                #"<meta content="https://cdn.example.com/x.webm" property="og:video">"#, base: base)?.absoluteString,
            "https://cdn.example.com/x.webm")
        // Twitter Player
        XCTAssertEqual(
            CollectorVideoResolver.playableURL(inHTML:
                #"<meta name="twitter:player:stream" content="https://cdn.example.com/t.mp4">"#, base: base)?.absoluteString,
            "https://cdn.example.com/t.mp4")
        // JSON-LD contentUrl（相对地址要按页面补全）
        XCTAssertEqual(
            CollectorVideoResolver.playableURL(inHTML:
                #"<script type="application/ld+json">{"contentUrl":"/media/a.mp4"}</script>"#, base: base)?.absoluteString,
            "https://example.com/media/a.mp4")
        // <video src>
        XCTAssertEqual(
            CollectorVideoResolver.playableURL(inHTML:
                #"<video controls src="https://cdn.example.com/v2.mov"></video>"#, base: base)?.absoluteString,
            "https://cdn.example.com/v2.mov")
        // 不能把 data: / 网页 / 脚本当播放源
        XCTAssertNil(CollectorVideoResolver.playableURL(inHTML:
            #"<meta property="og:video" content="data:image/png;base64,AAAA">"#, base: base))
        XCTAssertNil(CollectorVideoResolver.playableURL(inHTML:
            #"<meta property="og:video" content="https://example.com/watch.html">"#, base: base))
        XCTAssertNil(CollectorVideoResolver.playableURL(inHTML: "<p>没有视频</p>", base: base))
    }

    func testVideoExtensionAndSizeCap() {
        XCTAssertEqual(NotesStore.videoExt(mime: "video/webm", url: URL(string: "https://x/a")!), "webm")
        XCTAssertEqual(NotesStore.videoExt(mime: "video/quicktime", url: URL(string: "https://x/a")!), "mov")
        XCTAssertEqual(NotesStore.videoExt(mime: "", url: URL(string: "https://x/a.MKV")!), "mkv")
        XCTAssertEqual(NotesStore.videoExt(mime: "", url: URL(string: "https://x/a")!), "mp4")
        XCTAssertEqual(NotesStore.maxCollectedVideoBytes, 300 * 1024 * 1024)
    }
}

/// 画质档位：用于「你要 1080P，但账号只能取 360P」这类如实提示
final class CollectQualityRankTests: XCTestCase {
    func testRankMapping() {
        XCTAssertEqual(CollectVideoResolution.rank(of: "360P"), 1)
        XCTAssertEqual(CollectVideoResolution.rank(of: "480P"), 2)
        XCTAssertEqual(CollectVideoResolution.rank(of: "720P"), 3)
        XCTAssertEqual(CollectVideoResolution.rank(of: "1080P"), 4)
        XCTAssertEqual(CollectVideoResolution.rank(of: "1080P60"), 5)
        XCTAssertEqual(CollectVideoResolution.rank(of: "4K"), 6)
        XCTAssertEqual(CollectVideoResolution.rank(of: nil), 0)
        XCTAssertEqual(CollectVideoResolution.rank(of: "未知"), 0)
    }

    func testRequirementComparison() {
        // 要求 ≥1080P（rank 4），只拿到 360P（1）→ 不达标，该提示
        XCTAssertLessThan(CollectVideoResolution.rank(of: "360P"),
                          CollectVideoResolution.fhd.requiredRank)
        // 登录后拿到 1080P → 达标
        XCTAssertGreaterThanOrEqual(CollectVideoResolution.rank(of: "1080P"),
                                    CollectVideoResolution.fhd.requiredRank)
        // 不限就永远达标
        XCTAssertEqual(CollectVideoResolution.any.requiredRank, 0)
        // 4K 要求：1080P 不算达标
        XCTAssertLessThan(CollectVideoResolution.rank(of: "1080P"), CollectVideoResolution.uhd.requiredRank)
    }
}

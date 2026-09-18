import XCTest
@testable import MarkNote

/// 「搜索过滤三档 + 贴链接导入」：参数映射、老记录迁移、直链识别、页面媒体解析。
final class CollectorLinkImportTests: XCTestCase {

    // MARK: - 搜索过滤等级

    func testSafetyLevelsMapToBingParam() {
        XCTAssertEqual(CollectSafety.strict.bingValue, "strict")
        XCTAssertEqual(CollectSafety.moderate.bingValue, "moderate")
        XCTAssertEqual(CollectSafety.off.bingValue, "off", "关闭 = 完全不传过滤")
        XCTAssertEqual(CollectSafety.allCases.count, 3)
    }

    func testSafetyMigratesFromLegacyBool() throws {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        // 老记录：safeSearch=false 应迁移成「关闭」
        let legacyOff = """
        {"kind":"image","subject":"x","safeSearch":false}
        """
        let off = try dec.decode(CollectRequest.self, from: Data(legacyOff.utf8))
        XCTAssertEqual(off.safetyEnum, .off)
        // 老记录没这个字段 → 默认严格
        let legacyNil = try dec.decode(CollectRequest.self, from: Data(#"{"kind":"image"}"#.utf8))
        XCTAssertEqual(legacyNil.safetyEnum, .strict)
        // 新字段优先
        let modern = try dec.decode(CollectRequest.self,
                                    from: Data(#"{"kind":"image","safety":"moderate","safeSearch":false}"#.utf8))
        XCTAssertEqual(modern.safetyEnum, .moderate)
    }

    // MARK: - 贴链接导入

    func testExtensionClassification() {
        XCTAssertEqual(CollectorLinkImport.kindForExtension("JPG"), "image")
        XCTAssertEqual(CollectorLinkImport.kindForExtension("png"), "image")
        XCTAssertEqual(CollectorLinkImport.kindForExtension("mp4"), "video")
        XCTAssertEqual(CollectorLinkImport.kindForExtension("webm"), "video")
        XCTAssertNil(CollectorLinkImport.kindForExtension("html"))
        XCTAssertNil(CollectorLinkImport.kindForExtension(""))
    }

    func testDirectLinksBecomeCandidates() async throws {
        let image = try XCTUnwrap(URL(string: "https://pbs.twimg.com/media/ABC?format=jpg&name=orig"))
        // 带查询串的直链：扩展名判定看 path，这里用无查询的形式
        let plainImage = try XCTUnwrap(URL(string: "https://pbs.twimg.com/media/photo.jpg"))
        let imageCandidate = await CollectorLinkImport.candidate(for: plainImage)
        XCTAssertEqual(imageCandidate?.kind, "image")
        XCTAssertEqual(imageCandidate?.fullURL, plainImage)
        XCTAssertEqual(imageCandidate?.sourceLabel, "pbs.twimg.com")
        _ = image

        let video = try XCTUnwrap(URL(string: "https://video.twimg.com/amplify_video/1/vid/720x1280/clip.mp4"))
        let videoCandidate = await CollectorLinkImport.candidate(for: video)
        XCTAssertEqual(videoCandidate?.kind, "video")
        XCTAssertEqual(videoCandidate?.videoURL, video)
    }

    /// X / 微博这类页面：从 og:video / og:image 里取媒体（不绕过站点门槛，只读页面已有的元数据）
    func testPageMediaExtraction() throws {
        let html = """
        <html><head>
        <meta property="og:title" content="一条帖子 &amp; 视频">
        <meta property="og:image" content="https://pbs.twimg.com/media/thumb.jpg">
        <meta property="og:video:secure_url" content="https://video.twimg.com/amplify_video/1/vid/720x1280/clip.mp4">
        </head><body>...</body></html>
        """
        let base = try XCTUnwrap(URL(string: "https://x.com/someone/status/1234567890"))
        let media = CollectorLinkImport.mediaURLs(inHTML: html, base: base)
        XCTAssertEqual(media.video?.absoluteString,
                       "https://video.twimg.com/amplify_video/1/vid/720x1280/clip.mp4")
        XCTAssertEqual(media.image?.absoluteString, "https://pbs.twimg.com/media/thumb.jpg")
    }

    func testRelativeMediaURLsAreResolved() throws {
        let html = #"<meta property="og:image" content="/media/photo.jpg">"#
        let base = try XCTUnwrap(URL(string: "https://example.com/post/1"))
        let media = CollectorLinkImport.mediaURLs(inHTML: html, base: base)
        XCTAssertEqual(media.image?.absoluteString, "https://example.com/media/photo.jpg")
        XCTAssertNil(media.video)
    }

    func testNoMediaInPlainPage() throws {
        let base = try XCTUnwrap(URL(string: "https://example.com/"))
        let media = CollectorLinkImport.mediaURLs(inHTML: "<html><body>nothing</body></html>", base: base)
        XCTAssertNil(media.video)
        XCTAssertNil(media.image)
    }

    func testBatchParsingReportsBadLines() async {
        let (items, failures) = await CollectorLinkImport.candidates(from: """
        不是链接
        https://pbs.twimg.com/media/photo.jpg

        """)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(failures.count, 1)
        XCTAssertTrue(failures[0].contains("不是有效的"), failures[0])
    }

    // MARK: - 采集代理（访问 X / YouTube 常必需）

    func testProxyParsing() {
        XCTAssertEqual(CollectorNet.parseProxy("127.0.0.1:7890")?.host, "127.0.0.1")
        XCTAssertEqual(CollectorNet.parseProxy("127.0.0.1:7890")?.port, 7890)
        XCTAssertEqual(CollectorNet.parseProxy("http://127.0.0.1:7890")?.port, 7890)
        XCTAssertEqual(CollectorNet.parseProxy(" http://localhost:1087/ ")?.host, "localhost")
        XCTAssertNil(CollectorNet.parseProxy(nil))
        XCTAssertNil(CollectorNet.parseProxy(""))
        XCTAssertNil(CollectorNet.parseProxy("127.0.0.1"), "缺端口")
        XCTAssertNil(CollectorNet.parseProxy("127.0.0.1:99999"), "端口越界")
        XCTAssertNil(CollectorNet.parseProxy("a:b:c"), "格式不对")
    }

    func testProxyConfigurationAppliesToCollectorSession() {
        let old = CollectorPrefs.proxy
        defer { CollectorPrefs.proxy = old }
        CollectorPrefs.proxy = nil
        XCTAssertNil(CollectorNet.configuration.connectionProxyDictionary, "直连时不带代理配置")
        CollectorPrefs.proxy = "127.0.0.1:7890"
        let dict = CollectorNet.configuration.connectionProxyDictionary
        XCTAssertEqual(dict?["HTTPProxy"] as? String, "127.0.0.1")
        XCTAssertEqual(dict?["HTTPPort"] as? Int, 7890)
        XCTAssertEqual(dict?["HTTPSProxy"] as? String, "127.0.0.1")
        CollectorPrefs.proxy = nil
    }
}

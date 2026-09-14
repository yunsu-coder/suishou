import XCTest
@testable import MarkNote

/// 视频「下载成本地视频」链路：B 站接口解析 / 抖音页面解析 / 画质标注
final class CollectorVideoResolveTests: XCTestCase {

    func testBilibiliVideoIDExtraction() {
        XCTAssertEqual(CollectorVideoResolver.bilibiliVideoID(
            from: URL(string: "https://www.bilibili.com/video/BV1cL411V7Nf/?share=1")!), "BV1cL411V7Nf")
        XCTAssertEqual(CollectorVideoResolver.bilibiliVideoID(
            from: URL(string: "https://www.bilibili.com/video/av463713196")!), "av463713196")
        XCTAssertNil(CollectorVideoResolver.bilibiliVideoID(from: URL(string: "https://example.com/x")!))
    }

    func testBilibiliViewJSONGivesCID() throws {
        let json = """
        {"code":0,"data":{"bvid":"BV1cL411V7Nf","aid":463713196,"cid":428175837,"title":"超高质量【城市夜景】"}}
        """
        let info = try XCTUnwrap(CollectorVideoResolver.bilibiliCID(fromViewJSON: Data(json.utf8)))
        XCTAssertEqual(info.cid, 428175837)
        XCTAssertEqual(info.title, "超高质量【城市夜景】")
        XCTAssertNil(CollectorVideoResolver.bilibiliCID(fromViewJSON: Data(#"{"code":-400}"#.utf8)))
    }

    func testBilibiliPlayJSONGivesDirectURLAndQuality() throws {
        let json = """
        {"code":0,"data":{"quality":16,"format":"flv","durl":[
          {"order":1,"length":213035,"size":10938168,"url":"https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/x.flv"}]}}
        """
        let r = try XCTUnwrap(CollectorVideoResolver.bilibiliPlayURL(fromPlayJSON: Data(json.utf8)))
        XCTAssertEqual(r.url.host, "upos-sz-mirrorcos.bilivideo.com")
        XCTAssertEqual(r.quality, 16)
        XCTAssertEqual(CollectorVideoResolver.qualityLabel(16), "360P")
        XCTAssertEqual(CollectorVideoResolver.qualityLabel(80), "1080P")
        XCTAssertNil(CollectorVideoResolver.bilibiliPlayURL(fromPlayJSON: Data(#"{"code":0,"data":{"durl":[]}}"#.utf8)))
    }

    func testDouyinPageJSONGivesPlayURL() {
        let html = """
        <script>window._ROUTER_DATA = {"loaderData":{"video_(id)/page":{"videoInfoRes":{"item_list":[
        {"video":{"play_addr":{"uri":"v0200","url_list":["https:\\/\\/aweme.snssdk.com\\/aweme\\/v1\\/play\\/x.mp4?a=1&b=2"]}}}]}}}};</script>
        """
        let url = CollectorVideoResolver.douyinPlayURL(fromPageHTML: html)
        XCTAssertEqual(url?.absoluteString, "https://aweme.snssdk.com/aweme/v1/play/x.mp4?a=1&b=2")
        XCTAssertNil(CollectorVideoResolver.douyinPlayURL(fromPageHTML: "<html>无视频</html>"))
    }

    func testResolvedQualityLabelIsHonest() {
        // 无登录时 B 站只给 360P —— 界面要如实显示，而不是假装高清
        XCTAssertEqual(CollectorVideoResolver.qualityLabel(nil), nil)
        XCTAssertEqual(CollectorVideoResolver.qualityLabel(64), "720P")
        XCTAssertEqual(CollectorVideoResolver.qualityLabel(120), nil)
    }
}

/// B 站登录：cookie 拼接规则（登录后接口才给 1080P）
@MainActor
final class BilibiliLoginTests: XCTestCase {
    func testCookieHeaderPicksBilibiliAndDedupes() {
        let header = BilibiliLogin.cookieHeader(from: [
            (name: "SESSDATA", value: "abc", domain: ".bilibili.com"),
            (name: "bili_jct", value: "def", domain: ".bilibili.com"),
            (name: "SESSDATA", value: "old", domain: ".bilibili.com"),
            (name: "other", value: "x", domain: ".example.com"),
            (name: "empty", value: "", domain: ".bilibili.com"),
        ])
        XCTAssertEqual(header, "SESSDATA=old; bili_jct=def", "只取 bilibili 域、同名去重、空值丢弃")
        XCTAssertNil(BilibiliLogin.cookieHeader(from: [(name: "a", value: "b", domain: ".example.com")]),
                     "非 bilibili cookie 不参与")
        XCTAssertNil(BilibiliLogin.cookieHeader(from: []))
    }

    func testCollectorPrefsRoundTrip() {
        let old = CollectorPrefs.bilibiliCookie
        defer { CollectorPrefs.bilibiliCookie = old }
        CollectorPrefs.bilibiliCookie = "SESSDATA=x"
        XCTAssertEqual(CollectorPrefs.bilibiliCookie, "SESSDATA=x")
        CollectorPrefs.bilibiliCookie = nil
        XCTAssertNil(CollectorPrefs.bilibiliCookie, "清空后应为 nil（不是空串）")
    }
}

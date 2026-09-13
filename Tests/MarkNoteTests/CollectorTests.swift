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
        r.style = "极简"
        XCTAssertEqual(r.composedQueries(), ["极简 赛博朋克霓虹街道"], "无 AI 关键词时按 风格+主题 拼接")
        r.queries = ["cyberpunk neon street", "赛博朋克 霓虹 街道"]
        XCTAssertEqual(r.composedQueries().count, 2, "AI 给了关键词优先使用")
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

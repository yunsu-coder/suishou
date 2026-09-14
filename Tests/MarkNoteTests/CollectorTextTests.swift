import XCTest
@testable import MarkNote

/// 采集「文章 / 小说」：网页结果解析、Bing 跳转还原、章节目录识别、成书、落盘成 .md。
final class CollectorTextTests: XCTestCase {

    // MARK: - 搜索结果解析

    func testParseWebResultsWithBingRedirect() {
        let html = """
        <ol id="b_results">
        <li class="b_algo"><h2><a href="https://www.bing.com/ck/a?!&amp;&amp;p=1&u=a1aHR0cHM6Ly9leGFtcGxlLmNvbS9hP2I9MQ">
        三体：一部硬科幻的<strong>结构分析</strong></a></h2>
        <div class="b_caption"><p>从黑暗森林法则谈到叙事结构，本文给出长篇分析。</p></div></li>
        <li class="b_algo"><h2><a href="https://novel.example.com/book/1">三体 小说 在线阅读 全文阅读</a></h2>
        <p>三体全本小说目录，共 88 章，在线阅读。</p></li>
        <li class="b_algo"><h2><a href="javascript:void(0)">无效</a></h2><p>跳过</p></li>
        </ol>
        """
        let list = CollectorSearch.parseWebResults(html)
        XCTAssertEqual(list.count, 2, "javascript: 链接不该进候选")
        XCTAssertEqual(list[0].pageURL?.absoluteString, "https://example.com/a?b=1",
                       "Bing 跳转链接要还原成真实地址")
        XCTAssertEqual(list[0].title, "三体：一部硬科幻的结构分析", "标题要去掉内部标签")
        XCTAssertTrue(list[0].excerpt?.contains("黑暗森林法则") == true)
        XCTAssertEqual(list[0].sourceLabel, "example.com")
        XCTAssertEqual(list[0].kind, "article")
        XCTAssertEqual(list[1].kind, "novel", "带「目录 / 在线阅读 / 章」的更像小说目录页")
    }

    func testBingRealURLKeepsPlainLinks() {
        XCTAssertEqual(CollectorSearch.bingRealURL("https://a.example/x"), "https://a.example/x")
        XCTAssertEqual(CollectorSearch.bingRealURL(
            "https://www.bing.com/ck/a?u=a1aHR0cHM6Ly93d3cucWlkaWFuLmNvbS9ib29rLzEwMTA0NjA4ODUv"),
            "https://www.qidian.com/book/1010460885/")
    }

    // MARK: - 章节目录

    func testChapterListExtractionAndOrdering() throws {
        let html = """
        <html><body>
        <div class="bookinfo"><h1>测试小说</h1></div>
        <div id="list">
          <dl>
            <dd><a href="/book/2.html">第二章 出发</a></dd>
            <dd><a href="/book/1.html">第一章 起点</a></dd>
            <dd><a href="/book/10.html">第十章 归途</a></dd>
          </dl>
        </div>
        <div class="bottem"><a href="/book/1.html">上一章</a><a href="/book/3.html">下一章</a>
        <a href="/book/">目录</a></div>
        </body></html>
        """
        let base = try XCTUnwrap(URL(string: "https://novel.example.com/book/"))
        let chapters = NovelCollector.chapters(inHTML: html, base: base)
        XCTAssertEqual(chapters.map(\.title), ["第一章 起点", "第二章 出发", "第十章 归途"],
                       "要按章节号排序、去掉上下章导航")
        XCTAssertEqual(chapters.map(\.number), [1, 2, 10])
        XCTAssertEqual(chapters[0].url.absoluteString, "https://novel.example.com/book/1.html")
    }

    func testChapterNumberParsing() {
        XCTAssertEqual(NovelCollector.chapterNumber(inTitle: "第12章 起风了"), 12)
        XCTAssertEqual(NovelCollector.chapterNumber(inTitle: "第一百二十三章 大结局"), 123)
        XCTAssertEqual(NovelCollector.chapterNumber(inTitle: "第十二节"), 12)
        XCTAssertEqual(NovelCollector.chapterNumber(inTitle: "第 3 回 桃园结义"), 3)
        XCTAssertNil(NovelCollector.chapterNumber(inTitle: "楔子"))
        XCTAssertEqual(NovelCollector.chineseNumber("十"), 10)
        XCTAssertEqual(NovelCollector.chineseNumber("一百零三"), 103)
        XCTAssertEqual(NovelCollector.chineseNumber("两千零一"), 2001)
        XCTAssertEqual(NovelCollector.chineseNumber("一零零"), 100, "逐位写法：第一零零回 = 第100回")
        XCTAssertEqual(NovelCollector.chineseNumber("零五"), 5)
        XCTAssertEqual(NovelCollector.chapterNumber(inTitle: "第一零零回：径回东土"), 100)
    }

    func testNavigationLinksAreNotChapters() {
        XCTAssertTrue(NovelCollector.isNavigation("上一章"))
        XCTAssertTrue(NovelCollector.isNavigation("返回目录"))
        XCTAssertTrue(NovelCollector.isNavigation("加入书架"))
        XCTAssertFalse(NovelCollector.isNavigation("第一章 起点"))
        XCTAssertFalse(NovelCollector.isNavigation("第七章：雨夜"))
    }

    /// 百科 / 导航站的「目录容器」里全是普通链接，不能当成章节目录（否则抓回来一堆导航页）
    func testNavHeavyCatalogIsNotAChapterList() throws {
        let html = """
        <html><body><div id="catalog" class="catalog">
        <a href="/item/1">人物介绍</a><a href="/item/2">出版信息</a><a href="/item/3">作者简介</a>
        <a href="/item/4">相关作品</a><a href="/item/5">影视改编</a><a href="/item/6">获奖记录</a>
        </div></body></html>
        """
        let base = try XCTUnwrap(URL(string: "https://baike.example.com/item/9"))
        XCTAssertTrue(NovelCollector.chapters(inHTML: html, base: base).isEmpty,
                      "没有「第X章」链接的页面不算小说目录")
    }

    // MARK: - 成书 / 成篇

    func testBookNoteAssembly() throws {
        let book = NovelCollector.bookNote(
            bookTitle: "测试小说",
            source: try XCTUnwrap(URL(string: "https://novel.example.com/book/")),
            chapters: [("第一章 起点", "他出发了。"), ("第二章 出发", "雨很大。")],
            collectedAt: Date(timeIntervalSince1970: 1_760_000_000))
        XCTAssertTrue(book.hasPrefix("# 测试小说\n\n> 来源：<https://novel.example.com/book/>"))
        XCTAssertTrue(book.contains("## 第一章 起点\n\n他出发了。"))
        XCTAssertTrue(book.contains("## 第二章 出发\n\n雨很大。"))
        XCTAssertTrue(book.contains("采集于 "))
    }

    func testArticleNoteAssembly() throws {
        let note = NovelCollector.articleNote(title: "一篇长文",
                                              source: try XCTUnwrap(URL(string: "https://blog.example.com/p/1")),
                                              markdown: "正文第一段。\n\n正文第二段。",
                                              collectedAt: Date(timeIntervalSince1970: 1_760_000_000))
        XCTAssertTrue(note.hasPrefix("# 一篇长文\n\n> 来源：<https://blog.example.com/p/1>"))
        XCTAssertTrue(note.contains("正文第一段。"))
    }

    // MARK: - 落盘成工作台笔记

    @MainActor
    func testSaveCollectedMarkdownIntoWorkspace() throws {
        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let rel = try XCTUnwrap(store.saveCollectedMarkdown("# 标题\n\n正文", title: "三体/第一部: 测试"),
                                "应能写进工作台")
        XCTAssertEqual(rel, "三体-第一部 测试.md", "文件名要清洗掉 / 与 :")
        let text = try String(contentsOf: dir.appendingPathComponent(rel), encoding: .utf8)
        XCTAssertEqual(text, "# 标题\n\n正文")
        // 重名 → 自动加序号，绝不覆盖
        let second = try XCTUnwrap(store.saveCollectedMarkdown("# 另一个", title: "三体/第一部: 测试"))
        XCTAssertNotEqual(second, rel)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(second).path))
        // 一章一文件模式：进同名文件夹
        let inFolder = try XCTUnwrap(store.saveCollectedMarkdown("# 章", title: "第一章 起点", folder: "测试小说"))
        XCTAssertEqual(inFolder, "测试小说/第一章 起点.md")
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("测试小说").path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    // MARK: - 需求与旧记录兼容

    func testTextKindRequestSummaryAndDefaults() {
        var r = CollectRequest()
        XCTAssertFalse(r.isTextKind)
        r.kind = "novel"
        r.subject = "三体"
        r.chapterLimit = 40
        XCTAssertTrue(r.isTextKind)
        let summary = r.promptSummary()
        XCTAssertTrue(summary.contains("小说"), summary)
        XCTAssertTrue(summary.contains("40 章"), summary)
        XCTAssertTrue(r.searchQueries().first?.contains("小说") == true, "中文搜索词要带体裁")
    }

    func testOldHistoryJSONStillDecodes() throws {
        // 老版本存的记录没有 chapterLimit / mergeChapters：必须能读出来（否则历史整份丢）
        let json = """
        [{"request":{"kind":"image","subject":"赛博朋克","count":12,"skipDuplicates":true,
          "maxImport":20,"styles":["二次元"]},"summary":"找 12 个图片：赛博朋克","queries":[],
          "text":"","importedCount":3,"createdAt":"2026-09-13T16:55:44Z","id":"x1"}]
        """
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let list = try dec.decode([CollectHistoryEntry].self, from: Data(json.utf8))
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].request.subject, "赛博朋克")
        XCTAssertEqual(list[0].request.chapterLimit, 30, "缺字段回默认值")
        XCTAssertTrue(list[0].request.mergeChapters)
        XCTAssertEqual(list[0].importedCount, 3)
    }
}

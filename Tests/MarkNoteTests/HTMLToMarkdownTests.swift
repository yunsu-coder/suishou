import XCTest
@testable import MarkNote

/// HTML → Markdown：正文提取、标签转换、实体解码、广告行清理。
final class HTMLToMarkdownTests: XCTestCase {

    func testBlogArticleConversion() {
        let html = """
        <html><head><title>标题</title><style>body{color:red}</style>
        <script>var x = 1 < 2;</script></head>
        <body>
        <nav><a href="/">首页</a><a href="/about">关于</a></nav>
        <article>
          <h1>如何写好一篇技术笔记</h1>
          <p>先写<strong>结论</strong>，再写<em>过程</em>。</p>
          <p>参考 <a href="/docs/style">写作规范</a> 与 <a href="https://example.com/x">外部链接</a>。</p>
          <h2>要点</h2>
          <ul><li>一句话说清结论</li><li>过程要能复现<ul><li>环境版本</li><li>关键命令</li></ul></li></ul>
          <blockquote><p>写给别人看得懂的字。</p></blockquote>
          <pre><code class="language-swift">let a = 1
          print(a)</code></pre>
          <p><img src="/img/a.png" alt="示意图"></p>
          <hr>
          <table><tr><th>项</th><th>说明</th></tr><tr><td>速度</td><td>快</td></tr></table>
        </article>
        <footer>版权所有 &copy; 2026</footer>
        </body></html>
        """
        let md = HTMLToMarkdown.convert(html, baseURL: URL(string: "https://blog.example.com/post/1"))
        print("MD-BLOG >>>\n\(md)\n<<<")
        XCTAssertTrue(md.hasPrefix("# 如何写好一篇技术笔记"), "h1 要成 # 标题：\n\(md)")
        XCTAssertTrue(md.contains("先写**结论**，再写*过程*。"))
        XCTAssertTrue(md.contains("[写作规范](https://blog.example.com/docs/style)"), "相对链接要绝对化")
        XCTAssertTrue(md.contains("[外部链接](https://example.com/x)"))
        XCTAssertTrue(md.contains("## 要点"))
        XCTAssertTrue(md.contains("- 一句话说清结论"))
        XCTAssertTrue(md.contains("  - 环境版本"), "嵌套列表要缩进：\n\(md)")
        XCTAssertTrue(md.contains("> 写给别人看得懂的字。"))
        XCTAssertTrue(md.contains("```swift\nlet a = 1"), "代码块要带语言：\n\(md)")
        XCTAssertTrue(md.contains("![示意图](https://blog.example.com/img/a.png)"))
        XCTAssertTrue(md.contains("---"))
        XCTAssertTrue(md.contains("| 项 | 说明 |"))
        XCTAssertTrue(md.contains("| 速度 | 快 |"))
        XCTAssertFalse(md.contains("color:red"), "样式要删干净")
        XCTAssertFalse(md.contains("var x"), "脚本要删干净")
        XCTAssertFalse(md.contains("首页"), "导航要删干净")
        XCTAssertFalse(md.contains("版权所有"), "页脚要删干净")
    }

    func testChineseNovelChapterCleaning() {
        let html = """
        <html><body>
        <div class="header"><a href="/">首页</a> · <a href="/list">目录</a></div>
        <div id="chaptercontent" class="content read-content">
          <p>　　第一章 起点</p>
          <p>　　他抬头看了看天，云很薄，风也不大。</p>
          <p>请记住本站域名 www.example.com</p>
          <p>　　“走吧。”他说。</p>
          <p>笔趣阁最快更新！</p>
        </div>
        <div class="footer">加入书签 | 上一章 | 下一章</div>
        </body></html>
        """
        let md = HTMLToMarkdown.convert(html, baseURL: URL(string: "https://novel.example.com/book/1/2.html"))
        print("MD-NOVEL >>>\n\(md)\n<<<")
        XCTAssertTrue(md.contains("他抬头看了看天，云很薄，风也不大。"))
        XCTAssertTrue(md.contains("“走吧。”他说。"))
        XCTAssertFalse(md.contains("请记住本站"), "广告行要删掉")
        XCTAssertFalse(md.contains("笔趣阁"), "站点广告要删掉")
        XCTAssertFalse(md.contains("加入书签"), "页脚导航要删掉")
    }

    func testEntityDecodingAndWordCount() {
        XCTAssertEqual(HTMLToMarkdown.decodeEntities("&nbsp;&amp;&lt;&#x4E2D;&#25991;&#128512;"),
                       " &<中文😀")
        XCTAssertEqual(HTMLToMarkdown.decodeEntities("&hellip;&mdash;&quot;x&quot;"), "…—\"x\"")
        // 汉字按字算，英文按词算
        XCTAssertEqual(HTMLToMarkdown.wordCount("你好世界 hello world 123"), 4 + 3)
    }

    func testLinkTextRatioFlagsNavigationPages() {
        let nav = "- [首页](http://a.com)\n- [新闻](http://news.a.com)\n- [体育](http://sports.a.com)"
        XCTAssertGreaterThan(HTMLToMarkdown.linkTextRatio(nav), 0.8, "导航页链接占比必须高")
        let article = "这是一篇正常文章的第一段，文字很多很多。" + String(repeating: "正文内容。", count: 20)
            + " 参考 [规范](https://example.com)。"
        XCTAssertLessThan(HTMLToMarkdown.linkTextRatio(article), 0.15, "正常正文链接占比低")
    }

    func testMainContentPrefersArticleOverLinkHeavyList() {
        let html = """
        <body>
        <div class="chapter-list"><a href="/c1">第一章</a><a href="/c2">第二章</a></div>
        <div id="content"><p>\(String(repeating: "正文内容。", count: 60))</p></div>
        </body>
        """
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("正文内容。"))
        XCTAssertFalse(md.contains("第二章"), "链接堆不该被当正文：\n\(md)")
    }

    func testPlainTextAndTitle() {
        let html = "<html><head><title>  三体 · 第一章  </title></head><body><article><p>正文</p></article></body></html>"
        XCTAssertEqual(HTMLToMarkdown.pageTitle(inHTML: html), "三体 · 第一章")
        XCTAssertEqual(HTMLToMarkdown.plainText("<div><p>你好 <b>世界</b></p></div>"), "你好 世界")
    }
}

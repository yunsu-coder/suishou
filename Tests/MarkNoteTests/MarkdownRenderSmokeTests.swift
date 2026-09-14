import XCTest
import WebKit
import Foundation
@testable import MarkNote

/// 全语法预览 smoke：在真实 WKWebView 中渲染，按 DOM 断言支持的 Markdown 扩展。
final class MarkdownRenderSmokeTests: XCTestCase {

    private func loadPreviewWeb() throws -> WKWebView {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let resources = root.appendingPathComponent(".build/arm64-apple-macosx/debug/MarkNote_MarkNote.bundle/Resources")
        let html = resources.appendingPathComponent("preview.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: html.path))

        let web = WKWebView(frame: NSRect(x: -5000, y: -5000, width: 800, height: 600))
        web.loadFileURL(html, allowingReadAccessTo: resources)
        var lastValue: Any?
        var lastError: Error?
        for _ in 0..<60 {
            var value: Any?
            var error: Error?
            let e = expectation(description: "preview-ready")
            web.evaluateJavaScript("typeof window.renderMd") { r, err in value = r; error = err; e.fulfill() }
            wait(for: [e], timeout: 2)
            if (value as? String) == "function" { return web }
            lastValue = value
            lastError = error
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTFail("预览渲染管线未就绪: value=\(String(describing: lastValue)) err=\(String(describing: lastError))")
        return web
    }

    func testAllDocumentedSyntaxRenders() throws {
        let web = try loadPreviewWeb()
        let md = """
        # 标题

        [TOC]

        ::: tip
        **callout** 内容
        :::
        脚注引用[^1]。

        [^1]: 脚注定义

        - [x] 已完成
        - [ ] 未完成

        ==高亮== ~下标~ ^上标^ ++插入++

        ~~删除线~~

        :smile:

        行内公式 $E=mc^2$

        价格 $100 与 $200 不是公式。

        $$
        a^2+b^2=c^2
        $$

        ```mermaid
        graph TD
        A-->B
        ```

        ```swift
        let x = 1
        ```

        行内代码 `$x$`、`::: tip`、`@[x](y.pdf)` 应保持原文。

        ```bash
        echo $HOME
        ::: tip
        inside
        :::
        @[x](source/pdf/y.pdf)
        ```

        | A | B |
        | --- | --- |
        | 1 | 2 |

        @[文档](source/pdf/demo.pdf)

        ![图片](source/image/demo.png){width=320, caption=图注}

        ![视频](source/mp4/demo.mp4)

        ![音频](source/mp3/demo.mp3)
        """
        let mdJSON = try jsonString(md)
        let script = """
        window.__enabledModules = {};
        window.renderMd(\(mdJSON), "file:///", { dark: false, resetScroll: true });
        JSON.stringify({
          callout: document.querySelectorAll('.callout-tip').length,
          footnote: document.querySelectorAll('.footnote-ref').length,
          tasks: document.querySelectorAll('.task-list-item').length,
          mark: document.querySelectorAll('mark').length,
          sub: document.querySelectorAll('sub').length,
          sup: document.querySelectorAll('sup').length,
          ins: document.querySelectorAll('ins').length,
          katex: document.querySelectorAll('.katex').length,
          inlineDisplay: (function () {
            var all = document.querySelectorAll('.katex');
            for (var i = 0; i < all.length; i++) {
              var a = all[i].querySelector('annotation');
              if (a && a.textContent.indexOf('E=mc^2') >= 0) {
                return all[i].closest('.katex-display') ? 1 : 0;
              }
            }
            return -1;
          })(),
          code: document.querySelectorAll('pre[data-lang="swift"]').length,
          hl: document.querySelectorAll('pre[data-lang="swift"] .hljs-keyword').length,
          codeMath: document.querySelectorAll('pre .katex, code .katex').length,
          fenceRaw: (function () {
            var c = document.querySelector('pre[data-lang="bash"] code');
            if (!c) return 0;
            var t = c.textContent || '';
            return t.indexOf('echo $HOME') >= 0 && t.indexOf('::: tip') >= 0
                && t.indexOf('inside') >= 0 && t.indexOf('@[x](source/pdf/y.pdf)') >= 0 ? 1 : 0;
          })(),
          inlineRaw: (function () {
            var cs = document.querySelectorAll('#content code:not(pre code)');
            for (var i = 0; i < cs.length; i++) {
              if ((cs[i].textContent || '').indexOf('@[x](y.pdf)') >= 0) return 1;
            }
            return 0;
          })(),
          attach: document.querySelectorAll('a.attach-card').length,
          imageCard: document.querySelectorAll('figure.img-card figcaption').length,
          strike: document.querySelectorAll('s,del').length,
          emoji: document.getElementById('content').textContent.indexOf('😄') >= 0 ? 1 : 0,
          table: document.querySelectorAll('table').length,
          video: document.querySelectorAll('video[src]').length,
          audio: document.querySelectorAll('audio[src]').length,
          toc: document.querySelectorAll('nav.toc').length,
          tocText: document.querySelector('nav.toc a') ? document.querySelector('nav.toc a').textContent : '',
          mermaidErr: document.querySelectorAll('.mermaid-error').length,
          jsError: window.__jsError || ''
        });
        """
        let raw = try evaluate(web, script)
        let data = try XCTUnwrap(raw.data(using: .utf8))
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(result["jsError"] as? String, "", "渲染不应抛 JS 异常")

        let expected = [
            "callout": 1, "footnote": 1, "tasks": 2, "mark": 1, "sub": 1,
            "ins": 1, "code": 1, "attach": 1, "imageCard": 1, "strike": 1, "emoji": 1,
            "table": 1, "toc": 1, "video": 1, "audio": 1, "mermaidErr": 0,
            "codeMath": 0, "fenceRaw": 1, "inlineRaw": 1,
        ]
        for (key, want) in expected {
            XCTAssertEqual(result[key] as? Int, want, "语法 DOM 数量不符：\(key)")
        }
        XCTAssertGreaterThanOrEqual(result["sup"] as? Int ?? 0, 1, "上标应渲染")
        XCTAssertEqual(result["katex"] as? Int, 2, "仅行内/块级公式应渲染，货币文本不得误判")
        XCTAssertEqual(result["inlineDisplay"] as? Int, 0, "行内公式不得渲染成块级 KaTeX")
        XCTAssertGreaterThan(result["hl"] as? Int ?? 0, 0, "代码块应完成语法高亮")
        XCTAssertEqual(result["tocText"] as? String, "标题", "TOC 不应混入锚点符号")

        // Mermaid 懒加载异步；轮询到替换完成或错误出现。
        var mermaidDone = 0
        var mermaidErr = 0
        for _ in 0..<40 {
            let probe = try evaluate(web, "JSON.stringify({done: document.querySelectorAll('.mermaid-rendered').length, err: document.querySelectorAll('.mermaid-error').length})")
            let d = try XCTUnwrap(probe.data(using: .utf8))
            let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: d) as? [String: Any])
            mermaidDone = dict["done"] as? Int ?? 0
            mermaidErr = dict["err"] as? Int ?? 0
            if mermaidDone > 0 || mermaidErr > 0 { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertGreaterThan(mermaidDone, 0, "Mermaid 应渲染为 SVG")
        XCTAssertEqual(mermaidErr, 0)
    }

    private func jsonString(_ value: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [value])
        let array = try XCTUnwrap(String(data: data, encoding: .utf8))
        return String(array.dropFirst().dropLast())
    }

    /// 内置渲染增强（原 render-* 插件包，现随预览页直接加载）：语法必须开箱可用。
    func testBuiltInRenderEnhancements() throws {
        let web = try loadPreviewWeb()
        let md = """
        !!! warning 磁盘空间不足
        请及时清理缓存。

        [badge:成功]

        ::: badge 提示 blue
        徽章块说明
        :::

        :::tabs
        :::tab 概览
        概览内容
        :::tab 详情
        详情内容
        :::
        :::

        - [09-11] 起草大纲
        - [09-12] 完成初稿

        $ echo hello
        $ ls -la

        按键 [[⌘S]] 保存；@同事 看一下。

        > 引用会被主题染色

        ```swift
        let x = 1
        ```
        """
        let mdJSON = try jsonString(md)
        let script = """
        window.__enabledModules = {};
        window.renderMd(\(mdJSON), "file:///", { dark: false, resetScroll: true });
        JSON.stringify({
          alert: document.querySelectorAll('.md-alert-warning').length,
          alertTitle: document.querySelector('.md-alert-warning .md-alert-title') ? 1 : 0,
          badgeInline: document.querySelectorAll('.md-badge').length,
          badgeBlock: document.querySelectorAll('.md-badge-block').length,
          tabs: document.querySelectorAll('.md-tabs').length,
          tabPanels: document.querySelectorAll('.md-tab-panel').length,
          inactivePanelHidden: (function () {
            var ps = document.querySelectorAll('.md-tab-panel');
            if (ps.length < 2) return -1;
            return getComputedStyle(ps[1]).display === 'none' ? 1 : 0;
          })(),
          tabsVisibleText: (function () {
            var b = document.querySelector('.md-tabs-body');
            return b ? b.innerText.replace(/\\s+/g, '') : '';
          })(),
          timeline: document.querySelectorAll('.md-timeline').length,
          timelineItems: document.querySelectorAll('.md-tl-item').length,
          term: document.querySelectorAll('.term').length,
          kbd: document.querySelectorAll('kbd').length,
          mention: document.querySelectorAll('.mention').length,
          fancyQuote: document.querySelectorAll('blockquote.fancy').length,
          copyBtn: document.querySelectorAll('.marknote-copy-btn').length,
          jsError: window.__jsError || ''
        });
        """
        let raw = try evaluate(web, script)
        let data = try XCTUnwrap(raw.data(using: .utf8))
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(result["jsError"] as? String, "", "内置渲染增强不应抛 JS 异常")
        for (key, want) in ["alert": 1, "alertTitle": 1, "badgeInline": 2, "badgeBlock": 1,
                            "tabs": 1, "tabPanels": 2, "inactivePanelHidden": 1,
                            "timeline": 1, "timelineItems": 2,
                            "term": 1, "kbd": 1, "mention": 1, "fancyQuote": 1, "copyBtn": 1] {
            XCTAssertEqual(result[key] as? Int, want, "内置渲染增强 DOM 数量不符：\(key)")
        }
        XCTAssertEqual(result["tabsVisibleText"] as? String, "概览内容",
                       "标签页只应显示当前面板内容")
    }

    private func evaluate(_ web: WKWebView, _ script: String) throws -> String {
        var result: Any?
        var error: Error?
        let done = expectation(description: "evaluate")
        web.evaluateJavaScript(script) { r, e in result = r; error = e; done.fulfill() }
        wait(for: [done], timeout: 10)
        if let error { throw error }
        return try XCTUnwrap(result as? String)
    }
}

/// 图片：点击回传原始路径（不能把 data URL 当路径）、图注只认显式说明、图注可隐藏
final class PreviewImageBehaviorTests: XCTestCase {

    private func loadPreviewWeb() throws -> WKWebView {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let resources = root.appendingPathComponent(".build/arm64-apple-macosx/debug/MarkNote_MarkNote.bundle/Resources")
        let html = resources.appendingPathComponent("preview.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: html.path))
        let web = WKWebView(frame: NSRect(x: -5000, y: -5000, width: 800, height: 600))
        web.loadFileURL(html, allowingReadAccessTo: resources)
        for _ in 0..<60 {
            var value: Any?
            let e = XCTestExpectation(description: "ready")
            web.evaluateJavaScript("typeof window.renderMd") { r, _ in value = r; e.fulfill() }
            wait(for: [e], timeout: 2)
            if (value as? String) == "function" { return web }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTFail("预览渲染管线未就绪")
        return web
    }

    private func evaluate(_ web: WKWebView, _ script: String) throws -> String {
        let done = XCTestExpectation(description: "evaluate")
        var out = ""
        var err: Error?
        web.evaluateJavaScript(script) { value, error in
            out = (value as? String) ?? String(describing: value ?? "")
            err = error
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        if let err { throw err }
        return out
    }

    /// 内联图（注册表命中 → data URL）必须带 data-img-path，点击才回传原始相对路径
    func testInlineImageCarriesOriginalPath() throws {
        let web = try loadPreviewWeb()
        let out = try evaluate(web, """
        window.__setEntry('img/图 片 (2).jpg', 'data:image/png;base64,iVBORw0KGgo=');
        window.renderMd('![说明](img/图 片 (2).jpg)', 'file:///tmp/', { dark: false, resetScroll: true });
        (function () {
          var img = document.querySelector('.markdown-body img');
          if (!img) return 'no-img';
          return (img.getAttribute('src') || '').indexOf('data:') === 0
            ? (img.getAttribute('data-img-path') || 'no-marker')
            : 'not-inlined';
        })();
        """)
        // markdown-it 会把非 ASCII 目标编码（图→%E5%9B%BE）；这正是「原始引用路径」的规范形式，
        // 宿主侧 resolvedImageURL 会先解码再找文件 —— 关键是**不是 data: URL**
        XCTAssertFalse(out.hasPrefix("data:"), "不能把 data URL 当路径回传：\(out)")
        let decoded = out.removingPercentEncoding ?? out
        XCTAssertEqual(decoded, "img/图 片 (2).jpg", "解码后应回到原始相对路径，实际：\(out)")
    }

    /// 图注只认显式 title；只有 alt（文件名）时不生成 figcaption
    func testCaptionOnlyFromExplicitTitle() throws {
        let web = try loadPreviewWeb()
        let out = try evaluate(web, """
        window.renderMd('![09-13-很长的一串文件名.jpg](source/image/a.jpg)\\n\\n![图注文字](source/image/b.jpg "图注文字")', 'file:///tmp/', { dark: false, resetScroll: true });
        JSON.stringify({
          figures: document.querySelectorAll('.md-figure').length,
          captions: Array.prototype.map.call(document.querySelectorAll('.md-figure figcaption'), function (n) { return n.textContent; })
        });
        """)
        XCTAssertTrue(out.contains("\"figures\":2"), "两张图都要有相框：\(out)")
        XCTAssertTrue(out.contains("图注文字"), "显式图注要显示：\(out)")
        XCTAssertFalse(out.contains("很长的一串文件名"), "alt 不该再当图注：\(out)")
    }

    /// 一键隐藏图注：加 html.no-figcaption，图片本身不受影响
    func testCaptionsCanBeHidden() throws {
        let web = try loadPreviewWeb()
        let out = try evaluate(web, """
        window.renderMd('![图注](source/image/b.jpg "图注")', 'file:///tmp/', { dark: false, resetScroll: true });
        window.__setImageCaptions(false);
        (function () {
          var cap = document.querySelector('.md-figure figcaption');
          var img = document.querySelector('.md-figure img');
          var hidden = cap ? getComputedStyle(cap).display : 'no-caption';
          return JSON.stringify({ hidden: hidden, imgVisible: !!img && getComputedStyle(img).display !== 'none' });
        })();
        """)
        XCTAssertTrue(out.contains("\"hidden\":\"none\""), "关掉后图注应隐藏：\(out)")
        XCTAssertTrue(out.contains("\"imgVisible\":true"), "图片本身要留着：\(out)")
    }
}

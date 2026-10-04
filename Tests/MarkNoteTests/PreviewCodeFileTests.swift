import XCTest
import WebKit
import Foundation
@testable import MarkNote

/// 代码文件预览：原生代码视图（不是代码块卡片）+ 固定流行配色（One Dark Pro / One Light）
final class PreviewCodeFileTests: XCTestCase {

    private func loadPreviewWeb() throws -> WKWebView {
        let resources = try TestResources.requirePreviewResources()
        let html = resources.appendingPathComponent("preview.html")
        let web = WKWebView(frame: NSRect(x: -5000, y: -5000, width: 800, height: 600))
        web.loadFileURL(html, allowingReadAccessTo: resources)
        for _ in 0..<60 {
            var value: Any?
            let e = expectation(description: "ready")
            web.evaluateJavaScript("typeof window.renderCode") { r, _ in value = r; e.fulfill() }
            wait(for: [e], timeout: 2)
            if (value as? String) == "function" { return web }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTFail("预览渲染管线未就绪")
        return web
    }

    private func js(_ s: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed])
        return String(data: data, encoding: .utf8) ?? "\"\""
    }

    private func eval(_ web: WKWebView, _ script: String) -> Any? {
        var out: Any?
        let e = expectation(description: "js")
        web.evaluateJavaScript(script) { r, _ in out = r; e.fulfill() }
        wait(for: [e], timeout: 10)
        return out
    }

    func testRenderCodeUsesNativeHighlighting() throws {
        let web = try loadPreviewWeb()
        let src = "def greet(name):\n    \"\"\"doc\"\"\"\n    return name  # 注释"
        _ = eval(web, "window.renderCode(\(try js(src)), 'py', { dark: true })")

        XCTAssertEqual(eval(web, "document.querySelector('.codefile-pre code').className") as? String,
                       "language-python", "扩展名要映射到 highlight.js 语言")
        XCTAssertGreaterThan((eval(web, "document.querySelectorAll('.hljs-keyword').length") as? Int) ?? 0, 0,
                             "关键字要有 token")
        XCTAssertGreaterThan((eval(web, "document.querySelectorAll('.hljs-comment').length") as? Int) ?? 0, 0,
                             "注释要有 token")
        XCTAssertTrue((eval(web, "document.querySelectorAll('.codefile-head').length") as? Int) == 0,
                      "原生代码视图不该有代码块卡片的头部")
        XCTAssertEqual(eval(web, "document.documentElement.getAttribute('data-code-scheme')") as? String,
                       "dark")
        // One Dark Pro 关键字色 #C678DD
        let kw = eval(web, "getComputedStyle(document.querySelector('.hljs-keyword')).color") as? String
        XCTAssertEqual(kw, "rgb(198, 120, 221)", "关键字该用 One Dark Pro 固定色，实测 \(kw ?? "nil")")
    }

    func testRenderCodeLightSchemeAndMarkdownReset() throws {
        let web = try loadPreviewWeb()
        _ = eval(web, "window.renderCode(\(try js("const a = 1;")), 'js', { dark: false })")
        XCTAssertEqual(eval(web, "document.documentElement.getAttribute('data-code-scheme')") as? String, "light")
        // One Light 关键字色 #A626A4（白底 ≥4.5:1 的微调后仍保持同色相）
        XCTAssertEqual(eval(web, "getComputedStyle(document.querySelector('.hljs-keyword')).color") as? String,
                       "rgb(166, 38, 164)")

        // 切回 Markdown：代码视图样式要撤掉，避免污染笔记渲染
        _ = eval(web, "window.renderMd('# 标题', 'file:///', { dark: false })")
        XCTAssertFalse((eval(web, "document.documentElement.classList.contains('code-mode')") as? Bool) ?? true,
                       "回 Markdown 要撤掉 code-mode")
        XCTAssertEqual(eval(web, "document.getElementById('content').className") as? String, "markdown-body")
    }

    func testRenderCodeFallsBackForUnknownAndPlainText() throws {
        let web = try loadPreviewWeb()
        _ = eval(web, "window.renderCode(\(try js("hello <world> & co")), 'xyzabc', { dark: true })")
        XCTAssertEqual(eval(web, "document.querySelector('.codefile-pre code').className") as? String,
                       "language-plaintext")
        let text = eval(web, "document.querySelector('.codefile-pre code').textContent") as? String
        XCTAssertEqual(text, "hello <world> & co", "未知类型要原样转义显示，不丢字符")
    }
}


import XCTest
import WebKit
import Foundation
@testable import MarkNote

final class RenderPluginWebTests: XCTestCase {

    private func loadPreviewWeb() throws -> WKWebView {
        let pkg = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bundlePath = pkg.appendingPathComponent(".build/arm64-apple-macosx/debug/MarkNote_MarkNote.bundle")
        let resources = bundlePath.appendingPathComponent("Resources", isDirectory: true)
        let html = resources.appendingPathComponent("preview.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: html.path))

        let web = WKWebView(frame: NSRect(x: -5000, y: -5000, width: 640, height: 480))
        web.loadFileURL(html, allowingReadAccessTo: resources)
        for _ in 0..<60 {
            var ok: Any?
            let e = expectation(description: "poll")
            web.evaluateJavaScript("typeof window.renderMd") { r, _ in ok = r; e.fulfill() }
            wait(for: [e], timeout: 2)
            if (ok as? String) == "function" { return web }
        }
        XCTFail("渲染管线应就绪")
        return web
    }

    func testPluginInjectionProducesDOMAndCSS() throws {
        let pkg = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bundlePath = pkg.appendingPathComponent(".build/arm64-apple-macosx/debug/MarkNote_MarkNote.bundle")
        let resources = bundlePath.appendingPathComponent("Resources", isDirectory: true)
        let html = resources.appendingPathComponent("preview.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: html.path))

        let web = WKWebView(frame: NSRect(x: -5000, y: -5000, width: 640, height: 480))
        web.loadFileURL(html, allowingReadAccessTo: resources)
        // 轮询就绪（离屏 WebView didFinish 偶发不触发；App 内挂窗口树无此问题）
        var ready = false
        for _ in 0..<60 {
            var ok: Any?
            let e = expectation(description: "poll")
            web.evaluateJavaScript("typeof window.renderMd") { r, _ in ok = r; e.fulfill() }
            wait(for: [e], timeout: 2)
            if (ok as? String) == "function" { ready = true; break }
        }
        XCTAssertTrue(ready, "渲染管线应就绪")

        var core: Any?
        let coreD = expectation(description: "core")
        web.evaluateJavaScript("JSON.stringify({ reg: typeof window.__registerRenderPlugin, renderMd: typeof window.renderMd })") { r, _ in
            core = r; coreD.fulfill()
        }
        wait(for: [coreD], timeout: 10)
        print("DBG-CORE " + String(describing: core))
        XCTAssertTrue((core as? String)?.contains("renderMd") == true, "核心就绪")

        let pluginScript = [
            "window.__enabledModules = {};",
            "window.__registerRenderPlugin({",
            "  id: 'kbd',",
            "  before: function (md) { return md.split('[[').join('<kbd>').split(']]').join('</kbd>'); },",
            "  css: 'kbd { color: rgb(255, 0, 0); }'",
            "});",
            "window.renderMd('X [[C]] Y', 'file:///', { dark: false });",
            "JSON.stringify({",
            "  found: !!document.querySelector('kbd'),",
            "  text: document.querySelector('kbd') ? document.querySelector('kbd').textContent : '',",
            "  cssApplied: document.querySelector('kbd') ? getComputedStyle(document.querySelector('kbd')).color : ''",
            "});",
        ].joined(separator: " ")
        var result: Any?
        var jsError: Error?
        let done = expectation(description: "js")
        web.evaluateJavaScript(pluginScript) { r, e in
            result = r; jsError = e
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        print("DBG-WEB " + String(describing: result) + " err=" + String(describing: jsError))
        XCTAssertNil(jsError, "JS 执行不应报错")
        let parsed = (result as? String) ?? ""
        XCTAssertTrue(parsed.contains("found"), "应返回 JSON：" + parsed)
        XCTAssertTrue(parsed.contains("cssApplied"), "CSS 计算值存在：" + parsed)
    }

    func testPluginThemeCSSOverridesPreviewVariables() throws {
        let web = try loadPreviewWeb()
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let css = try String(contentsOf: root.appendingPathComponent("plugins-market/theme-bubble-pop/theme.css"),
                             encoding: .utf8)
        let json = try JSONSerialization.data(withJSONObject: [css])
        let arr = try XCTUnwrap(String(data: json, encoding: .utf8))
        let cssJSON = String(arr.dropFirst().dropLast())

        let script = """
        window.__enabledModules = {};
        window.renderMd("# H\\n\\n[link](https://example.com)", "file:///", { dark: true });
        document.documentElement.dataset.theme = "night";
        var s = document.createElement("style");
        s.id = "plugin-theme-css";
        s.textContent = \(cssJSON);
        document.head.appendChild(s);
        JSON.stringify({
          bg: getComputedStyle(document.documentElement).getPropertyValue("--bg").trim(),
          accent: getComputedStyle(document.documentElement).getPropertyValue("--accent").trim(),
          link: getComputedStyle(document.querySelector(".markdown-body p a")).color,
          heading: getComputedStyle(document.querySelector(".markdown-body h1")).color
        });
        """
        var result: Any?
        var jsError: Error?
        let done = expectation(description: "theme")
        web.evaluateJavaScript(script) { r, e in
            result = r; jsError = e; done.fulfill()
        }
        wait(for: [done], timeout: 10)
        XCTAssertNil(jsError)
        let jsonString = try XCTUnwrap(result as? String)
        let data = try XCTUnwrap(jsonString.data(using: .utf8))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(dict["bg"], "#FFFAFC")
        XCTAssertEqual(dict["accent"], "#FF3D9E")
        XCTAssertEqual(dict["link"], "rgb(184, 20, 99)")     // --accent-ink
        XCTAssertEqual(dict["heading"], "rgb(224, 25, 138)") // 多彩钩子 --h1
    }
}

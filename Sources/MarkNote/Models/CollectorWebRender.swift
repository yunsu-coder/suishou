import Foundation
import WebKit

/// 「真浏览器」兜底：JS 渲染页 / 需要登录态的页面（知乎、小红书、头条这类），
/// 普通 HTTP 抓回来的是空壳，用应用内的 WKWebView 跑一遍再取 DOM。
///
/// 关键点：复用 `WKWebsiteDataStore.default()` —— 站点账号登录时写的就是这个 store，
/// 所以这里**天然带着登录态**，登录过的站渲染出来就是登录后的样子。
@MainActor
enum CollectorWebRender {

    /// 渲染页面并返回 `outerHTML`；超时 / 失败返回 nil（调用方保留 HTTP 版本兜底）
    /// - Parameters:
    ///   - minChars: 等到正文至少有这么多字才收工（不够就等到 timeout）
    static func render(_ url: URL, minChars: Int = 600,
                       timeout: TimeInterval = 12) async -> String? {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()          // 与站点账号共用一个 cookie store
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 960),
                            configuration: config)
        web.customUserAgent = NotesStore.collectorUA
        let nav = NavigationWaiter()
        web.navigationDelegate = nav
        web.load(URLRequest(url: url))
        let loaded = await nav.wait(timeout: timeout)
        guard loaded else {
            web.stopLoading()
            return nil
        }
        _ = await waitForContent(web, minChars: minChars, timeout: 4)
        let html = try? await web.evaluateJavaScript("document.documentElement.outerHTML")
        web.stopLoading()
        return html as? String
    }

    /// 等正文出现：每 0.4s 问一次 `document.body.innerText` 长度
    private static func waitForContent(_ web: WKWebView, minChars: Int,
                                       timeout: TimeInterval) async -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        var length = 0
        while Date() < deadline {
            let value = try? await web.evaluateJavaScript(
                "(document.body && document.body.innerText ? document.body.innerText.length : 0)")
            length = (value as? Int) ?? 0
            if length >= minChars { break }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        return length
    }

}

/// 等一次导航结束（didFinish / 失败 / 超时），返回是否成功加载
@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var settled = false

    func wait(timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { cont in
            continuation = cont
            // 超时兜底：网页卡住时别把整条采集链路拖死
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self.settle(false)
            }
        }
    }

    private func settle(_ ok: Bool) {
        guard !settled else { return }
        settled = true
        continuation?.resume(returning: ok)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { settle(true) }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        settle(false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        settle(false)
    }
}

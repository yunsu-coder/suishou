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

    /// 在某个站点的**真实页面上下文**里跑一段 JS（可 await），把结果当字符串返回。
    ///
    /// 用途：站点专用接口。开源爬虫（MediaCrawler ★64k、Spider_XHS）验证过的路子 ——
    /// 不用逆向签名算法，让**页面自己的 JS** 算签名（小红书 `window._webmsxyw` 等），
    /// 我们在同一上下文里 `fetch`，同源 + 带 cookie，接口就会正常返回。
    static func runJS(_ js: String, on pageURL: URL, timeout: TimeInterval = 20) async -> String? {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()          // 与站点账号共用登录态
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 960),
                            configuration: config)
        web.customUserAgent = NotesStore.collectorUA
        let nav = NavigationWaiter()
        web.navigationDelegate = nav
        web.load(URLRequest(url: pageURL))
        guard await nav.wait(timeout: timeout) else {
            web.stopLoading()
            return nil
        }
        // 注意：evaluateJavaScript 不会等 Promise，必须用 callAsyncJavaScript；
        // 且要在 `.page` 世界执行 —— 站点的签名函数挂在页面自己的 JS 上下文里。
        let result: Any?
        do {
            result = try await web.callAsyncJavaScript("return await (async () => { \(js) })();",
                                                       arguments: [:], in: nil,
                                                       contentWorld: .page)
        } catch {
            web.stopLoading()
            return "JSERR: \(error.localizedDescription)"
        }
        web.stopLoading()
        return result as? String
    }

    /// 打开页面 → 等 `waitForJS` 为真（页面自己把内容画出来）→ 跑 `extractJS` 取结果。
    ///
    /// 这是「不碰签名」的稳妥路子：站点的前端自己会算签名、自己去请求，
    /// 我们只等它渲染完，再从 DOM 里把标题 / 图片地址读出来（MediaCrawler 的 CDP 模式同理）。
    static func scrape(_ url: URL, waitForJS: String, extractJS: String,
                       readyTimeout: TimeInterval = 12,
                       loadTimeout: TimeInterval = 20) async -> String? {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 960),
                            configuration: config)
        web.customUserAgent = NotesStore.collectorUA
        let nav = NavigationWaiter()
        web.navigationDelegate = nav
        web.load(URLRequest(url: url))
        guard await nav.wait(timeout: loadTimeout) else {
            web.stopLoading()
            return nil
        }
        // 等内容出现：每 0.5s 问一次
        let deadline = Date().addingTimeInterval(readyTimeout)
        while Date() < deadline {
            let ready = try? await web.callAsyncJavaScript(
                "return !!(\(waitForJS));", arguments: [:], in: nil, contentWorld: .page)
            if (ready as? Bool) == true { break }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        // 顺手滚一下，触发懒加载的图片
        _ = try? await web.callAsyncJavaScript(
            "window.scrollTo(0, document.body.scrollHeight); return 1;",
            arguments: [:], in: nil, contentWorld: .page)
        try? await Task.sleep(nanoseconds: 800_000_000)
        let result = try? await web.callAsyncJavaScript("return await (async () => { \(extractJS) })();",
                                                       arguments: [:], in: nil,
                                                       contentWorld: .page)
        web.stopLoading()
        return result as? String
    }

    /// **抓取站点自己的接口响应**（最稳的一招）：
    /// 在文档开始时注入一小段 JS 钩住 `fetch` / `XMLHttpRequest`，把页面自己发出的 `/api/…`
    /// 响应体存下来；然后我们直接读 JSON —— 不用碰签名（签名是页面自己算的），
    /// 也不受 DOM 结构变化影响。
    ///
    /// 返回：`[{"url": "...", "body": "..."}]` 的 JSON 字符串（按请求顺序）。
    static func captureAPI(_ url: URL, urlKeyword: String = "/api/",
                           readyJS: String? = nil, readyTimeout: TimeInterval = 12,
                           loadTimeout: TimeInterval = 20) async -> String? {
        let hook = """
        (function () {
          if (window.__capHooked) { return; }
          window.__capHooked = true;
          window.__cap = [];
          const keep = (u, body) => {
            try { if (!u || String(u).indexOf("\(urlKeyword)") < 0) return;
                  window.__cap.push({url: String(u), body: String(body || "")}); } catch (e) {}
          };
          const of = window.fetch;
          if (of) {
            window.fetch = function () {
              const args = arguments;
              const url = (typeof args[0] === "string") ? args[0] : (args[0] && args[0].url);
              return of.apply(this, args).then(function (res) {
                try { res.clone().text().then(function (t) { keep(url, t); }, function () {}); } catch (e) {}
                return res;
              });
            };
          }
          const oo = XMLHttpRequest.prototype.open;
          const os = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.open = function (m, u) { this.__u = u; return oo.apply(this, arguments); };
          XMLHttpRequest.prototype.send = function () {
            const self = this;
            this.addEventListener("load", function () {
              try { keep(self.__u, self.responseText); } catch (e) {}
            });
            return os.apply(this, arguments);
          };
        })();
        """
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.userContentController.addUserScript(WKUserScript(source: hook,
                                                                injectionTime: .atDocumentStart,
                                                                forMainFrameOnly: false))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 960),
                            configuration: config)
        web.customUserAgent = NotesStore.collectorUA
        let nav = NavigationWaiter()
        web.navigationDelegate = nav
        web.load(URLRequest(url: url))
        guard await nav.wait(timeout: loadTimeout) else {
            web.stopLoading()
            return nil
        }
        let deadline = Date().addingTimeInterval(readyTimeout)
        let readyProbe = readyJS ?? "(window.__cap && window.__cap.length > 0)"
        while Date() < deadline {
            let ready = try? await web.callAsyncJavaScript("return !!(\(readyProbe));",
                                                           arguments: [:], in: nil,
                                                           contentWorld: .page)
            if (ready as? Bool) == true { break }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        // 给还没回到的请求一点时间（图片/详情接口常晚一拍）
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        let result = try? await web.callAsyncJavaScript(
            "return JSON.stringify(window.__cap || []);", arguments: [:], in: nil,
            contentWorld: .page)
        web.stopLoading()
        return result as? String
    }

    /// 保持一个页面会话，分多次跑 JS —— 用于「先点一下、再等、再读」这类多步操作
    /// （页面里长时间 await 会在 SPA 路由切换时被掐断，所以必须拆开）。
    @MainActor
    final class Session: NSObject, WKUIDelegate {
        fileprivate let web: WKWebView
        private let nav: NavigationWaiter
        /// `target="_blank"` 弹窗的目标地址（站点自己拼好的，常带 xsec_token）
        private(set) var popupURL: URL?

        fileprivate init(web: WKWebView, nav: NavigationWaiter) {
            self.web = web
            self.nav = nav
            super.init()
            web.uiDelegate = self
        }

        /// 跑一段 JS（可 await），返回字符串结果
        func run(_ js: String, timeout: TimeInterval = 15) async -> String? {
            let result = try? await web.callAsyncJavaScript("return await (async () => { \(js) })();",
                                                            arguments: [:], in: nil,
                                                            contentWorld: .page)
            return result as? String
        }

        func close() {
            web.stopLoading()
            web.navigationDelegate = nil
            web.uiDelegate = nil
        }

        /// 让当前会话自己打开弹窗地址（不真的开新窗口）
        func followPopup() async -> URL? {
            guard let url = popupURL else { return nil }
            web.load(URLRequest(url: url))
            return url
        }

        // 拦截 target=_blank：记下地址，交由上面 followPopup 处理
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            popupURL = navigationAction.request.url
            return nil
        }
    }

    /// 打开一个页面会话（等首屏加载完）
    static func openSession(_ url: URL, loadTimeout: TimeInterval = 20) async -> Session? {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 960),
                            configuration: config)
        web.customUserAgent = NotesStore.collectorUA
        let nav = NavigationWaiter()
        web.navigationDelegate = nav
        web.load(URLRequest(url: url))
        guard await nav.wait(timeout: loadTimeout) else {
            web.stopLoading()
            return nil
        }
        return Session(web: web, nav: nav)
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

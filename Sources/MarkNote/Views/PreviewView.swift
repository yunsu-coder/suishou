import SwiftUI
import WebKit

/// 预览滚动跟随目标：标题文本 + 同名出现序号（跳过第 k 次出现）
struct PreviewHeadingTarget: Equatable {
    let text: String
    let occurrence: Int
}

/// 实时预览 —— 单个 WKWebView 渲染整套 markdown 管线
/// （markdown-it + KaTeX + mermaid + highlight.js，全部离线内置）。
/// 文本变化 180ms 防抖后一次性 JS 全量渲染（与 start 的 renderLive 同一策略）。
struct PreviewView: NSViewRepresentable {

    /// 当前需要渲染的 markdown（由 EditorView 维护，随打字更新）
    var liveText: String
    /// 图片相对路径的基准目录（笔记目录 file:// URL）
    var basePath: String
    var fontScale: Double
    var dark: Bool
    /// 切换笔记的变化标记（id），变化时预览重置到顶部
    var resetToken: String
    /// 主题 data-theme 值（nil = 跟随系统）
    var theme: String?
    /// 预览内图片点击（传 file URL，已解析为绝对路径）
    var onOpenImage: (URL) -> Void
    /// 预览内附件链接点击（相对路径已解析为 file URL）
    var onOpenFile: (URL) -> Void
    /// 滚动跟随：光标所在标题（含同名出现序号）；nil = 光标前无标题
    var headingTarget: PreviewHeadingTarget?
    /// 远程图片缓存版本（下载完成 +1 → 触发重渲染）
    var imageCacheVersion: Int
    /// 预览字体 CSS family（空 = 系统默认）
    var previewFont: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // 注意：iOS 的 allowFileAccessFromFileURLs KVC key 在 macOS 不存在，
        // 会导致 KVC exception。资源目录内访问由 loadFileURL 的
        // allowingReadAccessTo 授权，无需额外偏好。
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let handler = context.coordinator
        config.userContentController.add(handler, name: "openURL")
        config.userContentController.add(handler, name: "openImage")
        config.userContentController.add(handler, name: "openFile")

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsMagnification = false
        context.coordinator.webRef = web

        if let html = Bundle.module.url(forResource: "preview", withExtension: "html", subdirectory: "Resources") {
            web.loadFileURL(html, allowingReadAccessTo: Bundle.module.resourceURL ?? html.deletingLastPathComponent())
        }
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.scheduleRender(web)
        context.coordinator.scheduleFollow(web)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: PreviewView
        private var renderWorkItem: DispatchWorkItem?
        private var webReady = false
        /// 已渲染的指纹，避免重复渲染
        private var lastHash = ""
        private var lastBase = ""
        private var lastToken = ""
        private var lastHeading: PreviewHeadingTarget?
        private var followWorkItem: DispatchWorkItem?

        init(_ parent: PreviewView) {
            self.parent = parent
        }

        deinit {
            // 反注册：避免 WKUserContentController 强持 handler 造成泄漏
            if let web = webRef {
                web.configuration.userContentController.removeScriptMessageHandler(forName: "openURL")
                web.configuration.userContentController.removeScriptMessageHandler(forName: "openImage")
                web.configuration.userContentController.removeScriptMessageHandler(forName: "openFile")
            }
        }

        weak var webRef: WKWebView?

        func scheduleRender(_ web: WKWebView) {
            let md = parent.liveText
            renderWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self, weak web] in
                guard let self, let web else { return }
                self.performRender(web, md: md)
            }
            renderWorkItem = item
            // 智能降频：文档越大防抖越长（打击"每击键全量重建 DOM"的卡顿感）
            let delay: Double = md.count > 100_000 ? 0.60
                             : md.count > 60_000 ? 0.45
                             : md.count > 20_000 ? 0.30
                             : (webReady ? 0.20 : 0.05)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }

        private func performRender(_ web: WKWebView, md: String?) {
            guard webReady else { return }
            let md = md ?? parent.liveText
            let base = parent.basePath
            let scale = parent.fontScale
            let dark = parent.dark
            let token = parent.resetToken
            let theme = parent.theme
            let hash = "\(md.count)|\(base)|\(scale)|\(dark)|\(token)|\(theme ?? "-")|\(parent.imageCacheVersion)"
            guard hash != lastHash || base != lastBase else { return }
            let resetScroll = token != lastToken
            lastHash = hash
            lastBase = base
            lastToken = token
            let mdJSON = Self.jsString(md)
            let baseJSON = Self.jsString(base)
            let themeJS = theme.map { "\(Self.jsString($0))" } ?? "null"
            let fontJS = Self.jsString(parent.previewFont)
            let js = """
            if (window.renderMd) {
              window.renderMd(\(mdJSON), \(baseJSON), { dark: \(dark), resetScroll: \(resetScroll) });
              document.documentElement.style.colorScheme = \(dark) ? 'dark' : 'light';
              document.body.style.fontSize = \(String(format: "%.3f", scale * 16)) + 'px';
              if (\(fontJS).length > 0) { document.body.style.fontFamily = \(fontJS); }
              if (\(themeJS)) { document.documentElement.dataset.theme = \(themeJS); }
              else { delete document.documentElement.dataset.theme; }
            }
            """
            web.evaluateJavaScript(js, completionHandler: nil)
        }

        /// 编辑光标移动 → 预览滚动跟随（120ms 防抖）
        func scheduleFollow(_ web: WKWebView) {
            guard let target = parent.headingTarget, target != lastHeading else { return }
            lastHeading = target
            followWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self, weak web] in
                guard let self, let web else { return }
                let t = PreviewView.Coordinator.jsString(target.text)
                web.evaluateJavaScript("if (window.scrollToHeading) window.scrollToHeading(\(t), \(target.occurrence))")
            }
            followWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
        }

        /// JSON 字符串转 JS 字符串字面量（避免模板转义错误）
        static func jsString(_ s: String) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: [s]),
                  let arr = String(data: data, encoding: .utf8) else { return "\"\"" }
            return String(arr.dropFirst().dropLast()) // 去掉 [ ]
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webReady = true
            scheduleRender(webView)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // 仅拦截点击式导航（非 JS 同源导航）
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               url.scheme == "http" || url.scheme == "https" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("[preview] load error:", error.localizedDescription)
        }

        // MARK: WKScriptMessageHandler（JS postMessage → 宿主动作）

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let s = message.body as? String else { return }
            switch message.name {
            case "openURL":
                if let url = URL(string: s), url.scheme == "http" || url.scheme == "https" {
                    NSWorkspace.shared.open(url)
                }
            case "openImage":
                // 预览里图片 src 已被 resolveImages 转为绝对 file:// URL
                if let url = URL(string: s), url.isFileURL {
                    parent.onOpenImage(url)
                }
            case "openFile":
                // 预览里附件链接可能为相对路径（attachments/…）→ 传给宿主解析
                if let url = URL(string: s) {
                    parent.onOpenFile(url)
                }
            default:
                break
            }
        }
    }
}

import SwiftUI
import WebKit

/// 预览滚动跟随目标：标题文本 + 同名出现序号（跳过第 k 次出现）
struct PreviewHeadingTarget: Equatable {
    let text: String
    let occurrence: Int
}

/// 实时预览 —— 单个 WKWebView 渲染整套 markdown 管线
/// （markdown-it + KaTeX + mermaid + highlight.js，全部离线内置）。
/// 文本变化 180ms 防抖后一次性 JS 全量渲染。

/// 渲染扩展开关（设置页）/ UserDefaults key: renderModule.<name>；缺省全开
enum RenderModules {
    static let all: [String] = ["callout", "footnote", "tasklist", "mark", "ins", "sub", "sup",
                                "emoji", "katex", "mermaid", "attachments", "toc", "anchor",
                                "fold", "videoEmbed"]
    static func isEnabled(_ name: String) -> Bool {
        UserDefaults.standard.object(forKey: "renderModule.\(name)") as? Bool ?? true
    }
    static func setEnabled(_ name: String, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: "renderModule.\(name)")
    }
    /// 全部模块的启用集 JSON 字符串（注入 JS；缺省=全开）
    static func enabledJSON() -> String {
        var d: [String: Bool] = [:]
        for n in all { d[n] = isEnabled(n) }
        let data = (try? JSONSerialization.data(withJSONObject: d)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    static func hash() -> String {
        all.map { isEnabled($0) ? "1" : "0" }.joined()
    }
}

struct PreviewView: NSViewRepresentable {

    /// 当前需要渲染的 markdown（由 EditorView 维护，随打字更新）
    var liveText: String
    /// "md"=Markdown 渲染；"code"=代码高亮只读视图（VSCode 式）
    var renderMode: String = "md"
    /// 图片相对路径的基准目录（文件目录 file:// URL）
    var basePath: String
    var fontScale: Double
    var dark: Bool
    /// 切换文件的变化标记（id），变化时预览重置到顶部
    var resetToken: String
    /// 主题 data-theme 值（nil = 跟随系统）
    var theme: String?
    /// 预览内图片点击（载荷：原始相对路径 / file:// URL / http(s) URL，由宿主解析）
    var onOpenImage: (String) -> Void
    /// 预览内附件链接点击（相对路径已解析为 file URL）
    var onOpenFile: (URL) -> Void
    /// 滚动跟随：光标所在标题（含同名出现序号）；nil = 光标前无标题
    var headingTarget: PreviewHeadingTarget?
    /// 远程图片缓存版本（下载完成 +1 → 触发重渲染）
    var imageCacheVersion: Int
    /// 图片注册表（路径 → data URL）：Performance — 每帧预览只传 md 原文，图片不重复桥接
    var imageRegistry: [String: String]
    var imageRegistryVersion: Int
    /// 字体注册表（家族名 → data URL @font-face）：自定义字体走页面内注入（WebContent 进程读不到宿主注册）
    var fontRegistry: [String: String]
    var fontRegistryVersion: Int
    /// 毛玻璃强度（>0 = WebView 背景透明 + 页面背景透明，壁纸透出）
    var glass: Double = 0
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
            // 工作台语义：把预览页镜像到 notesDir/.preview/ 再以「工作台根」为读取授权加载 ——
            // 页面 vendor 与 source/ 资源同根，file:// 直放行（视频/PDF/图片卡全链路可渲染）。
            // 包内加载仅授权资源目录 → 跨目录 file:// 被 WebKit 拦截（旧病根）。
            let mirror = Self.mirroredPage(html, basePath: URL(string: basePath))
            web.loadFileURL(mirror ?? html, allowingReadAccessTo: mirror != nil ? URL(string: basePath)! : (Bundle.module.resourceURL ?? html.deletingLastPathComponent()))
            context.coordinator.webReady = false // makeNSView 写入需对外可见（didFinish 后置 true）
        }
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyGlassIfNeeded(web)
        context.coordinator.scheduleRender(web)
        context.coordinator.scheduleFollow(web)
    }

    /// 把 Bundle 内预览页镜像到工作台 .preview/（vendor 一起；源更新即重拷）
    private static func mirroredPage(_ html: URL, basePath: URL?) -> URL? {
        guard let base = basePath else { return nil }
        let fm = FileManager.default
        let previewDir = base.appendingPathComponent(".preview", isDirectory: true)
        let mirroredHTML = previewDir.appendingPathComponent("preview.html")
        let sourceDir = html.deletingLastPathComponent()
        let srcMtime = (try? sourceDir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let dstMtime = (try? mirroredHTML.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        if srcMtime > dstMtime {
            try? fm.removeItem(at: previewDir)
            try? fm.createDirectory(at: previewDir, withIntermediateDirectories: true)
            guard let items = try? fm.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil) else { return nil }
            for u in items {
                let dest = previewDir.appendingPathComponent(u.lastPathComponent)
                try? fm.copyItem(at: u, to: dest)
            }
        }
        return fm.fileExists(atPath: mirroredHTML.path) ? mirroredHTML : nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: PreviewView
        /// 插件启用/禁用/主题切换 → 主动触发重渲（修复：启用渲染/主题插件后无生效）
        private var pluginsObserver: NSObjectProtocol?
        private var renderWorkItem: DispatchWorkItem?
        /// 页面加载完成标记（didFinish 置 true）；makeNSView 中创建后先置 false
        var webReady = false
        /// 渲染指纹仲裁（C-01：内容/参数任一变化才渲染，避免同长度编辑漏渲）
        private var renderState = PreviewRenderState()
        private var lastHeading: PreviewHeadingTarget?
        private var followWorkItem: DispatchWorkItem?
        /// 图片注册表增量分发状态
        private var lastRegistryVersion = 0
        private var lastRegistryKeys: Set<String> = []
        /// 字体注册表增量分发状态
        private var lastFontRegistryVersion = 0
        private var lastFontFamilyKeys: Set<String> = []
        /// 已应用毛玻璃
        private var lastGlass = -1.0

        init(_ parent: PreviewView) {
            self.parent = parent
            super.init()
            pluginsObserver = NotificationCenter.default.addObserver(
                forName: PluginManager.changedNotification, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self, let web = self.webRef else { return }
                // 强制重渲：重置指纹（不依赖 meta 变化判定）
                self.renderState.reset()
                self.scheduleRender(web)
            }
            NotificationCenter.default.addObserver(forName: .renderForceRefresh, object: nil, queue: .main) { [weak self] _ in
                guard let self, let web = self.webRef else { return }
                self.renderState.reset()
                self.scheduleRender(web)
            }
        }

        deinit {
            if let pluginsObserver { NotificationCenter.default.removeObserver(pluginsObserver) }
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
            // 智能降频（按体量线性）；>200K 再降一档（书写连续时预览让路）
            let delay: Double = md.count > 200_000 ? 0.80
                             : md.count > 100_000 ? 0.60
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
            // 指纹必须含预览字体/字体注册表版本/毛玻璃/插件主题：设置页改任意一项后立即重渲
            let renderPlugins = PluginManager.shared.allRenderPlugins()
            let renderPluginHash = renderPlugins.map(\.id).sorted().joined(separator: ",")
            let renderPluginJS = renderPlugins.map { "try { " + $0.js + " } catch (e) {}" }.joined(separator: "\n")
            let pluginTheme = PluginManager.shared.enabledTheme()
            let pluginThemeID = pluginTheme?.id ?? "-"
            let meta = "\(base)|\(scale)|\(dark)|\(theme ?? "-")|\(parent.imageCacheVersion)|\(parent.previewFont)|\(parent.fontRegistryVersion)|\(parent.glass)|\(pluginThemeID)|\(RenderModules.hash())|\(renderPluginHash)"
            let decision = renderState.shouldRender(md: md, meta: meta, token: token)
            guard decision.render else { return }
            pushNewImageEntries(web)
            pushNewFontEntries(web)
            let resetScroll = decision.resetScroll
            let mdJSON = Self.jsString(md)
            let baseJSON = Self.jsString(base)
            let themeJS = theme.map { "\(Self.jsString($0))" } ?? "null"
            let fontJS = Self.jsString(parent.previewFont)
            let pluginThemeJS = Self.jsString(pluginTheme.flatMap { try? String(contentsOfFile: $0.cssFile, encoding: .utf8) } ?? "")
            let isCode = parent.renderMode == "code"
            let langJSON = Self.jsString((token as NSString).pathExtension.lowercased())
            let modulesJS = Self.jsString(RenderModules.enabledJSON())
            let js = """
            window.__enabledModules = \(modulesJS);
            \(renderPluginJS)
            if (window.renderMd) {
              if (\(isCode)) {
                window.renderCode(\(mdJSON), \(langJSON));
              } else {
                window.renderMd(\(mdJSON), \(baseJSON), { dark: \(dark), resetScroll: \(resetScroll) });
              }
              document.documentElement.style.colorScheme = \(dark) ? 'dark' : 'light';
              document.body.style.fontSize = \(String(format: "%.3f", scale * 16)) + 'px';
              document.body.style.fontFamily = \(fontJS); // 空串 = 清除内联覆盖（还原系统默认）
              if (\(themeJS)) { document.documentElement.dataset.theme = \(themeJS); }
              else { delete document.documentElement.dataset.theme; }
              var pt = document.getElementById("plugin-theme-css");
              if (\(pluginThemeID != "-")) { var pc = \(pluginThemeJS); if (!pt) { pt = document.createElement("style"); pt.id = "plugin-theme-css"; document.head.appendChild(pt); } pt.textContent = pc; }
              else if (pt) { pt.remove(); }
              // 毛玻璃：页面背景透明（WebView 已关 drawsBackground），壁纸从窗口垫层透出
              document.documentElement.style.backgroundColor = \(parent.glass > 0 ? "'transparent'" : "''");
              document.body.style.backgroundColor = \(parent.glass > 0 ? "'transparent'" : "''");
            }
            """
            web.evaluateJavaScript(js, completionHandler: nil)
            // 渲染诊断回传（UserDefaults 通道；独立查询，不再包裹 renderMd —— 修复主面板空白）
            let statsJS = """
            JSON.stringify({
              ms: window.__lastRenderMs || -1,
              att: document.querySelectorAll('.attach-card').length,
              vid: document.querySelectorAll('video').length,
              aud: document.querySelectorAll('audio').length,
              mmOK: document.querySelectorAll('.mermaid-rendered').length,
              mmErr: document.querySelectorAll('.mermaid-error').length,
              reg: window.__imgRegCount || 0,
              codeBtns: document.querySelectorAll('.copy-btn').length,
              jsError: window.__jsError || null
            })
            """
            web.evaluateJavaScript(statsJS) { result, _ in
                if let s = result as? String, let data = s.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    UserDefaults.standard.set(dict["ms"] as? Int ?? -1, forKey: "lastRenderMs")
                    UserDefaults.standard.set(dict["att"] as? Int ?? -1, forKey: "lastRenderAttCards")
                    UserDefaults.standard.set(dict["vid"] as? Int ?? -1, forKey: "lastRenderVideos")
                    UserDefaults.standard.set(dict["aud"] as? Int ?? -1, forKey: "lastRenderAudios")
                    UserDefaults.standard.set(dict["jsError"] as? String ?? "ok", forKey: "lastRenderJSError")
                    UserDefaults.standard.set(dict["reg"] as? Int ?? -1, forKey: "lastRenderRegCount")
                }
            }
      }

        /// 毛玻璃切换：WKWebView 背景开关（drawsBackground 无公开 API，走 KVC —— 苹果自身使用的小把戏）
        func applyGlassIfNeeded(_ web: WKWebView) {
            guard abs(lastGlass - parent.glass) > 0.001 else { return }
            lastGlass = parent.glass
            web.setValue(parent.glass <= 0, forKey: "drawsBackground")
        }

        /// 注册表增量下发：只在有新条目（图片变化）时逐条 eval，杜绝每帧大字符串桥接
        private func pushNewImageEntries(_ web: WKWebView) {
            let reg = parent.imageRegistry
            let v = parent.imageRegistryVersion
            guard v != lastRegistryVersion else { return }
            lastRegistryVersion = v
            for (path, dataURL) in reg where !lastRegistryKeys.contains(path) {
                lastRegistryKeys.insert(path)
                let p = PreviewView.Coordinator.jsString(path)
                let d = PreviewView.Coordinator.jsString(dataURL)
                web.evaluateJavaScript("if (window.__setEntry) window.__setEntry(\(p), \(d));")
            }
        }

        /// 字体注册表增量下发（同图片机制：只在字体新增时注入 @font-face）
        private func pushNewFontEntries(_ web: WKWebView) {
            let reg = parent.fontRegistry
            let v = parent.fontRegistryVersion
            guard v != lastFontRegistryVersion else { return }
            lastFontRegistryVersion = v
            for (family, dataURL) in reg where !lastFontFamilyKeys.contains(family) {
                lastFontFamilyKeys.insert(family)
                let f = PreviewView.Coordinator.jsString(family)
                let d = PreviewView.Coordinator.jsString(dataURL)
                web.evaluateJavaScript("if (window.__setFont) window.__setFont(\(f), \(d));")
            }
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
                // 载荷：内联图=原始相对路径（title 标记）/ file:// 绝对路径 / http(s) 远程图
                parent.onOpenImage(s)
            case "openFile":
                // 载荷为 URL 编码的相对路径（attachments/my%20file.md）—— 先解码再按文件目录解析
                let decoded = s.removingPercentEncoding ?? s
                var url: URL?
                if decoded.hasPrefix("/"), FileManager.default.fileExists(atPath: decoded) {
                    url = URL(fileURLWithPath: decoded)
                } else if let base = URL(string: parent.basePath) {
                    url = base.appendingPathComponent(decoded.hasPrefix("/") ? String(decoded.dropFirst()) : decoded)
                    url = URL(fileURLWithPath: url!.path) // 规范化回 file URL（避免二次编码残留）
                }
                if let url {
                    parent.onOpenFile(url)
                }
            default:
                break
            }
        }
    }
}

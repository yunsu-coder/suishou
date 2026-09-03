import AppKit
import WebKit
import UniformTypeIdentifiers
import AVFoundation

/// JSON 字符串转 JS 字符串字面量（通用；渲染器类内也有同名私有）
func exportJSString(_ s: String) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: [s]),
          let arr = String(data: data, encoding: .utf8) else { return "\"\"" }
    return String(arr.dropFirst().dropLast())
}

/// 导出 —— 一键直达 ~/Downloads/随手导出/，成功/失败都有明确反馈
@MainActor
enum ExportService {

    static func posterizeMedia(web: WKWebView, completion: @escaping () -> Void) {
        let collectJS = "(function(){var out=[];document.querySelectorAll('video[src],audio[src]').forEach(function(el){out.push(el.getAttribute('src'))});return out;})()"
        web.evaluateJavaScript(collectJS) { result, _ in
            guard let srcs = result as? [String], !srcs.isEmpty else { completion(); return }
            var imgs: [String: String] = [:]
            var index = 0
            func next() {
                if index >= srcs.count { finish(); return }
                let src = srcs[index]; index += 1
                guard let url = URL(string: src), url.isFileURL, let data = Self.videoFirstFrame(url: url) else {
                    next(); return
                }
                imgs[src] = "data:image/png;base64," + data.base64EncodedString()
                next()
            }
            func finish() {
                guard !imgs.isEmpty else { completion(); return }
                // 构造替换 JS：<video|audio> → <img>
                var entries: [String] = []
                for (k, v) in imgs {
                    entries.append("\"" + exportJSString(k) + "\":\"" + exportJSString(v) + "\"")
                }
                let map = "{" + entries.joined(separator: ",") + "}"
                let replaceJS = """
                (function(){var m=\(map);document.querySelectorAll('video[src],audio[src]').forEach(function(el){
                  var s=el.getAttribute('src'),u=m[s];
                  if(u){var img=document.createElement('img');img.src=u;img.alt='视频';img.style.maxWidth='100%';img.style.borderRadius='10px';img.style.display='block';el.replaceWith(img);}
                });})()
                """
                web.evaluateJavaScript(replaceJS) { _, _ in completion() }
            }
            next()
        }
    }

    /// 视频首帧 PNG（0.5s 兜底 0s；最大 1280×720；AVFoundation 同步提取；CLI/回调上下文亦可用）
    nonisolated static func videoFirstFrame(url: URL) -> Data? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1280, height: 720)
        for t in [0.5, 0.0] {
            let time = CMTime(seconds: t, preferredTimescale: 600)
            if let cg = try? gen.copyCGImage(at: time, actualTime: nil) {
                let rep = NSBitmapImageRep(cgImage: cg)
                if let d = rep.representation(using: .png, properties: [:]) { return d }
            }
        }
        return nil
    }

    /// 便携包：把文档里引用的工作台资源（source/…）拷入与导出文件同级的 `<标题>_assets/`，
    /// 并把 src/href 重写为 assets/…（整包可拷贝、可离线打开：附件可点、视频可播）。
    static func provisionAssets(in doc: String, title: String, baseDir: URL?) -> String {
        let fm = FileManager.default
        let dl = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let exportDir = dl.appendingPathComponent(_L("随手导出", "Export"), isDirectory: true)
        try? fm.createDirectory(at: exportDir, withIntermediateDirectories: true)
        let safe = sanitize(title)
        var assetsDir = exportDir.appendingPathComponent(safe + "_assets", isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: assetsDir.path) {
            assetsDir = exportDir.appendingPathComponent("\(safe)_assets \(n)", isDirectory: true)
            n += 1
        }
        try? fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        let pattern = "(src|href)=\"(source/[^\"#]+?)\""
        guard let re = try? NSRegularExpression(pattern: pattern) else { return doc }
        let ns = doc as NSString
        let range = NSRange(location: 0, length: ns.length)
        var replacements: [(NSRange, String)] = []
        var copiedNames: [String: String] = [:] // 引用串 → 落盘名（防重名）
        let matches = re.matches(in: doc, range: range)
        for m in matches {
            let attr = ns.substring(with: m.range(at: 1))
            let ref = ns.substring(with: m.range(at: 2))
            guard let baseDir else { break }
            var finalName = copiedNames[ref] ?? (ref as NSString).lastPathComponent
            if copiedNames[ref] == nil {
                var dest = assetsDir.appendingPathComponent(finalName)
                var i = 2
                while fm.fileExists(atPath: dest.path) {
                    let ext = (finalName as NSString).pathExtension
                    let base = (finalName as NSString).deletingPathExtension
                    finalName = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
                    dest = assetsDir.appendingPathComponent(finalName)
                    i += 1
                }
                let srcURL = baseDir.appendingPathComponent(ref)
                if fm.fileExists(atPath: srcURL.path) {
                    try? fm.copyItem(at: srcURL, to: dest)
                }
                copiedNames[ref] = finalName
            }
            let full = NSRange(location: m.range(at: 1).location,
                               length: m.range(at: 2).location + m.range(at: 2).length - m.range(at: 1).location)
            replacements.append((full, "\(attr)=\"assets/\(finalName)\""))
        }
        var out = doc
        for item in replacements.sorted(by: { $0.0.location > $1.0.location }) {
            out = (out as NSString).replacingCharacters(in: item.0, with: item.1)
        }
        return out
    }

    /// 单文件化导出：卡片/链接里的 source/… 资源 → data URL 内联（≤40MB/件；超出保持原路径）
    static func inlineAssets(in doc: String, baseDir: URL?) -> String {
        guard let baseDir else { return doc }
        let pattern = "(src|href)=\"([.]?[/]?source/[^\"#]+?)\""
        guard let re = try? NSRegularExpression(pattern: pattern) else { return doc }
        let ns = doc as NSString
        var out = doc
        var inlinedMedia = false
        for m in re.matches(in: doc, range: NSRange(location: 0, length: ns.length)).reversed() {
            let ref = ns.substring(with: m.range(at: 2))
            let url = baseDir.appendingPathComponent(ref)
            guard let data = try? Data(contentsOf: url), data.count <= 40 * 1024 * 1024 else { continue }
            let ext = (ref as NSString).pathExtension.lowercased()
            let mimes: [String: String] = [
                "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
                "mp4": "video/mp4", "mov": "video/quicktime", "mp3": "audio/mpeg",
                "pdf": "application/pdf", "zip": "application/zip",
                "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                "doc": "application/msword",
                "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                "xls": "application/vnd.ms-excel",
            ]
            let mime = mimes[ext] ?? "application/octet-stream"
            let dataURL = "data:\(mime);base64," + data.base64EncodedString()
            out = (out as NSString).replacingCharacters(in: m.range(at: 2), with: dataURL) // 替换 ref 分组（src/href 属性名保留）
            if mime.hasPrefix("video/") || mime.hasPrefix("audio/") { inlinedMedia = true }
        }
        // Safari 禁止 <video>/<audio> 使用 data: URL（Chrome/安卓可以）→ 注入启动脚本把
        // data 媒体转成 Blob URL（Safari 对 blob 视频放行）—— 单一文件跨浏览器真正可播
        if inlinedMedia {
            let patch = """
            <script>
            (function(){
              function fix(){
                document.querySelectorAll('video[src^="data:"],audio[src^="data:"]').forEach(function(el){
                  var raw = el.getAttribute('src');
                  var comma = raw.indexOf(',');
                  var meta = raw.slice(5, raw.indexOf(';'));
                  var bin = atob(raw.slice(comma + 1));
                  var bytes = new Uint8Array(bin.length);
                  for (var i = 0; i < bin.length; i++) { bytes[i] = bin.charCodeAt(i); }
                  el.src = URL.createObjectURL(new Blob([bytes], { type: meta }));
                });
              }
              if (document.readyState === 'complete') { fix(); }
              else { window.addEventListener('DOMContentLoaded', fix); }
            })();
            </script>
            """
            out = out.replacingOccurrences(of: "</body>", with: patch + "</body>")
        }
        return out
    }

    /// JSON 字符串转 JS 字符串字面量（避免模板转义错误）


    // MARK: - 直接写盘（MD / TXT）

    static func exportMD(_ store: NotesStore) {
        let url = destination(title: store.currentTitle, ext: "md")
        do {
            try Data(store.workingText.utf8).write(to: url, options: .atomic)
            presentSaved(url)
        } catch {
            presentError(_L("导出失败", "Export failed"), error)
        }
    }

    static func exportTXT(_ store: NotesStore) {
        let url = destination(title: store.currentTitle, ext: "txt")
        do {
            try Data(store.workingText.utf8).write(to: url, options: .atomic)
            presentSaved(url)
        } catch {
            presentError(_L("导出失败", "Export failed"), error)
        }
    }

    // MARK: - 目标目录 & 反馈

    /// ~/Downloads/随手导出/（同名自动加序号）
    static func destination(title: String, ext: String) -> URL {
        let dl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let dir = dl.appendingPathComponent(_L("随手导出", "Export"), isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = sanitize(title)
        var url = dir.appendingPathComponent(base + "." + ext)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }

    /// 保存渲染产物（PDF / HTML）
    static func saveRendered(_ data: Data, ext: String, title: String) {
        let url = destination(title: title, ext: ext)
        do {
            try data.write(to: url, options: .atomic)
            presentSaved(url)
        } catch {
            presentError(_L("导出失败", "Export failed"), error)
        }
    }

    private static func presentSaved(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = _L("导出完成", "Export Complete")
        alert.informativeText = _L("已保存到：\n\(url.path)", "Saved to:\n\(url.path)")
        alert.alertStyle = .informational
        alert.addButton(withTitle: _L("好", "OK"))
        alert.addButton(withTitle: _L("在 Finder 中显示", "Show in Finder"))
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private static func presentError(_ message: String, _ error: Error) {
        NSAlert(error: NSError(domain: "MarkNote.Export", code: -1,
                               userInfo: [NSLocalizedDescriptionKey: _L("\(message)：\(error.localizedDescription)", "\(message): \(error.localizedDescription)")]))
            .runModal()
    }

    /// 渲染端失败反馈入口
    static func presentExportError(_ error: Error) {
        presentError(_L("导出失败", "Export failed"), error)
    }

    // MARK: - 导出器生命周期托管
    // WebKit 导出器必须在完成前保持强引用（局部变量释放 → WebView 死掉 → 导出"没生效"）

    private static var activeExporters: [ObjectIdentifier: NSObject] = [:]

    static func track(_ exporter: NSObject) {
        activeExporters[ObjectIdentifier(exporter)] = exporter
    }

    static func untrack(_ exporter: NSObject) {
        activeExporters[ObjectIdentifier(exporter)] = nil
    }

    /// 导出独立 HTML（预览渲染产物 + 内联样式，任何浏览器可打开）
    static func exportHTML(_ store: NotesStore) {
        guard FeatureModules.isEnabled(FeatureModules.exportHTML) else {
            store.showHint(_L("导出 HTML 已在设置中关闭", "Export HTML is disabled in Settings"))
            return
        }

        launchHTMLExporter(store, silent: false)
    }

    /// 无 UI 调试导出（--test-export）：同一管线，静默落盘 — 自测闭环用
    static func debugExportHTML(_ store: NotesStore) {
        launchHTMLExporter(store, silent: true)
    }

    private static func launchHTMLExporter(_ store: NotesStore, silent: Bool) {
        guard store.selectedNoteID != nil else { return }
        // C-02：导出前与预览同源内联相对路径图片（data URL），避免跨目录 file:// 被 WebKit 拒绝
        let md = store.inlinePreviewImages(store.workingText)
        let title = "debug-" + (store.currentTitle.isEmpty ? _L("无标题", "Untitled") : store.currentTitle)
        let basePath = {
            var s = store.notesDir.standardizedFileURL.absoluteString
            return s.hasSuffix("/") ? s : s + "/"
        }()

        let config = WKWebViewConfiguration()
        let web = WKWebView(frame: .zero, configuration: config)
        let exporter = HTMLExporter(webView: web, md: md, basePath: basePath, title: title, silent: silent)
        track(exporter)
        exporter.start()
    }

    static func exportPDF(_ store: NotesStore) {
        guard FeatureModules.isEnabled(FeatureModules.exportPDF) else {
            store.showHint(_L("导出 PDF 已在设置中关闭", "Export PDF is disabled in Settings"))
            return
        }

        guard store.selectedNoteID != nil else { return }
        // C-02：导出前与预览同源内联相对路径图片
        let md = store.inlinePreviewImages(store.workingText)
        let title = store.currentTitle.isEmpty ? _L("无标题", "Untitled") : store.currentTitle
        let basePath = {
            var s = store.notesDir.standardizedFileURL.absoluteString
            return s.hasSuffix("/") ? s : s + "/"
        }()

        let config = WKWebViewConfiguration()
        // 注意：任何 allowFileAccessFromFileURLs 之类 KVC key 都会在此崩溃（iOS-only），
        // 资源访问统一走 loadFileURL 的 allowingReadAccessTo 授权。
        let web = WKWebView(frame: .zero, configuration: config)
        let exporter = PDFExporter(webView: web, md: md, basePath: basePath, title: title)
        track(exporter)
        exporter.start()
    }
    /// 预览深色判定（与 PreviewView.effectiveDark 对齐：主题强制优先，system 跟随外观）
    static var effectiveDark: Bool {
        return false // 晨曦 → 恒浅色
    }

    /// KaTeX 渲染产物需要 katex.min.css + 数学字体才能正确呈现。
    /// 导出 HTML 时：内联 CSS 并把 20 个 woff2 字体转 base64（strip woff/ttf 冗余声明），
    /// 离线 / 换机打开均正常。静态缓存；任何缺失时回退空串（调用方降级）。
    private static var kaTeXInlineCache: String?
    static func kaTeXInlineCSS() -> String {
        if let c = kaTeXInlineCache { return c }
        guard let cssURL = Bundle.module.url(forResource: "katex.min", withExtension: "css", subdirectory: "Resources/vendor"),
              var css = try? String(contentsOf: cssURL, encoding: .utf8) else {
            kaTeXInlineCache = ""
            return ""
        }
        // 1) 剔除 woff / ttf 冗余声明（保留 woff2 优先）
        let strip = try? NSRegularExpression(pattern: #",url\(fonts/[^)]+\.(?:woff|ttf)\)[^,]+\)"#)
        if let strip {
            css = strip.stringByReplacingMatches(in: css, range: NSRange(location: 0, length: (css as NSString).length), withTemplate: "")
        }
        // 2) woff2 → data URL
        let mstr = NSMutableString(string: css)
        let re = try? NSRegularExpression(pattern: #"url\(fonts/([^)]+\.woff2)\)"#)
        if let re {
            let ns = mstr as NSString
            let matches = re.matches(in: mstr as String, range: NSRange(location: 0, length: ns.length))
            for m in matches.reversed() where m.numberOfRanges > 1 {
                let name = ns.substring(with: m.range(at: 1))
                guard let fontURL = Bundle.module.url(forResource: (name as NSString).deletingPathExtension,
                                                      withExtension: "woff2",
                                                      subdirectory: "Resources/vendor/fonts"),
                      let data = try? Data(contentsOf: fontURL) else { continue }
                let b64 = data.base64EncodedString()
                mstr.replaceCharacters(in: m.range, with: "url(data:font/woff2;base64,\(b64))")
            }
        }
        kaTeXInlineCache = mstr as String
        return kaTeXInlineCache ?? ""
    }

    private static func sanitize(_ name: String) -> String {
        let bad = "\\/:*?\"<>|\n\r"
        return String(name.map { bad.contains($0) ? "_" : $0 }.prefix(60))
    }
}

/// 离屏 WebView 生命周期助手：挂载到窗口树（否则 loadFileURL 不完成）+ 超时保护
private final class WebHost {
    let web: WKWebView
    private var timeout: DispatchWorkItem?
    private let onTimeout: () -> Void

    private let timeoutSeconds: Double
    init(web: WKWebView, timeoutSeconds: Double = 15, onTimeout: @escaping () -> Void) {
        self.web = web
        self.timeoutSeconds = timeoutSeconds
        self.onTimeout = onTimeout
    }

    func attach() {
        guard let host = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        // 移到屏幕外但在窗口树内（WKWebView 离屏才能完成文档加载）
        web.frame = NSRect(x: -5000, y: -5000, width: 640, height: 480)
        host.contentView?.addSubview(web)
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.detach()
            self.onTimeout()
        }
        timeout = item
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: item)
    }

    func detach() {
        timeout?.cancel()
        web.removeFromSuperview()
    }
}

/// 处理离屏渲染 + PDF 生成 + 直存提示的整个生命周期
private final class PDFExporter: NSObject, WKNavigationDelegate {
    private let web: WKWebView
    private let md: String
    private let basePath: String
    private let title: String
    private var host: WebHost?
    private var finished = false
    private let silent: Bool

    init(webView: WKWebView, md: String, basePath: String, title: String, silent: Bool = false) {
        self.web = webView
        self.md = md
        self.basePath = basePath
        self.title = title
        self.silent = silent
        super.init()
    }

    func start() {
        web.navigationDelegate = self
        let host = WebHost(web: web) { [weak self] in
            self?.finish(.failure(NSError(domain: "MarkNote.Export", code: -1,
                                          userInfo: [NSLocalizedDescriptionKey: _L("导出超时（15 秒），请重试", "Export timed out (15 seconds). Please retry.")])))
        }
        self.host = host
        host.attach()
        if let html = Bundle.module.url(forResource: "preview", withExtension: "html", subdirectory: "Resources") {
            web.loadFileURL(html, allowingReadAccessTo: Bundle.module.resourceURL ?? html.deletingLastPathComponent())
        } else {
            finish(.failure(NSError(domain: "MarkNote.Export", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: _L("预览资源缺失", "Preview resources missing")])))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 主题一致化（C-02 收尾）：暗色判定 + data-theme + colorScheme 与预览对齐
        let dark = ExportService.effectiveDark
        let themeJS = currentTheme.dataTheme.map { Self.jsString($0) } ?? "null"
        let js = """
        if (window.renderMd) {
          window.renderMd(\(Self.jsString(md)), \(Self.jsString(basePath)), { dark: \(dark), resetScroll: true, exportMode: true, posterMode: true });
          document.documentElement.style.colorScheme = \(dark) ? 'dark' : 'light';
          if (\(themeJS)) { document.documentElement.dataset.theme = \(themeJS); }
          else { delete document.documentElement.dataset.theme; }
        }
        """
        web.evaluateJavaScript(js) { [weak self] _, _ in
            // PDF 导出：视频/音频 → 首帧海报图（无回退卡片兜底）
            guard let self else { return }
            ExportService.posterizeMedia(web: web) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.createPDF()
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(NSError(domain: "MarkNote.Export", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: _L("渲染页加载失败：\(error.localizedDescription)", "Failed to load render page: \(error.localizedDescription)")])))
    }

    /// 导出媒体海报化：<video>/<audio> → 首帧图（<img data URL>），静态导出（PDF/HTML）可读
    fileprivate static func jsString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              let arr = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(arr.dropFirst().dropLast())
    }

    private func createPDF() {
        let config = WKPDFConfiguration()
        web.createPDF(configuration: config) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let data) where !data.isEmpty:
                DispatchQueue.main.async {
                    // PDF 静态介质：从渲染页面收集 source/ 引用 → 原件拷入同级 “标题_assets/”（整包分享）
                    let collectJS = "(function(){var o=[];document.querySelectorAll('[href]').forEach(function(e){var h=e.getAttribute('href');if(h&&h.indexOf('source/')===0){o.push(h)}});return o;})()"
                    self.web.evaluateJavaScript(collectJS) { result, _ in
                        let refs = (result as? [String]) ?? []
                        if !refs.isEmpty, let base = URL(string: self.basePath) {
                            _ = ExportService.provisionAssets(
                                in: refs.map { "href=\"\($0)\"" }.joined(separator: " "),
                                title: self.title, baseDir: base)
                        }
                        self.finish(.success(data))
                    }
                }
            case .failure(let e):
                DispatchQueue.main.async { self.finish(.failure(e)) }
            default:
                DispatchQueue.main.async {
                    self.finish(.failure(NSError(domain: "MarkNote.Export", code: -1,
                                                userInfo: [NSLocalizedDescriptionKey: _L("浏览器无法生成 PDF，请重试或改用 HTML 导出", "Could not generate PDF. Please retry or export as HTML instead.")])))
                }
            }
        }
    }

    /// 统一出口：自检钩子吞结果；正常路径直存 + 提示
    private func finish(_ result: Result<Data, Error>) {
        guard !finished else { return }
        finished = true
        host?.detach()
        ExportService.untrack(self)
        switch result {
        case .success(let data):
            ExportService.saveRendered(data, ext: "pdf", title: title)
        case .failure(let e):
            ExportService.presentExportError(e)
        }
    }
}

/// 离屏渲染 → 拉取渲染后 HTML + 内联 CSS → 保存独立文件
private final class HTMLExporter: NSObject, WKNavigationDelegate {
    private let web: WKWebView
    private let md: String
    private let basePath: String
    private let title: String
    private var host: WebHost?
    private var finished = false
    private let silent: Bool

    init(webView: WKWebView, md: String, basePath: String, title: String, silent: Bool = false) {
        self.web = webView
        self.md = md
        self.basePath = basePath
        self.title = title
        self.silent = silent
        super.init()
    }

    func start() {
        web.navigationDelegate = self
        let host = WebHost(web: web) { [weak self] in
            self?.fail(_L("导出超时（15 秒），请重试", "Export timed out (15 seconds). Please retry."))
        }
        self.host = host
        host.attach()
        if let html = Bundle.module.url(forResource: "preview", withExtension: "html", subdirectory: "Resources") {
            web.loadFileURL(html, allowingReadAccessTo: Bundle.module.resourceURL ?? html.deletingLastPathComponent())
        }
    }

    private func fail(_ message: String) {
        guard !finished else { return }
        finished = true
        host?.detach()
        NSAlert(error: NSError(domain: "MarkNote.Export", code: -1, userInfo: [NSLocalizedDescriptionKey: message]))
            .runModal()
    }

    private func succeed(_ url: URL) {
        finished = true
        host?.detach()
        let alert = NSAlert()
        alert.messageText = _L("导出完成", "Export Complete")
        alert.informativeText = _L("已导出到：\n\(url.path)", "Exported to:\n\(url.path)")
        alert.alertStyle = .informational
        alert.addButton(withTitle: _L("好", "OK"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(_L("渲染页加载失败：\(error.localizedDescription)", "Failed to load render page: \(error.localizedDescription)"))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let dark = ExportService.effectiveDark
        let themeJS = currentTheme.dataTheme.map { PDFExporter.jsString($0) } ?? "null"
        let js = """
        if (window.renderMd) {
          window.renderMd(\(PDFExporter.jsString(md)), \(PDFExporter.jsString(basePath)), { dark: \(dark), resetScroll: true, exportMode: true });
          if (\(themeJS)) { document.documentElement.dataset.theme = \(themeJS); }
          else { delete document.documentElement.dataset.theme; }
        }
        """
        web.evaluateJavaScript(js) { [weak self] _, _ in
            guard let self else { return }
            // HTML 导出：视频/音频 → 首帧海报图
            ExportService.posterizeMedia(web: web) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.fetchHTML()
                }
            }
        }
    }

    private func fetchHTML() {
        web.evaluateJavaScript("document.getElementById('content').innerHTML", completionHandler: { [weak self] (result: Any?, _: Error?) in
            guard let self, let html = result as? String else {
                DispatchQueue.main.async { self?.fail(_L("渲染结果为空", "Render result is empty")) }
                return
            }
            let content = html
            // C-03：KaTeX 样式 + 数学字体随 HTML 内嵌（离线/换机可打开）
            let css = Self.readPreviewCSS() + "\n\n" + ExportService.kaTeXInlineCSS()
            let doc = """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            <title>\(self.sanitizedTitle)</title>
            <style>
            \(css)
            </style>
            </head>
            <body>
            <article class="markdown-body">
            \(content)
            </article>
            </body>
            </html>
            """
            DispatchQueue.main.async {
                // 默认 = 单文件 HTML：全部引用资源内联 data URL（一个文件拖拽即达）
                let finalDoc = ExportService.inlineAssets(in: doc, baseDir: URL(string: self.basePath))
                let data = Data(finalDoc.utf8)
                self.finished = true
                self.host?.detach()
                ExportService.untrack(self)
                if self.silent {
                    // 调试导出（--test-export）：静默落盘、无弹窗；回传渲染标志存入文件名
                    let url = ExportService.destination(title: self.title, ext: "html")
                    try? data.write(to: url, options: .atomic)
                } else {
                    ExportService.saveRendered(data, ext: "html", title: self.title)
                }
            }
        })
    }

    private var sanitizedTitle: String {
        title.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func readPreviewCSS() -> String {
        guard let css = Bundle.module.url(forResource: "preview", withExtension: "css", subdirectory: "Resources"),
              let text = try? String(contentsOf: css, encoding: .utf8) else { return "" }
        return text
    }
}

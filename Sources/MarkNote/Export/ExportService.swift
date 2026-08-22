import AppKit
import WebKit
import UniformTypeIdentifiers

/// 导出 —— 一键直达 ~/Downloads/随手导出/，成功/失败都有明确反馈
@MainActor
enum ExportService {

    // MARK: - 直接写盘（MD / TXT）

    static func exportMD(_ store: NotesStore) {
        let url = destination(title: store.currentTitle, ext: "md")
        do {
            try Data(store.workingText.utf8).write(to: url, options: .atomic)
            presentSaved(url)
        } catch {
            presentError("导出失败", error)
        }
    }

    static func exportTXT(_ store: NotesStore) {
        let url = destination(title: store.currentTitle, ext: "txt")
        do {
            try Data(store.workingText.utf8).write(to: url, options: .atomic)
            presentSaved(url)
        } catch {
            presentError("导出失败", error)
        }
    }

    // MARK: - 目标目录 & 反馈

    /// ~/Downloads/随手导出/（同名自动加序号）
    static func destination(title: String, ext: String) -> URL {
        let dl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let dir = dl.appendingPathComponent("随手导出", isDirectory: true)
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
            presentError("导出失败", error)
        }
    }

    private static func presentSaved(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = "导出完成"
        alert.informativeText = "已保存到：\n\(url.path)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "在 Finder 中显示")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private static func presentError(_ message: String, _ error: Error) {
        NSAlert(error: NSError(domain: "MarkNote.Export", code: -1,
                               userInfo: [NSLocalizedDescriptionKey: "\(message)：\(error.localizedDescription)"]))
            .runModal()
    }

    /// 渲染端失败反馈入口
    static func presentExportError(_ error: Error) {
        presentError("导出失败", error)
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
        guard store.selectedNoteID != nil else { return }
        let md = store.workingText
        let title = store.currentTitle.isEmpty ? "无标题" : store.currentTitle
        let basePath = {
            var s = store.notesDir.standardizedFileURL.absoluteString
            return s.hasSuffix("/") ? s : s + "/"
        }()

        let config = WKWebViewConfiguration()
        let web = WKWebView(frame: .zero, configuration: config)
        let exporter = HTMLExporter(webView: web, md: md, basePath: basePath, title: title)
        track(exporter)
        exporter.start()
    }

    static func exportPDF(_ store: NotesStore) {
        guard store.selectedNoteID != nil else { return }
        let md = store.workingText
        let title = store.currentTitle.isEmpty ? "无标题" : store.currentTitle
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

    init(webView: WKWebView, md: String, basePath: String, title: String) {
        self.web = webView
        self.md = md
        self.basePath = basePath
        self.title = title
        super.init()
    }

    func start() {
        web.navigationDelegate = self
        let host = WebHost(web: web) { [weak self] in
            self?.finish(.failure(NSError(domain: "MarkNote.Export", code: -1,
                                          userInfo: [NSLocalizedDescriptionKey: "导出超时（15 秒），请重试"])))
        }
        self.host = host
        host.attach()
        if let html = Bundle.module.url(forResource: "preview", withExtension: "html", subdirectory: "Resources") {
            web.loadFileURL(html, allowingReadAccessTo: Bundle.module.resourceURL ?? html.deletingLastPathComponent())
        } else {
            finish(.failure(NSError(domain: "MarkNote.Export", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "预览资源缺失"])))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let js = "if (window.renderMd) { window.renderMd(\(Self.jsString(md)), \(Self.jsString(basePath)), { dark: true }); }"
        web.evaluateJavaScript(js) { [weak self] _, _ in
            // 给懒加载图片留时间，再生成 PDF
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard let self else { return }
                self.createPDF()
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(NSError(domain: "MarkNote.Export", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "渲染页加载失败：\(error.localizedDescription)"])))
    }

    /// JSON 字符串转 JS 字符串字面量（避免模板转义错误）
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
                DispatchQueue.main.async { self.finish(.success(data)) }
            case .failure(let e):
                DispatchQueue.main.async { self.finish(.failure(e)) }
            default:
                DispatchQueue.main.async {
                    self.finish(.failure(NSError(domain: "MarkNote.Export", code: -1,
                                                userInfo: [NSLocalizedDescriptionKey: "浏览器无法生成 PDF，请重试或改用 HTML 导出"])))
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

    init(webView: WKWebView, md: String, basePath: String, title: String) {
        self.web = webView
        self.md = md
        self.basePath = basePath
        self.title = title
        super.init()
    }

    func start() {
        web.navigationDelegate = self
        let host = WebHost(web: web) { [weak self] in
            self?.fail("导出超时（15 秒），请重试")
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
        alert.messageText = "导出完成"
        alert.informativeText = "已导出到：\n\(url.path)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail("渲染页加载失败：\(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let dark = currentTheme.dataTheme != nil ? currentTheme.dataTheme != "dawn" : true
        let themeJS = currentTheme.dataTheme.map { PDFExporter.jsString($0) } ?? "null"
        let js = """
        if (window.renderMd) {
          window.renderMd(\(PDFExporter.jsString(md)), \(PDFExporter.jsString(basePath)), { dark: \(dark), resetScroll: true });
          if (\(themeJS)) { document.documentElement.dataset.theme = \(themeJS); }
          else { delete document.documentElement.dataset.theme; }
        }
        """
        web.evaluateJavaScript(js) { [weak self] _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.fetchHTML()
            }
        }
    }

    private func fetchHTML() {
        web.evaluateJavaScript("document.getElementById('content').innerHTML", completionHandler: { [weak self] (result: Any?, _: Error?) in
            guard let self, let html = result as? String else {
                DispatchQueue.main.async { self?.fail("渲染结果为空") }
                return
            }
            let content = html
            let css = Self.readPreviewCSS()
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
                let data = Data(doc.utf8)
                self.finished = true
                self.host?.detach()
                ExportService.untrack(self)
                ExportService.saveRendered(data, ext: "html", title: self.title)
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

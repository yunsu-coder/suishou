import Foundation

/// 「贴链接导入」：把你自己在浏览器 / App 里看到的页面链接丢进采集器，直接抓成素材。
///
/// 适用场景：社交平台（X、微博…）的帖子、单张图片的直链、一篇文章的地址。
/// 采集方式与站点账号一致：**用你本机的登录会话去读你能看到的页面**，
/// 不绕过站点自身的登录 / 年龄 / 付费门槛，也不做平台批量爬取。
enum CollectorLinkImport {

    /// 解析一批链接 → 候选（返回失败原因，逐条报账）
    @MainActor
    static func candidates(from raw: String) async -> (items: [CollectCandidate], failures: [String]) {
        var items: [CollectCandidate] = []
        var failures: [String] = []
        for line in raw.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                failures.append(_L("\(text.prefix(40))：不是有效的 http(s) 链接", "\(text.prefix(40)): not an http(s) link"))
                continue
            }
            if let c = await candidate(for: url) {
                items.append(c)
            } else {
                failures.append(_L("\(url.host ?? "?")：没能从这页里找到可下载的图片或视频（需要登录的请先在「站点账号」里登录）",
                                   "\(url.host ?? "?"): no downloadable media found"))
            }
        }
        // 同一条链接只留一个
        var seen = Set<String>()
        return (items.filter { seen.insert($0.pageURL?.absoluteString ?? $0.id).inserted }, failures)
    }

    /// 单条链接 → 候选。图片/视频直链直接判断；网页则抓页面找 og:video / og:image。
    @MainActor
    static func candidate(for url: URL) async -> CollectCandidate? {
        let ext = url.pathExtension.lowercased()
        if kindForExtension(ext) == "image" {
            var c = CollectCandidate(id: url.absoluteString, kind: "image",
                                     title: url.deletingPathExtension().lastPathComponent,
                                     thumbURL: url, fullURL: url, pageURL: url, duration: nil)
            c.sourceLabel = url.host
            return c
        }
        if kindForExtension(ext) == "video" {
            var c = CollectCandidate(id: url.absoluteString, kind: "video",
                                     title: url.deletingPathExtension().lastPathComponent,
                                     thumbURL: nil, fullURL: nil, pageURL: url, duration: nil)
            c.videoURL = url
            c.sourceLabel = url.host
            return c
        }
        // 网页：先用 HTTP 抓（带站点账号 cookie），太薄再用应用内浏览器渲染
        var html = await CollectorSearch.fetch(url)
        var media = html.map { mediaURLs(inHTML: $0, base: url) }
        if media == nil || (media?.video == nil && media?.image == nil) {
            if let rendered = await CollectorWebRender.render(url, minChars: 200, timeout: 14) {
                let m = mediaURLs(inHTML: rendered, base: url)
                if m.video != nil || m.image != nil { media = m; html = rendered }
            }
        }
        guard let media else { return nil }
        let isVideo = media.video != nil
        let title = pageTitle(inHTML: html ?? "") ?? url.host ?? url.absoluteString
        var c = CollectCandidate(id: url.absoluteString, kind: isVideo ? "video" : "image",
                                 title: title, thumbURL: media.image, fullURL: isVideo ? nil : media.image,
                                 pageURL: url, duration: nil)
        c.videoURL = media.video
        c.sourceLabel = url.host
        c.metaLine = _L(isVideo ? "视频 · 来自链接导入" : "图片 · 来自链接导入",
                        isVideo ? "video · imported from link" : "image · imported from link")
        return (media.video != nil || media.image != nil) ? c : nil
    }

    /// 按扩展名判断直链类型（纯函数，便于测试）
    static func kindForExtension(_ ext: String) -> String? {
        let e = ext.lowercased()
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "avif", "heic", "bmp", "tiff"]
        let videoExts: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv", "avi", "flv"]
        if imageExts.contains(e) { return "image" }
        if videoExts.contains(e) { return "video" }
        return nil
    }

    /// 页面里的媒体地址：og:video（含 secure_url / twitter:player:stream）优先，其次 og:image
    static func mediaURLs(inHTML html: String, base: URL) -> (video: URL?, image: URL?) {
        func first(_ patterns: [String]) -> URL? {
            for p in patterns {
                if let s = HTMLToMarkdown.firstRegexGroup(html, pattern: p),
                   let u = HTMLToMarkdown.absolute(decode(s), base: base) {
                    return URL(string: u)
                }
            }
            return nil
        }
        let video = first([
            #"(?is)<meta[^>]+property\s*=\s*"og:video:secure_url"[^>]*content\s*=\s*"([^"]+)""#,
            #"(?is)<meta[^>]+content\s*=\s*"([^"]+)"[^>]*property\s*=\s*"og:video:secure_url""#,
            #"(?is)<meta[^>]+property\s*=\s*"og:video(?::url)?"[^>]*content\s*=\s*"([^"]+)""#,
            #"(?is)<meta[^>]+name\s*=\s*"twitter:player:stream"[^>]*content\s*=\s*"([^"]+)""#,
        ])
        let image = first([
            #"(?is)<meta[^>]+property\s*=\s*"og:image(?::secure_url)?"[^>]*content\s*=\s*"([^"]+)""#,
            #"(?is)<meta[^>]+content\s*=\s*"([^"]+)"[^>]*property\s*=\s*"og:image""#,
            #"(?is)<meta[^>]+name\s*=\s*"twitter:image"[^>]*content\s*=\s*"([^"]+)""#,
        ])
        return (video, image)
    }

    private static func pageTitle(inHTML html: String) -> String? {
        HTMLToMarkdown.firstRegexGroup(html, pattern: #"(?is)<meta[^>]+property\s*=\s*"og:title"[^>]*content\s*=\s*"([^"]+)""#)
            .map(decode)
            ?? HTMLToMarkdown.firstRegexGroup(html, pattern: #"(?is)<title[^>]*>(.*?)</title>"#).map(decode)?.trimmed
    }

    private static func decode(_ s: String) -> String {
        HTMLToMarkdown.decodeEntities(s).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

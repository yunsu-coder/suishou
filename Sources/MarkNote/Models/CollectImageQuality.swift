import Foundation

/// 采集到的图片 URL 归一化：**能要原图就别要缩略图**。
///
/// 同一个图在站点上通常有多个尺寸变体，只是 URL 参数/路径不同：
/// - X/Twitter：`?name=small|medium|360x360` → `?name=orig`
/// - 微博：路径 `/thumb150/` `/small/` `/mw690/` `/orj360/` → `/large/`
/// - 各类 CDN：`?w=200&h=200&quality=60` 这类"缩图参数"直接去掉
/// - 后缀式：`xxx@300w.webp`、`xxx~300x300.image` → 去掉尺寸后缀
///
/// 只做"同源换参数"的事，不猜别的站点结构；改不动就原样返回。
enum CollectImageQuality {

    /// 会缩小图片、且去掉后不影响取图的查询参数
    static let cosmeticParams: Set<String> = [
        "w", "width", "h", "height", "resize", "quality", "q", "size", "thumbnail", "thumb",
        "crop", "fit", "imageview2", "imagemogr2", "image_process", "x-oss-process",
        "param", "compress", "scale", "maxwidth", "maxheight",
    ]

    static func upgrade(_ url: URL?) -> URL {
        guard let url else { return URL(string: "about:blank")! }
        return upgrade(url)
    }

    static func upgrade(_ url: URL) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let host = (comps.host ?? "").lowercased()

        // X / Twitter：直接切到 orig（保留 format，其他尺寸参数丢掉）
        if host.contains("twimg.com") {
            var items = (comps.queryItems ?? []).filter { $0.name != "name" && $0.name != "w" && $0.name != "h" }
            items.append(URLQueryItem(name: "name", value: "orig"))
            comps.queryItems = items
            return comps.url ?? url
        }

        // 微博图床：路径上的尺寸目录换成 large
        if host.contains("sinaimg.cn") {
            let smallDirs = ["/thumb150/", "/thumb180/", "/thumbnail/", "/small/", "/mw690/", "/orj360/", "/square/"]
            var path = comps.path
            for d in smallDirs where path.hasPrefix(d) {
                path = "/large/" + path.dropFirst(d.count)
                break
            }
            comps.path = path
            return comps.url ?? url
        }

        // 通用：去掉缩图参数
        if let items = comps.queryItems, !items.isEmpty {
            let kept = items.filter { !cosmeticParams.contains($0.name.lowercased()) }
            if kept.count != items.count { comps.queryItems = kept.isEmpty ? nil : kept }
        }

        // 后缀式尺寸：@300w.webp / @720w_1e_1c.jpg / ~300x300.image
        var s = comps.url?.absoluteString ?? url.absoluteString
        s = stripSizeSuffix(s)
        return URL(string: s) ?? comps.url ?? url
    }

    /// `...@300w.webp`、`...@720w_1e_1c.webp`、`...~300x300.image` 这类后缀去掉
    static func stripSizeSuffix(_ s: String) -> String {
        var out = s
        if let r = out.range(of: "@[0-9]+w[^.]*\\.[a-zA-Z0-9]+$", options: .regularExpression) {
            out.removeSubrange(r)
        }
        if let r = out.range(of: "~[0-9]+x[0-9]+\\.[a-zA-Z0-9]+$", options: .regularExpression) {
            out.removeSubrange(r)
        }
        return out
    }

    /// 同一张图可能在候选里出现多次（同图不同尺寸）：归一化后用它判重
    static func identity(for url: URL) -> String {
        upgrade(url).absoluteString.lowercased()
    }
}

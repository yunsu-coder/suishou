import Foundation

// MARK: - 采集需求（卡片式确认的数据模型）

/// 采集需求：AI 解析用户的话填入这些字段，缺失的必填项在卡片上高亮追问，填齐才允许采集。
struct CollectRequest: Codable, Equatable {
    /// "image" / "video"；nil = 还没确定（必填）
    var kind: String?
    /// 主题（必填）：越具体越好，如「赛博朋克霓虹街道」
    var subject: String?
    /// 用途（可选）：封面 / 配图 / 视频素材 / 参考……
    var usage: String?
    /// 风格细化（可选）
    var style: String?
    /// 想要的数量（默认 8）
    var count: Int = 8
    /// 明确不要的东西（可选）
    var avoid: String?
    /// 搜索关键词（AI 生成或自动拼接；中英各一条）
    var queries: [String] = []

    /// 必填但还缺的字段（卡片据此高亮追问）。
    var missing: [String] {
        var out: [String] = []
        if kind == nil { out.append("kind") }
        if (subject ?? "").trimmingCharacters(in: .whitespaces).isEmpty { out.append("subject") }
        return out
    }

    var isReady: Bool { missing.isEmpty }

    /// 根据字段生成搜索词（AI 没给 queries 时的兜底）。
    func composedQueries() -> [String] {
        if !queries.isEmpty { return queries }
        var parts: [String] = []
        if let style, !style.isEmpty { parts.append(style) }
        if let subject, !subject.isEmpty { parts.append(subject) }
        var q = parts.joined(separator: " ")
        if let usage, usage.contains("封面") || usage.contains("cover") { q += " wallpaper" }
        guard !q.isEmpty else { return [] }
        return [q]
    }
}

// MARK: - 候选素材

struct CollectCandidate: Identifiable, Equatable {
    let id: String
    let kind: String              // "image" / "video"
    let title: String
    let thumbURL: URL
    let fullURL: URL?             // 图片原图；视频仅存页面链接
    let pageURL: URL?             // 来源页
    let duration: String?         // 视频时长（"03:24"）
    var selected: Bool = false
}

// MARK: - Bing 搜索客户端（直连可用，无需 API key；只搜用户明确给出的关键词）

enum CollectorSearch {
    private static let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    /// 图片搜索：cn.bing.com/images/async —— 返回 m="{...}" JSON 卡片
    static func searchImages(query: String, count: Int = 24) async -> [CollectCandidate] {
        guard var comp = URLComponents(string: "https://cn.bing.com/images/async") else { return [] }
        comp.queryItems = [
            .init(name: "q", value: query),
            .init(name: "first", value: "0"),
            .init(name: "count", value: "\(max(8, count))"),
            .init(name: "mmasync", value: "1"),
        ]
        guard let url = comp.url, let html = await fetch(url) else { return [] }
        return parseImages(html)
    }

    /// 视频搜索：cn.bing.com/videos/search —— 返回 mmeta="{...}" JSON 卡片（须带 first/count 参数才有多条）
    static func searchVideos(query: String, count: Int = 24) async -> [CollectCandidate] {
        guard var comp = URLComponents(string: "https://cn.bing.com/videos/search") else { return [] }
        comp.queryItems = [
            .init(name: "q", value: query),
            .init(name: "first", value: "1"),
            .init(name: "count", value: "\(max(8, count))"),
            .init(name: "FORM", value: "HDRSC3"),
        ]
        guard let url = comp.url, let html = await fetch(url) else { return [] }
        return parseVideos(html)
    }

    static func fetch(_ url: URL) async -> String? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: 解析（独立出来便于离线测试）

    /// 图片：`m="{&quot;murl&quot;:…}"`（a.iusc 卡片）
    static func parseImages(_ html: String) -> [CollectCandidate] {
        var out: [CollectCandidate] = []
        for raw in captures(pattern: #"class="iusc"[^>]*m="([^"]+)""#, in: html) {
            guard let dict = jsonFromEscaped(raw),
                  let murl = dict["murl"] as? String, let full = URL(string: murl),
                  let turl = dict["turl"] as? String, let thumb = URL(string: turl) else { continue }
            let title = (dict["t"] as? String) ?? (dict["desc"] as? String) ?? full.lastPathComponent
            let page = (dict["purl"] as? String).flatMap(URL.init(string:))
            out.append(CollectCandidate(id: murl, kind: "image", title: title,
                                        thumbURL: thumb, fullURL: full, pageURL: page,
                                        duration: nil))
        }
        return dedupe(out)
    }

    /// 视频：`mmeta="{&quot;murl&quot;:…,&quot;turl&quot;:…}"`（turl 缩略图 / murl 视频页 / vt 标题 / du 时长）
    static func parseVideos(_ html: String) -> [CollectCandidate] {
        var out: [CollectCandidate] = []
        for raw in captures(pattern: #"mmeta="([^"]+)""#, in: html) {
            guard let dict = jsonFromEscaped(raw),
                  let turl = dict["turl"] as? String, let thumb = URL(string: turl),
                  let pageStr = (dict["pgurl"] as? String) ?? (dict["murl"] as? String),
                  let page = URL(string: pageStr) else { continue }
            let title = (dict["vt"] as? String) ?? (dict["vth"] as? String) ?? thumb.lastPathComponent
            out.append(CollectCandidate(id: pageStr, kind: "video", title: title,
                                        thumbURL: thumb, fullURL: nil, pageURL: page,
                                        duration: (dict["du"] as? String)))
        }
        return dedupe(out)
    }

    /// HTML 里 `&quot;` 转义过的 JSON 属性 → 字典
    static func jsonFromEscaped(_ raw: String) -> [String: Any]? {
        let un = unescape(raw)
        guard let data = un.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
    }

    private static func captures(pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap {
            $0.numberOfRanges > 1 ? ns.substring(with: $0.range(at: 1)) : nil
        }
    }

    private static func dedupe(_ list: [CollectCandidate]) -> [CollectCandidate] {
        var seen = Set<String>()
        return list.filter { seen.insert($0.id).inserted }
    }
}

// MARK: - AI 需求解析（把用户的话翻译成 CollectRequest）

enum CollectorIntent {
    /// 用 LLM 把自然语言解析为需求字段；未配置 key 或解析失败 → 返回 nil（走纯手填表单）。
    static func parse(_ text: String, current: CollectRequest) async -> CollectRequest? {
        guard LLM.configured else { return nil }
        let system = """
        你是素材采集需求解析器。把用户的话解析成 JSON（只输出 JSON，不要解释）：
        {"kind":"image|video 或 null","subject":"主题（具体名词，如 赛博朋克霓虹街道；无法确定给 null）",
         "usage":"用途（封面/配图/视频素材/参考；不确定给 null）","style":"风格细化（极简/写实/手绘…；不确定 null）",
         "count":数字或null,"avoid":"明确不要的东西或null",
         "queries":["2-3 条搜索关键词，中英文各一条"]}
        规则：subject 必须贴近用户实际意图，不要泛化；用户没提的字段给 null，不要编造。
        """
        let user = "用户输入：\(text)\n（已有需求：\(describe(current))）"
        guard let reply = try? await LLM.complete(system: system, user: user) else { return nil }
        let jsonText = extractJSON(reply)
        guard let data = jsonText.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var r = current
        if let k = obj["kind"] as? String, k == "image" || k == "video" { r.kind = k }
        if let s = obj["subject"] as? String, !s.isEmpty, s.lowercased() != "null" { r.subject = s }
        if let u = obj["usage"] as? String, !u.isEmpty, u.lowercased() != "null" { r.usage = u }
        if let st = obj["style"] as? String, !st.isEmpty, st.lowercased() != "null" { r.style = st }
        if let c = obj["count"] as? Int { r.count = max(1, min(40, c)) }
        if let av = obj["avoid"] as? String, !av.isEmpty, av.lowercased() != "null" { r.avoid = av }
        if let qs = obj["queries"] as? [String] { r.queries = qs.filter { !$0.isEmpty } }
        return r
    }

    static func describe(_ r: CollectRequest) -> String {
        var parts: [String] = []
        if let k = r.kind { parts.append("类型=\(k)") }
        if let s = r.subject { parts.append("主题=\(s)") }
        if let u = r.usage { parts.append("用途=\(u)") }
        if let st = r.style { parts.append("风格=\(st)") }
        return parts.isEmpty ? "（空）" : parts.joined(separator: "，")
    }

    private static func extractJSON(_ reply: String) -> String {
        if let s = reply.firstIndex(of: "{"), let e = reply.lastIndex(of: "}") {
            return String(reply[s...e])
        }
        return reply
    }
}

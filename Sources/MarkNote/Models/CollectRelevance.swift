import Foundation

/// 采集结果的相关度与去噪 —— 搜索接口给什么就收什么的时代结束了：
/// ① 明显是站点装饰（logo / 图标 / 占位 / 二维码…）的直接剔除；
/// ② 按「标题 + 文件名 + 来源页」对搜索词打分：标题命中权重更高；
/// ③ 标题明明写着内容、却和搜索词一个都不沾边 → 视为不相关剔除（标题为空的不杀、沉底）。
enum CollectRelevance {

    /// 站点装饰词（注意：查询词里自己带了就不算装饰）
    static let junkMarkers = ["logo", "icon", "avatar", "favicon", "sprite", "placeholder",
                              "spinner", "loading", "qrcode", "二维码", "占位"]

    /// 搜索词 → 词元：ASCII 词（≥2）+ 中文 2-gram（中文短串 ≤4 字时整体也算一个）
    static func terms(_ query: String) -> [String] {
        var terms: [String] = []
        var ascii = ""
        var cjk = ""
        func flushASCII() {
            defer { ascii = "" }
            if ascii.count >= 2 { terms.append(ascii.lowercased()) }
        }
        func flushCJK() {
            defer { cjk = "" }
            let chars = Array(cjk)
            guard chars.count >= 2 else { return }
            if chars.count <= 4 { terms.append(cjk) }
            for i in 0..<(chars.count - 1) { terms.append(String(chars[i...(i + 1)])) }
        }
        for ch in query {
            if ch.isASCII, ch.isLetter || ch.isNumber {
                ascii.append(ch)
                flushCJK()
            } else if ch.unicodeScalars.allSatisfy({ (0x4E00...0x9FFF).contains($0.value) }) {
                cjk.append(ch)
                flushASCII()
            } else {
                flushASCII()
                flushCJK()
            }
        }
        flushASCII()
        flushCJK()
        var seen = Set<String>()
        return terms.filter { seen.insert($0).inserted }
    }

    /// 相关度：标题命中 ×2（内容区最可信），文件名 / 来源页命中 ×1
    static func score(_ c: CollectCandidate, terms: [String]) -> Int {
        guard !terms.isEmpty else { return 0 }
        let title = c.title.lowercased()
        var hay = title
        if let u = c.fullURL ?? c.thumbURL {
            hay += " " + u.lastPathComponent.lowercased() + " " + (u.host ?? "").lowercased()
        }
        if let p = c.pageURL { hay += " " + p.absoluteString.lowercased() }
        var s = 0
        for t in terms {
            if hay.contains(t) { s += 1 }
            if title.contains(t) { s += 2 }
        }
        return s
    }

    static func isJunk(_ c: CollectCandidate, query: String) -> Bool {
        let q = query.lowercased()
        let hay = (c.title + " " + (c.fullURL?.absoluteString ?? c.thumbURL?.absoluteString ?? "")).lowercased()
        return junkMarkers.contains { hay.contains($0) && !q.contains($0) }
    }

    /// 排序 + 过筛：装饰图剔除；「有标题却 0 命中」判为不相关；其余按分数排前面
    static func refine(_ list: [CollectCandidate], query: String) -> [CollectCandidate] {
        let t = terms(query)
        var scored: [(c: CollectCandidate, s: Int, title: String)] = []
        for c in list {
            if isJunk(c, query: query) { continue }   // 装饰图：无论有没有词元都先剔除
            let s = score(c, terms: t)
            let title = c.title.lowercased().trimmed
            if !t.isEmpty, !title.isEmpty, s == 0 { continue }   // 有词元才做「不沾边」剔除
            scored.append((c, s, title))
        }
        guard !t.isEmpty else { return scored.map(\.c) }   // 单字查询：只滤装饰图，不改顺序
        return scored.sorted { a, b in
            if a.s != b.s { return a.s > b.s }
            return !a.title.isEmpty && b.title.isEmpty
        }.map(\.c)
    }
}

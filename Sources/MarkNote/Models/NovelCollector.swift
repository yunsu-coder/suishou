import Foundation

/// 小说（以及「文章」入库）的组装：目录页 → 章节列表 → 逐章正文 → 一本 Markdown。
enum NovelCollector {

    struct Chapter: Equatable {
        var title: String
        var url: URL
        var number: Int?
    }

    // MARK: - 目录页 → 章节列表

    /// 章节链接启发式：
    /// 1) 链接文字像「第 12 章 / 第一百二十三章 / 第 12 节」→ 收；
    /// 2) 目录容器（id/class 含 list / chapter / dir / volume，或 `<dd>` 项）里的链接也收；
    /// 3) 去掉「上一章 / 下一章 / 目录 / 首页」这类导航，去重，能解析出章节号就按号排序。
    static func chapters(inHTML html: String, base: URL) -> [Chapter] {
        let tokens = HTMLToMarkdown.tokenize(HTMLToMarkdown.stripNoise(html))
        var out: [Chapter] = []
        var containerDepth = 0
        var ddDepth = 0
        var href: String?
        var text = ""
        var inList = false
        var loose: [Chapter] = []      // 目录容器里但标题不带「第X章」的（先收着，看整页像不像小说目录）

        for t in tokens {
            switch t.kind {
            case .open:
                if isChapterContainer(t) { containerDepth += 1 }
                if t.name == "dd" { ddDepth += 1 }
                if t.name == "a" {
                    href = HTMLToMarkdown.attribute("href", in: t.attrs)
                    text = ""
                    inList = containerDepth > 0 || ddDepth > 0
                }
            case .close:
                if t.name == "a", let raw = href {
                    let title = text.trimmed
                    let link = raw.trimmed
                    if !title.isEmpty, !link.isEmpty, !link.hasPrefix("#"),
                       !link.lowercased().hasPrefix("javascript"),
                       let url = URL(string: link, relativeTo: base)?.absoluteURL,
                       !isNavigation(title) {
                        let number = chapterNumber(inTitle: title)
                        let ch = Chapter(title: title, url: url, number: number)
                        if number != nil {
                            out.append(ch)
                        } else if inList, title.count <= 30 {
                            loose.append(ch)
                        }
                    }
                    href = nil
                }
                if t.name == "dd" { ddDepth = max(0, ddDepth - 1) }
                if isChapterContainer(t) { containerDepth = max(0, containerDepth - 1) }
            case .text:
                if href != nil { text += t.text }
            }
        }

        // 只有「页面上确实有带章节号的链接」才认那些没号的（百科/导航站的目录容器全是普通链接）
        if out.count >= 3 { out += loose }

        // 去重（同 URL / 同标题）
        var seenURL = Set<String>()
        var seenTitle = Set<String>()
        var unique: [Chapter] = []
        for c in out {
            if seenURL.contains(c.url.absoluteString) { continue }
            if c.number == nil, seenTitle.contains(c.title) { continue }
            seenURL.insert(c.url.absoluteString)
            seenTitle.insert(c.title)
            unique.append(c)
        }
        // 大多数能解析出章节号 → 按号排；否则保持页面顺序
        let numbered = unique.compactMap(\.number)
        if numbered.count >= max(2, unique.count / 2) {
            unique.sort { ($0.number ?? Int.max) < ($1.number ?? Int.max) }
        }
        return unique
    }

    /// 目录容器：id/class 像章节目录（中英都认）
    private static func isChapterContainer(_ t: HTMLToMarkdown.Token) -> Bool {
        guard t.kind == .open else { return false }
        let words = ["list", "chapter", "catalog", "directory", "dir", "volume", "playlist",
                     "booklist", "zhangjie", "mulu", "章节", "目录", "article_list", "index"]
        for key in ["id", "class"] {
            guard let v = HTMLToMarkdown.attribute(key, in: t.attrs)?.lowercased() else { continue }
            if words.contains(where: { v.contains($0) }) { return true }
        }
        return false
    }

    /// 「上一章 / 下一章 / 目录 / 首页」这类不是章节
    static func isNavigation(_ title: String) -> Bool {
        let t = title.replacingOccurrences(of: " ", with: "")
        let blocked = ["上一章", "下一章", "上一页", "下一页", "上一节", "下一节", "返回目录",
                       "章节目录", "目录", "首页", "书页", "加入书架", "投推荐票", "求收藏",
                       "全文阅读", "最新章节目录", "查看更多", "展开全部", "换源", "报错"]
        if blocked.contains(t) { return true }
        if blocked.contains(where: { t.count <= 8 && t.hasPrefix($0) }) { return true }
        return t.count > 60                       // 超长的是广告 / 简介
    }

    /// 章节号：「第 123 章 / 第一百二十三章 / 第12节」→ 123
    static func chapterNumber(inTitle title: String) -> Int? {
        guard let r = title.range(of: #"第\s*([0-9]{1,6}|[零一二三四五六七八九十百千万两]{1,10})\s*[章节回话卷篇集]"#,
                                  options: .regularExpression) else { return nil }
        let raw = String(title[r]).replacingOccurrences(
            of: #"[^0-9零一二三四五六七八九十百千万两]"#, with: "", options: .regularExpression)
        if let n = Int(raw) { return n }
        return chineseNumber(raw)
    }

    /// 中文数字 → 阿拉伯数字（十二 → 12，一百零三 → 103）
    static func chineseNumber(_ s: String) -> Int? {
        let digits: [Character: Int] = ["零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
                                        "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        let units: [Character: Int] = ["十": 10, "百": 100, "千": 1000, "万": 10000]
        // 逐位写法（「一零零」= 100、「零五」= 5）：古籍站点常这么写章号
        if !s.contains(where: { units[$0] != nil }) {
            var value = 0
            for ch in s {
                guard let d = digits[ch] else { return nil }
                value = value * 10 + d
            }
            return value
        }
        var total = 0
        var section = 0
        var current = 0
        for ch in s {
            if let d = digits[ch] {
                current = d
            } else if let u = units[ch] {
                if u == 10000 {
                    section = (section + current) * u
                    total += section
                    section = 0
                } else {
                    section += (current == 0 ? 1 : current) * u
                }
                current = 0
            } else {
                return nil
            }
        }
        return total + section + current
    }

    // MARK: - 组装成 Markdown

    /// 单篇文章 → 一篇笔记
    static func articleNote(title: String, source: URL?, markdown: String,
                            collectedAt: Date = Date()) -> String {
        let head = title.isEmpty ? "# 未命名" : "# \(title)"
        return head + "\n\n" + sourceLine(source, at: collectedAt) + "\n\n" + markdown.trimmed + "\n"
    }

    /// 一本小说 → 一篇笔记（每章一个 `## 标题`）
    static func bookNote(bookTitle: String, source: URL?, chapters: [(title: String, markdown: String)],
                         collectedAt: Date = Date()) -> String {
        var out = "# \(bookTitle.isEmpty ? "未命名" : bookTitle)\n\n"
        out += sourceLine(source, at: collectedAt) + "\n"
        for ch in chapters {
            let body = ch.markdown.trimmed
            guard !body.isEmpty else { continue }
            out += "\n## \(ch.title)\n\n\(body)\n"
        }
        return out
    }

    static func sourceLine(_ source: URL?, at date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        var parts: [String] = []
        if let source { parts.append(_L("来源：<\(source.absoluteString)>", "Source: <\(source.absoluteString)>")) }
        parts.append(_L("采集于 \(f.string(from: date))", "Collected \(f.string(from: date))"))
        return "> " + parts.joined(separator: " · ")
    }
}

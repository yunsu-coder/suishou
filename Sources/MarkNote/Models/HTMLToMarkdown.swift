import Foundation

/// HTML → Markdown（采集「文章 / 小说」用）。
///
/// 目标不是还原网页，而是把**正文**变成干净的 Markdown 笔记：
/// 1) 去掉脚本 / 样式 / 导航 / 页脚等噪声；
/// 2) 「正文容器启发式」挑主体（`<article>` / 常见正文 id-class / 链接密度最低的大块），兜底 `<body>`；
/// 3) 转换标题、段落、列表（可嵌套）、引用、代码块、行内代码、链接、图片、表格、分割线；
/// 4) 解码实体（`&nbsp;` `&#x4E2D;` …）、绝对化相对链接、清理小说站的广告行。
enum HTMLToMarkdown {

    // MARK: - 入口

    /// 整页 HTML → Markdown 正文（baseURL 用于把相对链接/图片补成绝对地址）
    static func convert(_ html: String, baseURL: URL? = nil) -> String {
        let tokens = tokenize(stripNoise(html))
        let body = mainContentTokens(tokens) ?? tokens
        var md = render(body, baseURL: baseURL)
        md = cleanupJunkLines(md)
        return md
    }

    /// 页面标题：`<title>` → og:title → 第一个 `<h1>`
    static func pageTitle(inHTML html: String) -> String? {
        // og:title（最准）与 <title> 都在 <head> 里 —— 先直接从原文取（head 会被当噪声整段跳过）
        if let raw = firstRegexGroup(html, pattern: #"(?is)<meta[^>]+og:title[^>]*content\s*=\s*"([^"]+)""#)
            ?? firstRegexGroup(html, pattern: #"(?is)<meta[^>]+content\s*=\s*"([^"]+)"[^>]*og:title"#) {
            let v = decodeEntities(raw).trimmed
            if !v.isEmpty { return v }
        }
        if let raw = firstRegexGroup(html, pattern: #"(?is)<title[^>]*>(.*?)</title>"#) {
            let v = decodeEntities(raw).trimmed
            if !v.isEmpty { return v }
        }
        let tokens = tokenize(stripNoise(html))
        for (tag, limit) in [("title", 200), ("h1", 120)] {
            var depth = 0
            var text = ""
            for t in tokens {
                if t.kind == .open, t.name == tag { depth += 1; continue }
                if t.kind == .close, t.name == tag {
                    depth -= 1
                    if depth <= 0, !text.isEmpty { return String(decodeEntities(text).trimmed.prefix(limit)) }
                    continue
                }
                if depth > 0, t.kind == .text { text += t.text }
            }
        }
        return nil
    }

    /// 正则取第一个捕获组（页面标题这类「原文里找一下就行」的场景）
    static func firstRegexGroup(_ s: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let m = re.firstMatch(in: s, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    /// 正文纯文本（摘要 / 字数统计）
    static func plainText(_ html: String, baseURL: URL? = nil) -> String {
        let md = convert(html, baseURL: baseURL)
        let stripped = md.replacingOccurrences(of: #"[#>*`\[\]()!_|-]"#, with: " ",
                                               options: .regularExpression)
        return stripped.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmed
    }

    /// 片段纯文本：搜索摘要那种「一小段 HTML」直接去标签 + 解码实体（不做正文提取）
    static func fragmentText(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: #"(?s)<!--.*?-->"#, with: " ", options: .regularExpression)
        // 块级标签 = 断句（留空格）；行内标签 = 原样接上（中文被拆成「硬科幻的 结构」就难看了）
        s = s.replacingOccurrences(of: #"(?is)</?(p|div|br|li|ul|ol|tr|td|th|h[1-6]|section|article|blockquote)[^>]*>"#,
                                   with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?s)<[^>]*>"#, with: "", options: .regularExpression)
        s = decodeEntities(s)
        return s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmed
    }

    /// 字数：汉字按字算，西文按词算（小说「多少字」的常用口径）
    static func wordCount(_ text: String) -> Int {
        var cjk = 0
        var words = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            let v = scalar.value
            let isCJK = (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v)
                || (0xF900...0xFAFF).contains(v) || (0x3040...0x30FF).contains(v)
            if isCJK {
                cjk += 1
                inWord = false
            } else if CharacterSet.alphanumerics.contains(scalar) {
                if !inWord { words += 1; inWord = true }
            } else {
                inWord = false
            }
        }
        return cjk + words
    }

    /// Markdown 里「链接文字」占比：导航页 / 评论页会高得离谱（正文页通常 < 15%）
    static func linkTextRatio(_ markdown: String) -> Double {
        var linkChars = 0
        var stripped = markdown
        if let re = try? NSRegularExpression(pattern: #"\[([^\]]*)\]\([^)]*\)"#) {
            let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
            for m in re.matches(in: markdown, range: range) {
                if let r = Range(m.range(at: 1), in: markdown) { linkChars += markdown[r].count }
            }
            stripped = re.stringByReplacingMatches(in: markdown, range: range, withTemplate: "$1")
        }
        // 分母只算「可读文字」：先把 Markdown 记号与链接地址去掉，别让 URL 稀释比例
        let plain = stripped.replacingOccurrences(of: #"[#>*`~\[\]()!_|\-]"#, with: "",
                                                  options: .regularExpression)
        let total = plain.reduce(0) { $1.isWhitespace ? $0 : $0 + 1 }
        guard total > 0 else { return 0 }
        return min(1, Double(linkChars) / Double(total))
    }

    // MARK: - 分词（够用就好：不引入 DOM 依赖）

    struct Token: Equatable {
        enum Kind { case text, open, close }
        var kind: Kind
        var name: String = ""
        var attrs: String = ""
        var text: String = ""
        /// 原始片段（拼回某个容器的 inner HTML 用）
        var raw: String = ""
    }

    /// 会被整段丢掉（连同内容）的标签
    static let noiseTags: Set<String> = [
        "script", "style", "noscript", "svg", "iframe", "template", "canvas",
        "nav", "footer", "aside", "form", "button", "select", "option", "input",
        "video", "audio", "object", "embed", "map", "head",
    ]

    private static let voidTags: Set<String> = [
        "br", "hr", "img", "input", "meta", "link", "source", "track", "wbr",
        "col", "base", "param", "embed", "area",
    ]

    /// 去注释 / CDATA（保留标签，噪声标签在 tokenize 里整段跳过）
    static func stripNoise(_ html: String) -> String {
        var s = html
        if s.contains("<!--") {
            s = s.replacingOccurrences(of: #"(?s)<!--.*?-->"#, with: " ",
                                       options: .regularExpression)
        }
        if s.contains("<![CDATA[") {
            s = s.replacingOccurrences(of: #"(?s)<!\[CDATA\[.*?\]\]>"#, with: " ",
                                       options: .regularExpression)
        }
        return s
    }

    /// 把 HTML 拆成 token（噪声标签整段跳过；文本 token 已解码实体）
    static func tokenize(_ html: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(html)
        var i = 0
        var text = ""

        func flushText() {
            guard !text.isEmpty else { return }
            tokens.append(Token(kind: .text, text: decodeEntities(text), raw: text))
            text = ""
        }

        while i < chars.count {
            guard chars[i] == "<" else {
                text.append(chars[i]); i += 1; continue
            }
            // <!doctype> / <?xml>：跳过
            if i + 1 < chars.count, chars[i + 1] == "!" || chars[i + 1] == "?" {
                var j = i
                while j < chars.count, chars[j] != ">" { j += 1 }
                i = min(j + 1, chars.count)
                continue
            }
            // 找标签结束（引号里的 > 不算）
            var j = i + 1
            var quote: Character?
            while j < chars.count {
                let c = chars[j]
                if let q = quote {
                    if c == q { quote = nil }
                } else if c == "\"" || c == "'" {
                    quote = c
                } else if c == ">" {
                    break
                }
                j += 1
            }
            guard j < chars.count else {          // 没闭合的 <，当文本
                text.append(chars[i]); i += 1; continue
            }
            let raw = String(chars[i...j])
            let inner = String(chars[(i + 1)..<j])
            let isClose = inner.hasPrefix("/")
            let name = tagName(inner).lowercased()
            let attrs = attrsPart(inner)
            flushText()

            if name.isEmpty {
                i = j + 1
                continue
            }
            if isClose {
                tokens.append(Token(kind: .close, name: name, attrs: attrs, raw: raw))
                i = j + 1
                continue
            }
            let selfClosing = inner.hasSuffix("/") || voidTags.contains(name)
            // 噪声标签：整段跳到配对闭合（不配对的就当自闭合）
            if noiseTags.contains(name), !selfClosing {
                var depth = 1
                var k = j + 1
                var endOfClose: Int? = nil
                while k < chars.count {
                    guard chars[k] == "<" else { k += 1; continue }
                    var m = k + 1
                    var q: Character?
                    while m < chars.count {
                        let c = chars[m]
                        if let qq = q { if c == qq { q = nil } }
                        else if c == "\"" || c == "'" { q = c }
                        else if c == ">" { break }
                        m += 1
                    }
                    guard m < chars.count else { break }
                    let tagInner = String(chars[(k + 1)..<m])
                    let tagName = tagName(tagInner).lowercased()
                    if tagName == name {
                        if tagInner.hasPrefix("/") {
                            depth -= 1
                            if depth == 0 { endOfClose = m + 1; break }
                        } else if !tagInner.hasSuffix("/") {
                            depth += 1
                        }
                    }
                    k = m + 1
                }
                i = endOfClose ?? min(k + 1, chars.count)
                continue
            }
            tokens.append(Token(kind: .open, name: name, attrs: attrs, raw: raw))
            i = j + 1
            if selfClosing { tokens.append(Token(kind: .close, name: name, raw: "")) }
        }
        flushText()
        return tokens
    }

    private static func tagName(_ inner: String) -> String {
        var s = inner
        if s.hasPrefix("/") { s.removeFirst() }
        var out = ""
        for ch in s {
            if ch.isLetter || ch.isNumber || ch == "-" || ch == ":" || ch == "_" { out.append(ch) }
            else { break }
        }
        return out
    }

    private static func attrsPart(_ inner: String) -> String {
        guard let space = inner.firstIndex(where: { $0 == " " || $0 == "\n" || $0 == "\t" }) else { return "" }
        return String(inner[inner.index(after: space)...])
    }

    /// 取属性值（大小写不敏感，单双引号都认）
    static func attribute(_ name: String, in attrs: String) -> String? {
        let pattern = "(?i)\\b" + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*("([^"]*)"|'([^']*)')"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(attrs.startIndex..<attrs.endIndex, in: attrs)
        guard let m = re.firstMatch(in: attrs, range: range) else { return nil }
        for g in [2, 3] {
            if let r = Range(m.range(at: g), in: attrs) { return String(attrs[r]) }
        }
        return nil
    }

    // MARK: - 正文容器启发式

    /// 正文容器：`<article>`/`<main>` 优先；否则在「id/class 像正文」的块里选
    /// **文本多、链接密度低**的那个；都不行就用全部 token（≈ body）。
    static func mainContentTokens(_ tokens: [Token]) -> [Token]? {
        struct Candidate { var score: Double; var tokens: [Token]; var textLen: Int; var isArticle: Bool }
        var candidates: [Candidate] = []
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            guard t.kind == .open, ["article", "main", "div", "section", "td", "body", "dl"].contains(t.name) else {
                i += 1; continue
            }
            guard let end = matchClose(tokens, from: i) else { i += 1; continue }
            let inner = Array(tokens[(i + 1)..<end])
            let isArticle = t.name == "article" || t.name == "main"
            let looksContent = isArticle || isContentLike(t.attrs, name: t.name)
            if looksContent {
                let (textLen, linkLen) = textLengths(inner)
                let score = Double(textLen) - Double(linkLen) * 2.5
                candidates.append(Candidate(score: score, tokens: inner, textLen: textLen, isArticle: isArticle))
            }
            i += 1                       // 允许嵌套候选（取外层不太吃亏）
        }
        let usable = candidates.filter { $0.textLen >= 200 }
        // 链接密度过高的容器（导航/推荐位）宁可不选：分数太低就退回整页（至少不丢正文）
        let healthy = usable.filter { $0.score >= 120 }
        let best = healthy.max { $0.score < $1.score } ?? usable.max { $0.textLen < $1.textLen }
        let article = candidates.filter { $0.isArticle && $0.textLen >= 200 }.max { $0.score < $1.score }
        // article/main 只要不太寒酸就优先（语义最可靠）
        if let article, let best, article.score >= best.score * 0.75 { return article.tokens }
        return best?.tokens
    }

    /// id/class 像正文容器（中英常见命名都认）
    private static func isContentLike(_ attrs: String, name: String) -> Bool {
        let a = attrs.lowercased()
        let keys = ["id", "class", "itemprop", "role"]
        let words = ["article", "artibody", "content", "post", "entry", "chapter", "chaptercontent",
                     "booktext", "read", "text", "main", "story", "body", "novel", "chapter-content",
                     "artical", "detail", "desc", "news", "story", "content_body", "contentbody",
                     "正文", "内容", "章节", "阅读", "article-content", "chapter_content"]
        for key in keys {
            guard let v = attribute(key, in: attrs)?.lowercased() else { continue }
            if words.contains(where: { v.contains($0) }) { return true }
        }
        if a.contains("itemprop=\"articlebody\"") { return true }
        return false
    }

    /// 配对闭合标签的位置（同标签名深度计数）
    private static func matchClose(_ tokens: [Token], from openIndex: Int) -> Int? {
        let name = tokens[openIndex].name
        var depth = 0
        var i = openIndex
        while i < tokens.count {
            let t = tokens[i]
            if t.kind == .open, t.name == name { depth += 1 }
            if t.kind == .close, t.name == name {
                depth -= 1
                if depth == 0 { return i }
            }
            i += 1
        }
        return nil
    }

    /// 容器内（文本长度, 链接文字长度）——链接越长越像导航/目录，而不是正文
    private static func textLengths(_ tokens: [Token]) -> (Int, Int) {
        var text = 0
        var link = 0
        var anchorDepth = 0
        for t in tokens {
            switch t.kind {
            case .open where t.name == "a": anchorDepth += 1
            case .close where t.name == "a": anchorDepth = max(0, anchorDepth - 1)
            case .text:
                let n = t.text.trimmingCharacters(in: .whitespacesAndNewlines).count
                text += n
                if anchorDepth > 0 { link += n }
            default: break
            }
        }
        return (text, link)
    }

    // MARK: - 渲染

    private struct ListCtx { var ordered: Bool; var index: Int }

    private static func render(_ tokens: [Token], baseURL: URL?) -> String {
        var out: [String] = []
        var buf = ""
        var lists: [ListCtx] = []
        var quoteDepth = 0
        var preDepth = 0
        var preBuf = ""
        var preLang: String?
        var headingLevel = 0
        var anchors: [(href: String, start: Int)] = []
        var tableDepth = 0
        var rows: [[String]] = []
        var cells: [String] = []
        var cellBuf: String?

        func inline(_ raw: String) -> String {
            var s = preDepth > 0 ? raw : raw.replacingOccurrences(of: #"\s+"#, with: " ",
                                                                 options: .regularExpression)
            if preDepth == 0 { s = s.trimmed.isEmpty ? " " : s }
            return s
        }

        func decorate(_ text: String, bullet: String?, quote: Int) -> String {
            let prefix = (0..<quote).map { _ in "> " }.joined() + (bullet ?? "")
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            var out: [String] = []
            for line in lines {
                let body = line.trimmingCharacters(in: .whitespaces)
                if body.isEmpty { out.append(""); continue }
                out.append(prefix + body)
            }
            return out.joined(separator: "\n")
        }

        func flush(as bullet: String? = nil) {
            let text = buf.trimmingCharacters(in: .whitespacesAndNewlines)
            buf = ""
            guard !text.isEmpty else { return }
            if headingLevel > 0 {
                let hashes = String(repeating: "#", count: min(max(headingLevel, 1), 6))
                out.append("\(hashes) \(text)")
                return
            }
            out.append(decorate(text, bullet: bullet, quote: quoteDepth))
        }

        func flushParagraph(bullet: String? = nil) {
            let text = buf.trimmingCharacters(in: .whitespacesAndNewlines)
            buf = ""
            guard !text.isEmpty else { return }
            out.append(decorate(text, bullet: bullet, quote: quoteDepth))
        }

        func currentBullet() -> String? {
            guard !lists.isEmpty, headingLevel == 0 else { return nil }
            let depth = lists.count - 1
            let indent = String(repeating: "  ", count: max(0, depth))
            let top = lists[depth]
            return indent + (top.ordered ? "\(top.index). " : "- ")
        }

        for (idx, t) in tokens.enumerated() {
            let next = idx + 1 < tokens.count ? tokens[idx + 1] : nil
            switch t.kind {
            case .text:
                if preDepth > 0 { preBuf += t.text; continue }
                if cellBuf != nil { cellBuf! += t.text; continue }
                buf += inline(t.text)

            case .open:
                let href = attribute("href", in: t.attrs)
                switch t.name {
                case "br":
                    if preDepth > 0 { preBuf += "\n" } else { buf += "\n" }
                case "hr":
                    flushParagraph()
                    out.append("---")
                case "p", "div", "section", "article", "main", "figure", "figcaption",
                     "header", "dl", "dt", "dd", "body":
                    flushParagraph()
                case "blockquote":
                    flushParagraph()
                    quoteDepth += 1
                case "h1", "h2", "h3", "h4", "h5", "h6":
                    flushParagraph()
                    headingLevel = Int(String(t.name.dropFirst())) ?? 1
                case "strong", "b":
                    buf += "**"
                case "em", "i":
                    buf += "*"
                case "del", "s", "strike":
                    buf += "~~"
                case "code":
                    if preDepth > 0 { break }
                    buf += "`"
                case "pre":
                    flushParagraph()
                    preDepth += 1
                    preBuf = ""
                    if let cls = attribute("class", in: t.attrs),
                       let range = cls.range(of: "language-") {
                        preLang = String(cls[range.upperBound...].prefix(20))
                    }
                    if next?.kind == .open, next?.name == "code",
                       let cls = attribute("class", in: next?.attrs ?? ""),
                       let range = cls.range(of: "language-") {
                        preLang = String(cls[range.upperBound...].prefix(20))
                    }
                case "ul", "ol":
                    // 嵌套列表：父项文字先按列表项落地，再进下一层
                    flushParagraph(bullet: currentBullet())
                    let start = Int(attribute("start", in: t.attrs) ?? "1") ?? 1
                    lists.append(ListCtx(ordered: t.name == "ol", index: start))
                case "li":
                    flushParagraph(bullet: currentBullet())
                case "table":
                    flushParagraph()
                    tableDepth += 1
                    rows = []
                    cells = []
                case "tr":
                    cells = []
                case "td", "th":
                    cellBuf = ""
                case "a":
                    anchors.append((href ?? "", buf.count))
                case "img":
                    let src = attribute("src", in: t.attrs) ?? attribute("data-src", in: t.attrs) ?? ""
                    guard !src.isEmpty else { break }
                    let alt = decodeEntities(attribute("alt", in: t.attrs) ?? "").trimmed
                    if let url = absolute(src, base: baseURL) {
                        buf += "![\(alt)](\(url))"
                    }
                default:
                    break
                }

            case .close:
                switch t.name {
                case "p", "div", "section", "article", "main", "figure", "figcaption",
                     "header", "dl", "dt", "dd", "body":
                    flushParagraph()
                case "blockquote":
                    flushParagraph()
                    quoteDepth = max(0, quoteDepth - 1)
                case "h1", "h2", "h3", "h4", "h5", "h6":
                    flush(as: nil)
                    headingLevel = 0
                case "strong", "b":
                    buf += "**"
                case "em", "i":
                    buf += "*"
                case "del", "s", "strike":
                    buf += "~~"
                case "code":
                    if preDepth > 0 { break }
                    buf += "`"
                case "pre":
                    preDepth = max(0, preDepth - 1)
                    // 网页里的代码块常带统一缩进：按最小缩进整体左移，别让每行飘着
                    let body = dedent(preBuf).trimmingCharacters(in: .whitespacesAndNewlines)
                    preBuf = ""
                    if !body.isEmpty {
                        let fence = body.contains("```") ? "````" : "```"
                        let lang = preLang ?? ""
                        out.append("\(fence)\(lang)\n\(body)\n\(fence)")
                    }
                    preLang = nil
                case "ul", "ol":
                    flushParagraph()
                    if !lists.isEmpty { lists.removeLast() }
                case "li":
                    let bullet = currentBullet()
                    flushParagraph(bullet: bullet)
                    if !lists.isEmpty { lists[lists.count - 1].index += 1 }
                case "table":
                    flushParagraph()
                    appendTable(&out, rows: rows)
                    rows = []
                    cells = []
                    tableDepth = max(0, tableDepth - 1)
                case "tr":
                    rows.append(cells)
                    cells = []
                case "td", "th":
                    if let cell = cellBuf {
                        cells.append(cell.replacingOccurrences(of: "\n", with: " ")
                            .replacingOccurrences(of: "|", with: "\\|")
                            .trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    cellBuf = nil
                case "a":
                    guard let anchor = anchors.popLast() else { break }
                    let href = anchor.href
                    guard !href.isEmpty, buf.count >= anchor.start else { break }
                    let start = buf.index(buf.startIndex, offsetBy: anchor.start)
                    let label = String(buf[start...]).trimmingCharacters(in: .whitespaces)
                    guard !label.isEmpty else {
                        if let url = absolute(href, base: baseURL) { buf += "<\(url)>" }
                        break
                    }
                    if let url = absolute(href, base: baseURL) {
                        let head = String(buf[..<start])
                        buf = head + "[\(label)](\(url))"
                    }
                default:
                    break
                }
            }
        }
        flushParagraph()
        if !preBuf.trimmed.isEmpty { out.append("```\n\(preBuf.trimmingCharacters(in: .whitespacesAndNewlines))\n```") }

        // 段落间留空行，去掉多余空行
        var text = out.joined(separator: "\n\n")
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        // 相邻列表项之间不留空行（否则渲染出来是「松散列表」，项距忽大忽小）
        text = text.replacingOccurrences(
            of: #"(?m)^([ \t]*(?:-|\d+\.) .*)\n\n(?=[ \t]*(?:-|\d+\.) )"#,
            with: "$1\n", options: .regularExpression)
        return text.trimmed
    }

    private static func appendTable(_ out: inout [String], rows: [[String]]) {
        let usable = rows.filter { !$0.isEmpty }
        guard usable.count >= 1 else { return }
        let width = usable.map(\.count).max() ?? 0
        guard width >= 1, usable.count >= 2 || width >= 2 else { return }
        func line(_ cells: [String]) -> String {
            var row = cells
            while row.count < width { row.append("") }
            return "| " + row.joined(separator: " | ") + " |"
        }
        var lines = [line(usable[0]), "| " + Array(repeating: "---", count: width).joined(separator: " | ") + " |"]
        for r in usable.dropFirst() { lines.append(line(r)) }
        out.append(lines.joined(separator: "\n"))
    }

    /// 多行文本整体去缩进（取非空行的最小缩进）
    static func dedent(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let indents = lines.filter { !$0.trimmed.isEmpty }.map { line -> Int in
            line.prefix { $0 == " " || $0 == "\t" }.count
        }
        guard let minIndent = indents.min(), minIndent > 0 else { return text }
        return lines.map { line in
            line.trimmed.isEmpty ? "" : String(line.dropFirst(min(minIndent, line.count)))
        }.joined(separator: "\n")
    }

    // MARK: - 清理与工具

    /// 小说站/资讯站常见的广告与导航行（只删**短行**，避免误伤正文）
    static let junkPatterns: [String] = [
        "请收藏本站", "请记住本站", "记住本站", "收藏本站", "本站域名", "本站网址",
        "最快更新", "更新最快", "无弹窗", "全文阅读", "手机阅读", "手机版阅读", "手机用户",
        "加入书签", "加入书架", "投推荐票", "求收藏", "求推荐", "求月票",
        "章节报错", "内容举报", "举报此章", "点击下一页", "翻页", "返回目录", "章节目录",
        "上一章", "下一章", "上一节", "下一节", "笔趣阁", "天才一秒记住",
    ]

    static func cleanupJunkLines(_ md: String) -> String {
        var lines: [String] = []
        for rawLine in md.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let plain = line.replacingOccurrences(of: #"^\s*[#>*\-]+\s*"#, with: "",
                                                  options: .regularExpression).trimmed
            let compact = plain.replacingOccurrences(of: " ", with: "")
            let isShort = compact.count <= 28
            let isJunk = isShort && junkPatterns.contains { compact.contains($0) }
            let isNoise = plain.isEmpty ? false
                : plain.rangeOfCharacter(from: CharacterSet.alphanumerics.union(
                    CharacterSet(charactersIn: "。！？，、；：\"'\u{4E00}"))) == nil
            let isCodeFence = line.hasPrefix("```")
            let isTableRow = line.trimmed.hasPrefix("|")
            if isJunk || (isNoise && !isCodeFence && !isTableRow) { continue }
            lines.append(line)
        }
        var text = lines.joined(separator: "\n")
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return text.trimmed
    }

    /// 相对地址 → 绝对地址
    static func absolute(_ link: String, base: URL?) -> String? {
        let s = link.trimmed
        guard !s.isEmpty, !s.hasPrefix("data:"), !s.hasPrefix("javascript:"), !s.hasPrefix("#") else {
            return nil
        }
        if s.hasPrefix("http://") || s.hasPrefix("https://") { return s }
        guard let base else { return nil }
        return URL(string: s, relativeTo: base)?.absoluteString
    }

    /// HTML 实体解码（命名 + 十进制 + 十六进制）
    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        out.reserveCapacity(s.count)
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            guard chars[i] == "&", let semi = indexOf(";", in: chars, from: i + 1, limit: 12) else {
                out.append(chars[i]); i += 1; continue
            }
            let body = String(chars[(i + 1)..<semi])
            if let decoded = decodeEntityBody(body) {
                out.append(decoded)
                i = semi + 1
            } else {
                out.append(chars[i]); i += 1
            }
        }
        return out
    }

    private static func indexOf(_ target: Character, in chars: [Character], from: Int, limit: Int) -> Int? {
        var i = from
        let end = min(chars.count, from + limit)
        while i < end {
            if chars[i] == target { return i }
            i += 1
        }
        return nil
    }

    private static func decodeEntityBody(_ body: String) -> String? {
        let named: [String: String] = [
            "nbsp": " ", "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
            "ldquo": "“", "rdquo": "”", "lsquo": "‘", "rsquo": "’", "hellip": "…",
            "mdash": "—", "ndash": "–", "middot": "·", "times": "×", "laquo": "«", "raquo": "»",
            "copy": "©", "reg": "®", "trade": "™", "deg": "°", "bull": "•", "prime": "′",
            "ensp": " ", "emsp": "　", "thinsp": " ", "zwj": "", "zwnj": "",
        ]
        if let v = named[body.lowercased()] { return v }
        guard body.hasPrefix("#") else { return nil }
        let digits = String(body.dropFirst())
        let value: UInt32? = digits.lowercased().hasPrefix("x")
            ? UInt32(digits.dropFirst(), radix: 16)
            : UInt32(digits, radix: 10)
        guard let v = value, let scalar = Unicode.Scalar(v) else { return nil }
        return String(Character(scalar))
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

import Foundation

/// 代码着色 token 语义（跨语言统一；具体颜色由 CodePalette 给「最流行的配色」）
enum CodeKind: CaseIterable {
    case keyword, type, string, comment, number, preproc, function, variable, tag, property, constant
}

struct CodeToken {
    let range: NSRange
    let kind: CodeKind
}

/// 代码文件原生语法着色：按语言家族单遍扫描（注释 / 字符串 / 关键字 / 函数 / 标签 / 属性）。
/// 与 Markdown 着色同轨：后台解析 → 主线程只做属性应用（不阻塞输入）。
enum CodeHighlighter {

    // MARK: - 入口

    static func tokenize(_ text: String, language: CodeLanguage, maxChars: Int = 400_000) -> [CodeToken] {
        guard !text.isEmpty, language != .plain, text.utf16.count <= maxChars else { return [] }
        let ns = text as NSString
        let syntax = language.syntax
        var out: [CodeToken] = []
        if syntax.markup {
            scanMarkup(ns, out: &out)
        } else if syntax.css {
            scanCSS(ns, syntax: syntax, out: &out)
        } else {
            scanCode(ns, syntax: syntax, out: &out)
        }
        return out
    }

    /// 兼容旧调用（C 系）：扩展名 → 语言的判定走 CodeLanguage.of(ext:)
    static func tokenize(_ text: String, maxChars: Int = 400_000) -> [CodeToken] {
        tokenize(text, language: .cFamily, maxChars: maxChars)
    }

    // MARK: - 通用扫描（C 系 / Python / Go / JS / TS / Shell / Data / SQL / Ruby / PHP / Lua / ASM / Swift / Rust）

    private static func scanCode(_ ns: NSString, syntax: CodeSyntax, out: inout [CodeToken]) {
        let len = ns.length
        var i = 0
        var lineStart = true

        while i < len {
            let c = ns.character(at: i)
            let wasLineStart = lineStart

            // 换行 / 空白
            if c == 10 || c == 13 { lineStart = true; i += 1; continue }
            if c == 32 || c == 9 { i += 1; continue }
            lineStart = false

            // 行注释
            if match(syntax.lineComments, in: ns, at: i) != nil {
                let e = endOfLine(ns, from: i)
                add(&out, i, e, .comment)
                i = e
                continue
            }
            // 块注释（可跨行）
            if let block = syntax.blockComment, matches(block.open, in: ns, at: i) {
                let e = skipBlock(ns, open: block.open, close: block.close, from: i)
                add(&out, i, e, .comment)
                i = e
                continue
            }
            // 行首指令（C 的 #include、PHP 的 #、CSS/Python 的 @）
            if wasLineStart, c < 128, syntax.lineDirectives.contains(ascii(c)) {
                let e = directiveEnd(ns, at: i, toEndOfLine: c == 35)
                add(&out, i, e, .preproc)
                i = e
                continue
            }
            // 三引号字符串（Python docstring，可跨行）
            if syntax.tripleQuotes, isTripleQuote(ns, at: i) {
                let e = skipTripleQuote(ns, at: i)
                add(&out, i, e, .string)
                i = e
                continue
            }
            // 普通字符串 / 反引号字符串
            if syntax.quotes.contains(ascii(c)) {
                let e = skipString(ns, at: i, allowNewline: false)
                // JSON/YAML 的 "key": → 属性色
                let after = nextNonSpace(ns, from: e)
                let isKey = syntax.keyBeforeColon && after < len && ns.character(at: after) == 58
                add(&out, i, e, isKey ? .property : .string)
                i = e
                continue
            }
            if syntax.backtickString, c == 96 {
                let e = skipString(ns, at: i, allowNewline: true)
                add(&out, i, e, .string)
                i = e
                continue
            }
            // 变量前缀（$VAR / @ivar）
            if c < 128, syntax.variablePrefixes.contains(ascii(c)),
               i + 1 < len, isIdentStart(ns.character(at: i + 1)) {
                var j = i + 1
                while j < len, isIdentBody(ns.character(at: j), allowDash: false) { j += 1 }
                add(&out, i, j, .variable)
                i = j
                continue
            }
            // 数字
            if isDigit(c) || (c == 46 && i + 1 < len && isDigit(ns.character(at: i + 1))) {
                let e = skipNumber(ns, at: i)
                add(&out, i, e, .number)
                i = e
                continue
            }
            // 标识符
            if isIdentStart(c) {
                var j = i + 1
                while j < len, isIdentBody(ns.character(at: j), allowDash: false) { j += 1 }
                let word = ns.substring(with: NSRange(location: i, length: j - i))
                if let kind = classify(word, syntax: syntax, ns: ns, end: j) {
                    add(&out, i, j, kind)
                }
                i = j
                continue
            }
            i += 1
        }
    }

    /// 标识符归类：常量 → 关键字 → 类型 → 函数调用 → `key:` 属性
    private static func classify(_ word: String, syntax: CodeSyntax, ns: NSString, end: Int) -> CodeKind? {
        if syntax.constants.contains(word) { return .constant }
        if syntax.keywords.contains(word) { return .keyword }
        if syntax.types.contains(word) { return .type }
        let next = nextNonSpace(ns, from: end)
        if syntax.functionCalls, next < ns.length, ns.character(at: next) == 40 { return .function }
        if syntax.keyBeforeColon, next < ns.length, ns.character(at: next) == 58 { return .property }
        return nil
    }

    // MARK: - HTML / XML

    private static func scanMarkup(_ ns: NSString, out: inout [CodeToken]) {
        let len = ns.length
        var i = 0
        while i < len {
            let c = ns.character(at: i)
            guard c == 60 else { i += 1; continue }   // '<'

            if matches("<!--", in: ns, at: i) {
                let e = skipBlock(ns, open: "<!--", close: "-->", from: i)
                add(&out, i, e, .comment)
                i = e
                continue
            }
            // <!DOCTYPE …> / <?xml … ?>
            if i + 1 < len, let n = scalar(ns.character(at: i + 1)), n == "!" || n == "?" {
                var j = i + 2
                while j < len, ns.character(at: j) != 62 { j += 1 }
                add(&out, i, min(j + 1, len), .preproc)
                i = min(j + 1, len)
                continue
            }

            // 标签名
            var j = i + 1
            if j < len, ns.character(at: j) == 47 { j += 1 }        // '/'
            let nameStart = j
            while j < len, isTagNameChar(ns.character(at: j)) { j += 1 }
            guard j > nameStart else { i += 1; continue }
            let name = ns.substring(with: NSRange(location: nameStart, length: j - nameStart)).lowercased()
            add(&out, i, j, .tag)

            // 属性区（到 '>' 或 '/>'）
            var selfClosing = false
            while j < len {
                let ch = ns.character(at: j)
                if ch == 62 { j += 1; break }                       // '>'
                if ch == 47, j + 1 < len, ns.character(at: j + 1) == 62 { selfClosing = true; j += 2; break }
                if ch == 34 || ch == 39 {
                    let e = skipString(ns, at: j, allowNewline: true)
                    add(&out, j, e, .string)
                    j = e
                    continue
                }
                if isIdentStart(ch) {
                    var k = j + 1
                    while k < len, isIdentBody(ns.character(at: k), allowDash: true) || ns.character(at: k) == 58 { k += 1 }
                    add(&out, j, k, .property)
                    j = k
                    continue
                }
                j += 1
            }
            let bodyStart = j
            i = j

            // <script> / <style> 内联体：按 JS / CSS 再扫一遍（HTML 里最常见的两种语法）
            guard !selfClosing, name == "script" || name == "style", bodyStart < len else { continue }
            let closeTag = "</" + name
            let search = NSRange(location: bodyStart, length: len - bodyStart)
            let hit = ns.range(of: closeTag, options: .caseInsensitive, range: search)
            guard hit.location != NSNotFound, hit.location > bodyStart else { continue }
            let close = hit.location
            let bodyRange = NSRange(location: bodyStart, length: close - bodyStart)
            let body = ns.substring(with: bodyRange) as NSString
            var sub: [CodeToken] = []
            if name == "script" { scanCode(body, syntax: CodeLanguage.javascript.syntax, out: &sub) }
            else { scanCSS(body, syntax: CodeLanguage.css.syntax, out: &sub) }
            for t in sub {
                out.append(CodeToken(range: NSRange(location: t.range.location + bodyStart, length: t.range.length),
                                     kind: t.kind))
            }
            i = close
        }
    }

    // MARK: - CSS / SCSS / Less

    private static func scanCSS(_ ns: NSString, syntax: CodeSyntax, out: inout [CodeToken]) {
        let len = ns.length
        var i = 0
        var depth = 0
        var statementStart = true         // '{' / ';' / '}' 之后 = 新语句（属性名或嵌套选择器）
        var inValue = false               // 已过 ':' → 后面的标识符是值
        var pending: Int? = nil           // 语句首个标识符（先按属性名，遇到 '{' 改判为选择器）

        while i < len {
            let c = ns.character(at: i)
            if c == 10 || c == 13 || c == 32 || c == 9 { i += 1; continue }

            if matches("/*", in: ns, at: i) {
                let e = skipBlock(ns, open: "/*", close: "*/", from: i)
                add(&out, i, e, .comment)
                i = e
                continue
            }
            if match(["//"], in: ns, at: i) != nil {
                let e = endOfLine(ns, from: i)
                add(&out, i, e, .comment)
                i = e
                continue
            }
            if c == 34 || c == 39 {
                let e = skipString(ns, at: i, allowNewline: false)
                add(&out, i, e, .string)
                i = e
                continue
            }
            if c == 123 {                                                           // {
                // 语句里先出现 '{' → 刚才那个标识符是选择器（@media / SCSS 嵌套也得对）
                if let p = pending, p < out.count {
                    out[p] = CodeToken(range: out[p].range, kind: .tag)
                }
                pending = nil
                depth += 1
                statementStart = true
                inValue = false
                i += 1
                continue
            }
            if c == 125 {                                                           // }
                depth = max(0, depth - 1)
                statementStart = true
                inValue = false
                pending = nil
                i += 1
                continue
            }
            if c == 59 {                                                            // ;
                statementStart = true
                inValue = false
                pending = nil
                i += 1
                continue
            }
            if c == 58 {                                                            // :
                if !statementStart { inValue = true }
                i += 1
                continue
            }
            if c == 64 {                                                            // @media / @import
                let e = directiveEnd(ns, at: i, toEndOfLine: false)
                add(&out, i, e, .preproc)
                i = e
                continue
            }
            // 颜色值 #fff / #ffffff（声明区）
            if c == 35, !statementStart {
                var j = i + 1
                while j < len, isHexDigit(ns.character(at: j)) { j += 1 }
                if j - i - 1 >= 3 { add(&out, i, j, .number); i = j; continue }
            }
            // 选择器：#id / .class（含 @media 里的嵌套选择器）
            if (c == 35 || c == 46), i + 1 < len, isIdentStart(ns.character(at: i + 1)) {
                var j = i + 1
                while j < len, isIdentBody(ns.character(at: j), allowDash: true) { j += 1 }
                add(&out, i, j, .tag)
                statementStart = false
                i = j
                continue
            }
            // 数字（含 px / em / % 单位）
            if isDigit(c) || (c == 46 && i + 1 < len && isDigit(ns.character(at: i + 1))) {
                var j = i
                while j < len, isDigit(ns.character(at: j)) || ns.character(at: j) == 46 { j += 1 }
                while j < len, isIdentBody(ns.character(at: j), allowDash: false) { j += 1 }
                if j < len, ns.character(at: j) == 37 { j += 1 }
                add(&out, i, j, .number)
                i = j
                continue
            }
            // 标识符：属性名 / 选择器 / 值关键字
            if isIdentStart(c) {
                var j = i + 1
                while j < len, isIdentBody(ns.character(at: j), allowDash: true) { j += 1 }
                let word = ns.substring(with: NSRange(location: i, length: j - i))
                if statementStart {
                    add(&out, i, j, .property)
                    pending = out.count - 1
                    statementStart = false
                } else if !inValue {
                    add(&out, i, j, .tag)
                } else if cssValueKeywords.contains(word.lowercased()) {
                    add(&out, i, j, .constant)
                }
                i = j
                continue
            }
            i += 1
        }
    }

    private static let cssValueKeywords: Set<String> = [
        "none", "auto", "inherit", "initial", "unset", "revert", "important", "flex", "grid",
        "block", "inline", "inline-block", "absolute", "relative", "fixed", "sticky", "static",
        "hidden", "visible", "solid", "dashed", "dotted", "bold", "italic", "center", "left",
        "right", "top", "bottom", "middle", "nowrap", "wrap", "pointer", "transparent",
        "currentcolor", "cover", "contain", "repeat", "no-repeat", "border-box", "content-box",
        "screen", "print", "ease", "ease-in", "ease-out", "ease-in-out", "linear", "infinite",
        "both", "forwards", "backwards", "row", "column", "space-between", "space-around",
    ]

    // MARK: - 扫描辅助

    private static func add(_ out: inout [CodeToken], _ start: Int, _ end: Int, _ kind: CodeKind) {
        guard end > start else { return }
        out.append(CodeToken(range: NSRange(location: start, length: end - start), kind: kind))
    }

    private static func endOfLine(_ ns: NSString, from i: Int) -> Int {
        let len = ns.length
        var j = i
        while j < len {
            let c = ns.character(at: j)
            if c == 10 || c == 13 { break }
            j += 1
        }
        return j
    }

    /// 块注释 / 注释段落：从 open 到 close 末（未闭合则到文末）
    private static func skipBlock(_ ns: NSString, open: String, close: String, from i: Int) -> Int {
        let len = ns.length
        let search = NSRange(location: i + (open as NSString).length, length: max(0, len - i - (open as NSString).length))
        let hit = ns.range(of: close, options: .literal, range: search)
        return hit.location == NSNotFound ? len : hit.location + hit.length
    }

    /// 字符串：支持反斜杠转义；allowNewline=false 时遇换行即结束（未闭合不吞下一行）
    private static func skipString(_ ns: NSString, at i: Int, allowNewline: Bool) -> Int {
        let len = ns.length
        let quote = ns.character(at: i)
        var j = i + 1
        while j < len {
            let c = ns.character(at: j)
            if c == 92 { j += 2; continue }
            if c == quote { return j + 1 }
            if !allowNewline, c == 10 || c == 13 { return j }
            j += 1
        }
        return len
    }

    private static func isTripleQuote(_ ns: NSString, at i: Int) -> Bool {
        guard i + 2 < ns.length else { return false }
        let c = ns.character(at: i)
        guard c == 34 || c == 39 else { return false }
        return ns.character(at: i + 1) == c && ns.character(at: i + 2) == c
    }

    private static func skipTripleQuote(_ ns: NSString, at i: Int) -> Int {
        let len = ns.length
        let q = ns.character(at: i)
        var j = i + 3
        while j + 2 < len {
            if ns.character(at: j) == q, ns.character(at: j + 1) == q, ns.character(at: j + 2) == q {
                return j + 3
            }
            j += 1
        }
        return len
    }

    private static func skipNumber(_ ns: NSString, at i: Int) -> Int {
        let len = ns.length
        var j = i
        // 0x / 0b / 0o
        if ns.character(at: i) == 48, i + 1 < len {
            let n = ns.character(at: i + 1) | 0x20
            if n == 120 || n == 98 || n == 111 {
                j = i + 2
                while j < len, isHexDigit(ns.character(at: j)) { j += 1 }
                return j
            }
        }
        var seenDot = false
        while j < len {
            let c = ns.character(at: j)
            if isDigit(c) { j += 1; continue }
            if c == 46, !seenDot, j + 1 < len, isDigit(ns.character(at: j + 1)) { seenDot = true; j += 1; continue }
            if c == 95 || c == 39 { j += 1; continue }                       // 1_000_000 / 1'000
            if c == 101 || c == 69 {                                          // 1e10
                var k = j + 1
                if k < len, ns.character(at: k) == 43 || ns.character(at: k) == 45 { k += 1 }
                if k < len, isDigit(ns.character(at: k)) { j = k; continue }
            }
            break
        }
        return j
    }

    /// 指令（#include / @media / @decorator）：# 到行末；@ 到指令名末尾
    private static func directiveEnd(_ ns: NSString, at i: Int, toEndOfLine: Bool) -> Int {
        if toEndOfLine { return endOfLine(ns, from: i) }
        let len = ns.length
        var j = i + 1
        while j < len, isIdentBody(ns.character(at: j), allowDash: true) || ns.character(at: j) == 46 { j += 1 }
        return j
    }

    private static func match(_ markers: [String], in ns: NSString, at i: Int) -> String? {
        for m in markers where matches(m, in: ns, at: i) { return m }
        return nil
    }

    private static func matches(_ s: String, in ns: NSString, at i: Int) -> Bool {
        let sn = s as NSString
        guard i + sn.length <= ns.length else { return false }
        return ns.compare(sn as String, options: .literal, range: NSRange(location: i, length: sn.length)) == .orderedSame
    }

    private static func nextNonSpace(_ ns: NSString, from i: Int) -> Int {
        var j = i
        while j < ns.length {
            let c = ns.character(at: j)
            if c != 32, c != 9, c != 10, c != 13 { break }
            j += 1
        }
        return j
    }

    private static func scalar(_ c: unichar) -> Character? {
        guard let u = UnicodeScalar(c) else { return nil }
        return Character(u)
    }

    private static func ascii(_ c: unichar) -> Character {
        Character(UnicodeScalar(UInt8(c & 0x7F)))
    }

    private static func isDigit(_ c: unichar) -> Bool { c >= 48 && c <= 57 }
    private static func isHexDigit(_ c: unichar) -> Bool {
        isDigit(c) || (c | 0x20) >= 97 && (c | 0x20) <= 102
    }
    private static func isIdentStart(_ c: unichar) -> Bool {
        (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36 || c > 127
    }
    private static func isIdentBody(_ c: unichar, allowDash: Bool) -> Bool {
        isIdentStart(c) || isDigit(c) || (allowDash && c == 45)
    }
    private static func isTagNameChar(_ c: unichar) -> Bool {
        isIdentBody(c, allowDash: true) || c == 58
    }
}

import Foundation

/// 编辑器内 C/C++（及 C 系语言）语法着色 token —— 与 Markdown 着色同轨：
/// 单遍行扫描（块注释跨行状态机、字符串/字符/预处理优先于关键字）。
enum CodeKind: CaseIterable {
    case keyword, type, string, comment, preproc, number
}

struct CodeToken {
    let range: NSRange
    let kind: CodeKind
}

enum CodeHighlighter {

    static let keywords: Set<String> = [
        "if", "else", "for", "while", "do", "return", "break", "continue", "switch", "case", "default",
        "struct", "class", "enum", "union", "typedef", "static", "const", "constexpr", "volatile",
        "register", "extern", "inline", "public", "private", "protected", "virtual", "override",
        "final", "namespace", "template", "typename", "new", "delete", "this", "nullptr", "true",
        "false", "using", "try", "catch", "throw", "operator", "auto", "signed", "unsigned",
        "sizeof", "goto", "continue", "friend", "explicit", "mutable", "noexcept", "consteval",
        "consteval", "consteval", "decltype", "alignas", "alignof", "static_cast", "dynamic_cast",
        "const_cast", "reinterpret_cast", "and", "or", "not", "xor", "asm", "goto",
    ]

    static let types: Set<String> = [
        "int", "char", "float", "double", "void", "bool", "short", "long", "wchar_t",
        "size_t", "ssize_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t",
        "int8_t", "int16_t", "int32_t", "int64_t", "u8", "u16", "u32", "u64", "i8", "i16", "i32", "i64",
        "string", "vector", "map", "set", "unordered_map", "unordered_set", "pair", "optional",
        "unique_ptr", "shared_ptr", "weak_ptr", "FILE", "fstream", "iostream", "ostream", "istream",
    ]

    /// 单遍行扫描（块注释跨行）；返回不重叠 token（字符串/注释内容不再二次着色）
    static func tokenize(_ text: String, maxChars: Int = 400_000) -> [CodeToken] {
        guard !text.isEmpty, text.count <= maxChars else { return [] }
        let ns = text as NSString
        var out: [CodeToken] = []
        var inBlockComment = false
        var index = 0
        while index < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: index, length: 0))
            let line = ns.substring(with: lineRange)
            scan(line: line, base: lineRange.location, inBlock: &inBlockComment, out: &out)
            index = lineRange.location + lineRange.length
        }
        return out
    }

    private static func scan(line: String, base: Int, inBlock: inout Bool, out: inout [CodeToken]) {
        let ns = line as NSString
        var i = 0
        let len = ns.length
        func add(_ range: NSRange, _ kind: CodeKind) {
            if range.length > 0 { out.append(CodeToken(range: range, kind: kind)) }
        }
        // 预处理：行首（可带空白）#
        let trimmedStart = ns.range(of: "#", options: .anchored, range: NSRange(location: 0, length: len))
        if trimmedStart.location != NSNotFound && trimmedStart.location == 0 {
            add(NSRange(location: base, length: len), .preproc)
            return
        }
        while i < len {
            let c = ns.character(at: i)
            // 块注释（可跨行）
            if inBlock {
                let close = ns.range(of: "*/", options: .literal,
                                     range: NSRange(location: i, length: len - i))
                if close.location != NSNotFound {
                    // 注释范围从本行开头到 */ 末
                    add(NSRange(location: base, length: close.location + 2), .comment)
                    i = close.location + 2
                    inBlock = false
                } else {
                    add(NSRange(location: base, length: len), .comment)
                    return
                }
                continue
            }
            // 行注释
            if c == 0x2F, i + 1 < len, ns.character(at: i + 1) == 0x2F {
                add(NSRange(location: base + i, length: len - i), .comment)
                return
            }
            // 块注释起始
            if c == 0x2F, i + 1 < len, ns.character(at: i + 1) == 0x2A {
                let close = ns.range(of: "*/", options: .literal,
                                        range: NSRange(location: i + 2, length: len - i - 2))
                if close.location != NSNotFound {
                    add(NSRange(location: base + i, length: close.location + 2 - i), .comment)
                    i = close.location + 2
                } else {
                    add(NSRange(location: base + i, length: len - i), .comment)
                    inBlock = true
                    return
                }
                continue
            }
            // 字符串
            if c == 0x22 {  // "
                var j = i + 1
                while j < len {
                    let ch = ns.character(at: j)
                    if ch == 0x5C, j + 1 < len { j += 2; continue }   // 转义
                    if ch == 0x22 { j += 1; break }
                    j += 1
                }
                add(NSRange(location: base + i, length: min(j, len) - i), .string)
                i = min(j, len)
                continue
            }
            // 字符字面量
            if c == 0x27 {  // '
                var j = i + 1
                while j < len {
                    let ch = ns.character(at: j)
                    if ch == 0x5C, j + 1 < len { j += 2; continue }
                    if ch == 0x27 { j += 1; break }
                    j += 1
                }
                add(NSRange(location: base + i, length: min(j, len) - i), .string)
                i = min(j, len)
                continue
            }
            // 数字
            if c >= 0x30 && c <= 0x39 {
                var j = i
                while j < len {
                    let ch = ns.character(at: j)
                    if (ch >= 0x30 && ch <= 0x39) || (ch >= 0x61 && ch <= 0x7A) || (ch >= 0x41 && ch <= 0x5A)
                        || ch == 0x2E || ch == 0x5F || ch == 0x78 || ch == 0x58 || ch == 0x2B || ch == 0x2D {
                        j += 1
                    } else { break }
                }
                add(NSRange(location: base + i, length: j - i), .number)
                i = j
                continue
            }
            // 标识符 / 关键字 / 类型
            if (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || c == 0x5F {
                var j = i
                while j < len {
                    let ch = ns.character(at: j)
                    if (ch >= 0x61 && ch <= 0x7A) || (ch >= 0x41 && ch <= 0x5A)
                        || (ch >= 0x30 && ch <= 0x39) || ch == 0x5F {
                        j += 1
                    } else { break }
                }
                let word = ns.substring(with: NSRange(location: i, length: j - i))
                if keywords.contains(word) {
                    add(NSRange(location: base + i, length: j - i), .keyword)
                } else if types.contains(word) {
                    add(NSRange(location: base + i, length: j - i), .type)
                }
                i = j
                continue
            }
            i += 1
        }
    }
}

/// 括号匹配（VSCode 式）：以光标位置为准，向左右找配对；返回两处字符范围
enum BracketMatcher {
    static let open: Set<Character> = ["(", "[", "{"]
    static let close: Set<Character> = [")", "]", "}"]
    static let pair: [Character: Character] = ["(": ")", "[": "]", "{": "}"]

    /// 光标处可能是「刚输入的开括号」或「站在闭括号上」；返回 (openRange, closeRange)
    static func match(in text: String, at utf16Location: Int) -> (NSRange, NSRange)? {
        let ns = text as NSString
        guard ns.length > 0 else { return nil }
        var loc = min(max(0, utf16Location), ns.length)
        // 光标「贴着」括号也匹配：优先光标处字符；不是括号时回退左侧（刚输入完开括号/闭括号场景）
        var c: Character? = nil
        if loc < ns.length {
            let at = char(at: loc, ns: ns)
            if let a = at, BracketMatcher.open.contains(a) || BracketMatcher.close.contains(a) {
                c = a
            } else if loc > 0, let prev = char(at: loc - 1, ns: ns) {
                c = prev
                loc -= 1
            }
        } else if loc > 0, let prev = char(at: loc - 1, ns: ns) {
            c = prev
            loc -= 1
        }
        guard let ch = c else { return nil }
        if open.contains(ch), let closeCh = pair[ch] {
            guard let closeIdx = findClose(from: loc + 1, openCh: ch, closeCh: closeCh, ns: ns) else { return nil }
            return (NSRange(location: loc, length: 1), NSRange(location: closeIdx, length: 1))
        }
        if close.contains(ch) {
            let openCh = pair.first(where: { $0.value == ch })?.key
            guard let o = openCh else { return nil }
            guard let openIdx = findOpen(from: loc - 1, openCh: o, closeCh: ch, ns: ns) else { return nil }
            return (NSRange(location: openIdx, length: 1), NSRange(location: loc, length: 1))
        }
        return nil
    }

    private static func char(at i: Int, ns: NSString) -> Character? {
        guard i >= 0, i < ns.length else { return nil }
        let s = ns.substring(with: NSRange(location: i, length: 1))
        return s.first
    }

    private static func findClose(from start: Int, openCh: Character, closeCh: Character, ns: NSString) -> Int? {
        var depth = 0
        var i = start
        while i < ns.length {
            if let c = char(at: i, ns: ns) {
                if c == openCh { depth += 1 }
                else if c == closeCh {
                    if depth == 0 { return i }
                    depth -= 1
                }
            }
            i += 1
        }
        return nil
    }

    private static func findOpen(from start: Int, openCh: Character, closeCh: Character, ns: NSString) -> Int? {
        var depth = 0
        var i = start
        while i >= 0 {
            if let c = char(at: i, ns: ns) {
                if c == closeCh { depth += 1 }
                else if c == openCh {
                    if depth == 0 { return i }
                    depth -= 1
                }
            }
            i -= 1
        }
        return nil
    }
}

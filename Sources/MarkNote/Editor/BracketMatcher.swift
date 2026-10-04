import Foundation

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

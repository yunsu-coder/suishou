import Foundation

// MARK: - Markdown 语法着色 token 化器（纯文本解析，可离线后台执行）

enum MDKind: CaseIterable {
    case heading, bold, italic, code, linkLabel, linkURL, quote, listBullet, listNumber, taskBox,
         fenceHead, fenceBody, math, highlight, strikethrough, insert, tableSep, hr

    /// 涂色优先级：数值小者先应用（后被应用者覆盖）—— 字面量优先于标记
    var priority: Int {
        switch self {
        case .code, .fenceHead, .fenceBody, .linkURL: return 0
        case .heading, .quote, .hr, .tableSep: return 4
        case .linkLabel, .math: return 5
        case .listBullet, .listNumber, .taskBox: return 6
        case .bold, .italic, .highlight, .strikethrough, .insert: return 8
        }
    }
}

struct MDToken {
    let range: NSRange
    let kind: MDKind
}

enum MarkdownHighlighter {

    /// 解析整个文档 → tokens（按优先级升序，可后台执行；超大文本跳过着色）
    static func tokenize(_ text: String, maxChars: Int = 500_000) -> [MDToken] {
        guard !text.isEmpty, text.count <= maxChars else { return [] }
        let ns = text as NSString
        var out: [MDToken] = []
        var fence = false
        var index = 0

        while index < ns.length {
            let r = ns.lineRange(for: NSRange(location: index, length: 0))
            let line = ns.substring(with: r)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isFenceMarker = trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")

            if isFenceMarker {
                out.append(MDToken(range: NSRange(location: r.location, length: min(r.length, line.count)), kind: .fenceHead))
                fence.toggle()
            } else if fence {
                out.append(MDToken(range: r, kind: .fenceBody))
            } else {
                classifyLine(ns, line, r, &out)
            }
            index = r.location + r.length
        }
        out.sort { a, b in a.kind.priority < b.kind.priority }
        return out
    }

    /// 行级结构 + 行内标记
    private static func classifyLine(_ ns: NSString, _ line: String, _ lineRange: NSRange, _ out: inout [MDToken]) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var handledRoot = false

        // 标题
        if isHeading(trimmed, lineRange, &out) { handledRoot = true }
        // 引用前缀（连续 ">  "）
        if !handledRoot, trimmed.hasPrefix(">") {
            let qLen = trimmed.prefix(while: { $0 == ">" }).count
            out.append(MDToken(range: NSRange(location: lineRange.location, length: qLen), kind: .quote))
            handledRoot = true
        }
        // 任务列表 / 无序列表 / 有序列表
        if !handledRoot, let m = trimmed.range(of: #"^\s*[-*+]\s+\[[ xX]\]\s"#, options: [.regularExpression]) {
            out.append(MDToken(range: NSRange(location: lineRange.location, length: m.upperBound.utf16Offset(in: trimmed)), kind: .taskBox))
            handledRoot = true
        } else if !handledRoot, let m = trimmed.range(of: #"^\s*[-*+]\s"#, options: [.regularExpression]) {
            out.append(MDToken(range: NSRange(location: lineRange.location, length: m.upperBound.utf16Offset(in: trimmed)), kind: .listBullet))
            handledRoot = true
        } else if !handledRoot, let m = trimmed.range(of: #"^\s*\d+\.\s"#, options: [.regularExpression]) {
            out.append(MDToken(range: NSRange(location: lineRange.location, length: m.upperBound.utf16Offset(in: trimmed)), kind: .listNumber))
            handledRoot = true
        }
        // 分隔线 / 表格分隔行（可叠加在普通行上）
        if hrLine(in: trimmed) {
            out.append(MDToken(range: lineRange, kind: .hr))
        }
        if tableSep(in: trimmed) {
            out.append(MDToken(range: lineRange, kind: .tableSep))
        }

        // 行内标记
        let withoutNewline = line.replacingOccurrences(of: "\n", with: "")
        inlineTokens(in: withoutNewline, baseOffset: lineRange.location, into: &out)
    }

    private static func isHeading(_ trimmed: String, _ lineRange: NSRange, _ out: inout [MDToken]) -> Bool {
        let hashes = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), trimmed.count > hashes,
              trimmed[trimmed.index(trimmed.startIndex, offsetBy: hashes)] == " " else { return false }
        out.append(MDToken(range: lineRange, kind: .heading))
        return true
    }

    private static func hrLine(in t: String) -> Bool {
        guard t.count >= 5 else { return false }
        let core = t.replacingOccurrences(of: " ", with: "")
        if core.hasPrefix("---"), core.allSatisfy({ $0 == "-" }), core.count >= 3 { return true }
        if core.hasPrefix("***"), core.allSatisfy({ $0 == "*" }), core.count >= 3 { return true }
        if core.hasPrefix("___"), core.allSatisfy({ $0 == "_" }), core.count >= 3 { return true }
        return false
    }

    private static func tableSep(in t: String) -> Bool {
        guard t.contains("-") else { return false }
        let core = t.trimmingCharacters(in: CharacterSet(charactersIn: "| \t"))
        guard core.contains("-") else { return false }
        return core.replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "").isEmpty
    }

    /// 行内表达式（顺序由 priority 决定；重叠由符号优先级覆盖）
    private static func inlineTokens(in line: String, baseOffset: Int, into out: inout [MDToken]) {
        regexMatches(#"`[^`\n]+`"#, in: line, base: baseOffset, kind: .code, into: &out)
        regexMatches(#"\[([^\]\n]*)\]\(([^)\s]+)\)"#, in: line, base: baseOffset, kind: .linkLabel, into: &out)
        regexMatches(#"\(([^)\s]+)\)"#, in: line, base: baseOffset, kind: .linkURL, into: &out)
        regexMatches(#"\$\$[^$\n]+\$\$|\$[^$\n]+\$"#, in: line, base: baseOffset, kind: .math, into: &out)
        regexMatches(#"\*\*[^*\n]+\*\*"#, in: line, base: baseOffset, kind: .bold, into: &out)
        regexMatches(#"__[^_\n]+__"#, in: line, base: baseOffset, kind: .bold, into: &out)
        regexMatches(#"(?<!\*)\*[^*\n]{1,200}\*(?!\*)"#, in: line, base: baseOffset, kind: .italic, into: &out)
        regexMatches(#"(?<!_)_[^_\n]{1,200}_(?!_)"#, in: line, base: baseOffset, kind: .italic, into: &out)
        regexMatches(#"==[^=\n]{1,120}=="#, in: line, base: baseOffset, kind: .highlight, into: &out)
        regexMatches(#"~~[^~\n]{1,120}~~"#, in: line, base: baseOffset, kind: .strikethrough, into: &out)
        regexMatches(#"\+\+[^\n]{1,120}\+\+"#, in: line, base: baseOffset, kind: .insert, into: &out)
    }

    private static func regexMatches(_ pattern: String, in line: String, base: Int, kind: MDKind,
                                     into out: inout [MDToken]) {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return }
        let ns = line as NSString
        re.enumerateMatches(in: line, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            let tokenRange = NSRange(location: base + m.range(at: 0).location, length: m.range(at: 0).length)
            guard tokenRange.length > 0, tokenRange.length <= 2000 else { return }
            out.append(MDToken(range: tokenRange, kind: kind))
        }
    }
}

import Foundation

// MARK: - Markdown 语法着色 token 化器（纯文本解析，可离线后台执行）

enum MDKind: CaseIterable {
    case heading, bold, italic, code, linkLabel, linkURL, quote, listBullet, listNumber, taskBox,
         fenceHead, fenceBody, math, highlight, strikethrough, insert, tableSep, hr,
         /// 语法标记本身（#、**、~~、==、``` 等）：主题里用中性色，内容和标记分工
         marker,
         /// Callout / 告警标记（::: tip、!!! warning）
         callout,
         /// 表格竖线 / 结构符号
         tableCell,
         /// 表头单元格内容
         tableHead,
         /// HTML 标签
         htmlTag,
         /// 图片 / 媒体 / 附件（![..](..)、@[..](..)）
         embed,
         /// 键帽 [[⌘S]]
         kbd,
         /// 提及 @名字
         mention,
         /// Emoji :smile:
         emoji,
         /// 状态徽章 [badge:成功]
         badge,
         /// 时间线 - [09-11] 内容
         timeline,
         /// 终端命令块 $ command
         term,
         /// Mermaid 围栏
         mermaid

    /// 涂色优先级：数值小者先应用（后被应用者覆盖）—— 字面量优先于标记
    var priority: Int {
        switch self {
        case .code, .fenceHead, .fenceBody, .linkURL, .callout, .htmlTag, .mermaid: return 0
        case .heading, .quote, .hr, .tableSep, .tableHead: return 4
        case .linkLabel, .math, .embed, .kbd, .mention, .emoji, .badge, .timeline, .term: return 5
        case .listBullet, .listNumber, .taskBox, .tableCell: return 6
        case .bold, .italic, .highlight, .strikethrough, .insert: return 8
        case .marker: return 9
        }
    }
}

struct MDToken {
    let range: NSRange
    let kind: MDKind
    /// 标题级别（1…6），仅 .heading 有意义
    var level: Int = 0
}

enum MarkdownHighlighter {

    /// 解析整个文档 → tokens（按优先级升序，可后台执行；超大文本跳过着色）
    static func tokenize(_ text: String, maxChars: Int = 500_000) -> [MDToken] {
        guard !text.isEmpty, text.count <= maxChars else { return [] }
        let ns = text as NSString
        var out: [MDToken] = []
        var fence = false
        var mathBlock = false
        var index = 0
        var pendingTableHeader = false

        while index < ns.length {
            let r = ns.lineRange(for: NSRange(location: index, length: 0))
            let line = ns.substring(with: r)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let isFenceMarker = trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
            let isMathFence = trimmed == "$$"

            if isMathFence {
                // 多行公式块：$$ … $$
                out.append(MDToken(range: NSRange(location: r.location, length: min(r.length, 2)), kind: .marker))
                if !mathBlock, r.length > 2 {
                    out.append(MDToken(range: NSRange(location: r.location + 2, length: r.length - 2), kind: .math))
                }
                mathBlock.toggle()
            } else if mathBlock {
                out.append(MDToken(range: r, kind: .math))
            } else if isFenceMarker {
                let info = trimmed.drop(while: { $0 == "`" || $0 == "~" })
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                let isMermaid = info.hasPrefix("mermaid")
                out.append(MDToken(range: NSRange(location: r.location, length: min(r.length, line.count)),
                                   kind: isMermaid ? .mermaid : .fenceHead))
                fence.toggle()
            } else if fence {
                out.append(MDToken(range: r, kind: .fenceBody))
            } else {
                // 表格头：本行是表格行、下一行是分隔行
                let nextLine = (index + r.length < ns.length)
                    ? ns.substring(with: ns.lineRange(for: NSRange(location: index + r.length, length: 0)))
                    : ""
                let nextIsSep = tableSep(in: nextLine.trimmingCharacters(in: .whitespacesAndNewlines))
                classifyLine(ns, line, r, isTableHeader: nextIsSep, &out)
            }
            index = r.location + r.length
        }
        out.sort { a, b in a.kind.priority < b.kind.priority }
        return out
    }

    /// 行级结构 + 行内标记
    private static func classifyLine(_ ns: NSString, _ line: String, _ lineRange: NSRange,
                                     isTableHeader: Bool = false, _ out: inout [MDToken]) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        var handledRoot = false

        // 标题
        if isHeading(trimmed, lineRange, &out) { handledRoot = true }
        // 行首缩进：list / quote / task 的标记要落在真实位置（嵌套列表就靠它）
        let indent = leadingIndent(in: line)
        // 引用前缀（连续 ">  "）
        if !handledRoot, trimmed.hasPrefix(">") {
            let qLen = trimmed.prefix(while: { $0 == ">" }).count
            out.append(MDToken(range: NSRange(location: lineRange.location + indent, length: qLen), kind: .quote))
            handledRoot = true
        }
        // 任务列表 / 无序列表 / 有序列表
        if !handledRoot, let m = trimmed.range(of: #"^\s*[-*+]\s+\[[ xX]\]\s"#, options: [.regularExpression]) {
            out.append(MDToken(range: NSRange(location: lineRange.location + indent,
                                              length: m.upperBound.utf16Offset(in: trimmed)), kind: .taskBox))
            handledRoot = true
        } else if !handledRoot, let m = trimmed.range(of: #"^\s*[-*+]\s+\[[^\]]+\]\s"#, options: [.regularExpression]) {
            // 时间线：- [09-11] 内容（不是任务框）
            let prefixLen = m.upperBound.utf16Offset(in: trimmed)
            out.append(MDToken(range: NSRange(location: lineRange.location + indent, length: 2), kind: .marker))
            out.append(MDToken(range: NSRange(location: lineRange.location + indent + 2, length: prefixLen - 3),
                               kind: .timeline))
            handledRoot = true
        } else if !handledRoot, let m = trimmed.range(of: #"^\s*[-*+]\s"#, options: [.regularExpression]) {
            out.append(MDToken(range: NSRange(location: lineRange.location + indent,
                                              length: m.upperBound.utf16Offset(in: trimmed)), kind: .listBullet))
            handledRoot = true
        } else if !handledRoot, let m = trimmed.range(of: #"^\s*\d+(?:\.\d+)*\.?\s"#, options: [.regularExpression]) {
            // 有序列表（含多级编号）：`1. ` / `1.1 ` / `1.1.1 ` / `1.1.1. `（编号与空格一起上色）
            out.append(MDToken(range: NSRange(location: lineRange.location + indent,
                                              length: m.upperBound.utf16Offset(in: trimmed)), kind: .listNumber))
            handledRoot = true
        }
        // 终端命令块：行首 "$ "
        if !handledRoot, let m = trimmed.range(of: #"^\$\s"#, options: [.regularExpression]) {
            out.append(MDToken(range: NSRange(location: lineRange.location + indent,
                                              length: max(2, lineRange.length - indent)),
                               kind: .term))
        }
        // 分隔线 / 表格分隔行（可叠加在普通行上）
        if hrLine(in: trimmed) {
            out.append(MDToken(range: lineRange, kind: .hr))
        }
        if tableSep(in: trimmed) {
            out.append(MDToken(range: lineRange, kind: .tableSep))
        }
        // 表格：竖线标成结构符；表头单元格加粗着色
        if trimmed.contains("|"), !tableSep(in: trimmed) {
            let nsLine = line as NSString
            for i in 0..<nsLine.length where nsLine.character(at: i) == 124 {   // "|"
                out.append(MDToken(range: NSRange(location: lineRange.location + i, length: 1),
                                   kind: .tableCell))
            }
            if isTableHeader {
                for cell in tableCells(in: line, base: lineRange.location) where cell.length > 0 {
                    out.append(MDToken(range: cell, kind: .tableHead))
                }
            }
        }
        // HTML 标签
        regexMatches(#"</?[A-Za-z][A-Za-z0-9-]*(\s[^<>]*)?/?>"#, in: line, base: lineRange.location,
                     kind: .htmlTag, into: &out)
        // Callout / 告警整行（::: tip / !!! warning）
        if trimmed.hasPrefix(":::") || trimmed.hasPrefix("!!!") {
            let lead = leadingIndent(in: line)
            out.append(MDToken(range: NSRange(location: lineRange.location + lead,
                                              length: max(3, lineRange.length - lead)),
                               kind: .callout))
        }

        // 行内标记
        let withoutNewline = line.replacingOccurrences(of: "\n", with: "")
        inlineTokens(in: withoutNewline, baseOffset: lineRange.location, into: &out)
    }

    /// 表格单元格内容（去掉竖线与空白）
    private static func tableCells(in line: String, base: Int) -> [NSRange] {
        var ranges: [NSRange] = []
        let ns = line as NSString
        var start = 0
        for i in 0...ns.length where i == ns.length || ns.character(at: i) == 124 {
            let seg = NSRange(location: start, length: i - start)
            if seg.length > 0 {
                let text = ns.substring(with: seg)
                let blanks: Set<Character> = [" ", "\t", "\n", "\r"]
                let lead = text.prefix(while: { blanks.contains($0) }).utf16.count
                let trail = text.reversed().prefix(while: { blanks.contains($0) }).count
                let len = seg.length - lead - trail
                if len > 0 {
                    ranges.append(NSRange(location: base + seg.location + lead, length: len))
                }
            }
            start = i + 1
        }
        return ranges
    }

    private static func isHeading(_ trimmed: String, _ lineRange: NSRange, _ out: inout [MDToken]) -> Bool {
        let hashes = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), trimmed.count > hashes,
              trimmed[trimmed.index(trimmed.startIndex, offsetBy: hashes)] == " " else { return false }
        // 标记（#）与内容分开：标记走中性色，内容按级别取 --md-h1/h2/h3
        let leadingSpaces = leadingIndent(in: trimmed)
        let markerRange = NSRange(location: lineRange.location + leadingSpaces, length: hashes)
        out.append(MDToken(range: markerRange, kind: .marker))
        // 内容范围以「去空白后的行」为准，并跳过 # 后的空格，避免把行尾换行也染上标题色
        let restText = String(trimmed.dropFirst(hashes))
        let leadSpaces = restText.prefix(while: { $0 == " " || $0 == "\t" }).utf16.count
        let rest = NSRange(location: markerRange.location + hashes + leadSpaces,
                           length: max(0, restText.utf16.count - leadSpaces))
        if rest.length > 0 {
            out.append(MDToken(range: rest, kind: .heading, level: hashes))
        }
        return true
    }

    /// 行首缩进（空格 / Tab）的 UTF-16 长度。
    /// 注意：不能用 `lineRange.length - trimmed.count` —— 行范围含行尾换行，会算多一格。
    private static func leadingIndent(in text: String) -> Int {
        text.prefix(while: { $0 == " " || $0 == "\t" }).utf16.count
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
        guard t.contains("-"), t.contains("|") || !t.contains(" ") else { return false }
        // 支持 | --- | :--: | 以及 --- | --- 两种写法：每个单元格必须是 :?-{3,}:?
        let cells = t.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let core = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":")).trimmingCharacters(in: .whitespacesAndNewlines)
            return core.count >= 3 && core.allSatisfy { $0 == "-" }
        }
    }

    /// 行内表达式（顺序由 priority 决定；重叠由符号优先级覆盖）
    private static func inlineTokens(in line: String, baseOffset: Int, into out: inout [MDToken]) {
        regexMatches(#"`[^`\n]+`"#, in: line, base: baseOffset, kind: .code, into: &out)
        // 图片 / 视频 / 音频 / 附件：![说明](路径)、@[附件](路径) —— 标记 / 说明 / 路径 分别上色
        linkLikeMatches(#"([!@])\[([^\]\n]*)\]\(([^)\s]+)\)"#, in: line, base: baseOffset,
                        labelKind: .embed, into: &out)
        // 普通链接：[说明](路径)
        linkLikeMatches(#"\[([^\]\n]*)\]\(([^)\s]+)\)"#, in: line, base: baseOffset,
                        labelKind: .linkLabel, into: &out, singleGroup: true)
        // 键帽 [[⌘S]]、提及 @名字、Emoji :smile:、徽章 [badge:成功]
        delimitedMatches(#"\[\[[^\[\]\n]{1,24}\]\]"#, in: line, base: baseOffset, kind: .kbd,
                         markerLength: 2, into: &out)
        regexMatches(#"(^|[\s(])@[\p{L}\p{N}_\-]{1,24}"#, in: line, base: baseOffset, kind: .mention, into: &out)
        regexMatches(#":[a-zA-Z0-9_+\-]{2,32}:"#, in: line, base: baseOffset, kind: .emoji, into: &out)
        delimitedMatches(#"\[badge:[^\]\n]{1,40}\]"#, in: line, base: baseOffset, kind: .badge,
                         markerLength: 1, into: &out)
        // 脚注引用 / TOC / 锚点：安静处理（走标记色，避免抢镜）
        regexMatches(#"\[\^[^\]\n]{1,32}\]"#, in: line, base: baseOffset, kind: .marker, into: &out)
        regexMatches(#"\[TOC\]"#, in: line, base: baseOffset, kind: .marker, into: &out)
        regexMatches(#"\{#[A-Za-z0-9_\-\u4e00-\u9fa5]{1,40}\}"#, in: line, base: baseOffset, kind: .marker, into: &out)
        regexMatches(#"(?<!~)~[^~\n]{1,80}~(?!~)"#, in: line, base: baseOffset, kind: .marker, into: &out)
        regexMatches(#"(?<!\^)\^[^\^\n]{1,80}\^(?!\^)"#, in: line, base: baseOffset, kind: .marker, into: &out)
        regexMatches(#"\$\$[^$\n]+\$\$|\$[^$\n]+\$"#, in: line, base: baseOffset, kind: .math, into: &out)
        delimitedMatches(#"\*\*[^*\n]+\*\*"#, in: line, base: baseOffset, kind: .bold, markerLength: 2, into: &out)
        delimitedMatches(#"__[^_\n]+__"#, in: line, base: baseOffset, kind: .bold, markerLength: 2, into: &out)
        delimitedMatches(#"(?<!\*)\*[^*\n]{1,200}\*(?!\*)"#, in: line, base: baseOffset, kind: .italic,
                         markerLength: 1, into: &out)
        delimitedMatches(#"(?<!_)_[^_\n]{1,200}_(?!_)"#, in: line, base: baseOffset, kind: .italic,
                         markerLength: 1, into: &out)
        delimitedMatches(#"==[^=\n]{1,120}=="#, in: line, base: baseOffset, kind: .highlight,
                         markerLength: 2, into: &out)
        delimitedMatches(#"~~[^~\n]{1,120}~~"#, in: line, base: baseOffset, kind: .strikethrough,
                         markerLength: 2, into: &out)
        delimitedMatches(#"\+\+[^\n]{1,120}\+\+"#, in: line, base: baseOffset, kind: .insert,
                         markerLength: 2, into: &out)
    }

    /// 前后带定界符的行内语法：把定界符单独标成 .marker，内容按各自类型上色。
    private static func delimitedMatches(_ pattern: String, in line: String, base: Int, kind: MDKind,
                                         markerLength: Int, into out: inout [MDToken]) {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return }
        let ns = line as NSString
        re.enumerateMatches(in: line, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            let full = m.range(at: 0)
            guard full.length > markerLength * 2, full.length <= 2000 else { return }
            let loc = base + full.location
            out.append(MDToken(range: NSRange(location: loc, length: markerLength), kind: .marker))
            out.append(MDToken(range: NSRange(location: loc + markerLength,
                                              length: full.length - markerLength * 2), kind: kind))
            out.append(MDToken(range: NSRange(location: loc + full.length - markerLength,
                                              length: markerLength), kind: .marker))
        }
    }

    /// 链接类语法：标记（[]() 与可选的 ! / @）走中性色，说明文字与路径分别上色。
    /// - `singleGroup = true`：模式为 `[说明](路径)`（普通链接）
    /// - `singleGroup = false`：模式为 `([!@]?)[说明](路径)`（图片 / 附件，前缀标记单列一组）
    private static func linkLikeMatches(_ pattern: String, in line: String, base: Int,
                                        labelKind: MDKind, into out: inout [MDToken],
                                        singleGroup: Bool = false) {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return }
        let ns = line as NSString
        re.enumerateMatches(in: line, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            let full = m.range(at: 0)
            guard full.length > 2 else { return }
            let labelGroup = singleGroup ? 1 : 2
            let urlGroup = singleGroup ? 2 : 3
            guard m.range(at: labelGroup).location != NSNotFound,
                  m.range(at: urlGroup).location != NSNotFound else { return }
            func mark(_ r: NSRange) {
                guard r.location != NSNotFound, r.length > 0 else { return }
                out.append(MDToken(range: NSRange(location: base + r.location, length: r.length), kind: .marker))
            }
            let label = m.range(at: labelGroup)
            let url = m.range(at: urlGroup)
            if !singleGroup {
                mark(m.range(at: 1))                                            // ! 或 @
            }
            mark(NSRange(location: full.location, length: label.location - full.location))          // [ 前缀
            out.append(MDToken(range: NSRange(location: base + label.location, length: label.length),
                               kind: labelKind))
            mark(NSRange(location: label.location + label.length,
                         length: url.location - (label.location + label.length)))                   // ]( 中缀
            out.append(MDToken(range: NSRange(location: base + url.location, length: url.length),
                               kind: .linkURL))
            let tail = full.location + full.length - (url.location + url.length)
            mark(NSRange(location: url.location + url.length, length: tail))                        // ) 收尾
        }
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

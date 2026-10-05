import AppKit
import UniformTypeIdentifiers

/// 增强版 NSTextView：粘贴/拖拽图片时自动存入文件附件目录，
/// 并在光标处插入 Markdown 图片引用（否则回退默认文本粘贴行为）。
final class MarkdownTextView: NSTextView {

    /// (data, ext) -> 相对文件目录的引用路径；nil 表示保存失败
    var imageHandler: ((Data, String) -> String?)?
    /// 任意文件 (data, fileName) -> 引用路径；用于非图片文件的粘贴/拖拽
    var attachmentHandler: ((Data, String) -> String?)?
    /// Finder 文件 URL -> 相对引用路径；直接复制文件入库（视频/大文件不读进内存）
    var fileURLHandler: ((URL) -> String?)?
    /// AI 快捷操作（翻译/改写/润色）：右键菜单回调（action, 选中文本）
    var aiMenuHandler: ((AIQuickAction, String) -> Void)?
    /// 当前文件扩展名（⌘/ 注释符号选择；EditorView 注入）
    var fileExtension = ""

    private static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff"]

    /// 右键菜单：有选区时追加「AI 翻译 / 改写 / 润色」
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let sel = selectedRange()
        guard sel.length > 0, let handler = aiMenuHandler else { return menu }
        menu.addItem(.separator())
        for action in AIQuickAction.allCases {
            let item = NSMenuItem(title: "AI \(action.title)", action: #selector(runAIMenuItem(_:)), keyEquivalent: "")
            item.target = self
            item.tag = AIQuickAction.allCases.firstIndex(of: action) ?? 0
            item.image = NSImage(systemSymbolName: action.icon, accessibilityDescription: nil)
            menu.addItem(item)
        }
        return menu
    }

    @objc private func runAIMenuItem(_ sender: NSMenuItem) {
        guard let handler = aiMenuHandler else { return }
        let actions = AIQuickAction.allCases
        guard actions.indices.contains(sender.tag) else { return }
        let sel = selectedRange()
        guard sel.length > 0 else { return }
        let text = (string as NSString).substring(with: sel)
        handler(actions[sender.tag], text)
    }

    // MARK: - 模板填空模式（Tab 在字段间跳，输入即替换）

    /// 当前填空进度（nil = 不在填空）
    private(set) var fillPlan: TemplateFillPlan?

    /// 开始填空：选中第一个字段
    func startFill(_ plan: TemplateFillPlan) {
        guard plan.isActive else { return }
        fillPlan = plan
        if let range = fillPlan?.current {
            setSelectedRange(NSRange(location: range.lowerBound, length: range.count))
            scrollRangeToVisible(NSRange(location: range.lowerBound, length: range.count))
        }
    }

    /// 结束填空（保留已填内容；清除多余字段标记不需要，因为字段本身不写进文本）
    func exitFill() {
        guard fillPlan != nil else { return }
        fillPlan = nil
        // 落到最后一个字段之后，方便继续写正文
        let caret = selectedRange().location + selectedRange().length
        setSelectedRange(NSRange(location: min(caret, (string as NSString).length), length: 0))
        window?.makeFirstResponder(self)
    }

    /// 文本变了 → 同步字段范围（打字会让后面的字段整体平移）
    override func didChangeText() {
        super.didChangeText()
        guard var plan = fillPlan else { return }
        let edited = textStorage?.editedRange ?? NSRange(location: 0, length: 0)
        let delta = textStorage?.changeInLength ?? 0
        guard delta != 0 || edited.length > 0 else { return }
        let oldStart = edited.location
        let oldLength = max(0, edited.length - delta)
        plan.applyEdit(editedRange: oldStart..<(oldStart + oldLength), delta: delta)
        fillPlan = plan
    }

    /// 编辑器焦点下 ⌘⌫/⌘⌦（两种退格）也会被文本系统截胡 —— 拦截并转给"删除文件"命令
    override func keyDown(with event: NSEvent) {
        // 模板填空模式：Tab / ⇧Tab 在字段间跳，Esc 结束（见 Models/NoteTemplate.swift）
        if fillPlan?.isActive == true {
            if event.keyCode == 48 {                        // Tab
                let delta = event.modifierFlags.contains(.shift) ? -1 : 1
                if let next = fillPlan?.advance(delta) {
                    setSelectedRange(NSRange(location: next.lowerBound, length: next.count))
                } else {
                    exitFill()                              // 走到头：收工，光标落在字段后
                }
                return
            }
            if event.keyCode == 53 { exitFill(); return }    // Esc
        }
        if event.modifierFlags.contains(.command),
           event.keyCode == 51 || event.keyCode == 117 {   // 51=Delete(⌫) 117=DeleteForward(⌦)
            NotificationCenter.default.post(name: .deleteNoteRequested, object: nil)
            return
        }
        // REQ-ED-04 多行缩进/反缩进：⌘] / ⌘/ 缩进、⌘[ / ⇧⌘/ 反缩进（多选或当前行；含德式布局下 ⌘]/⌘[ 难按的键盘）
        if event.modifierFlags.contains(.command) {
            let ch = event.charactersIgnoringModifiers
            if ch == "/" && event.modifierFlags.contains(.shift) { blockIndent(indent: false); return }
            if ch == "]" || ch == "/" { blockIndent(indent: true); return }
            if ch == "[" { blockIndent(indent: false); return }
        }
        // 代码文件：成对补全 + 选区包围 + 类型越过（VS Code 式）
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           Workspace.isEditorText(fileExtension),
           !MarkdownEditorView.isMarkdownExt(fileExtension),
           let ch = event.charactersIgnoringModifiers {
            // 有选区 → 直接用符号包住（输入 " 也能把选中的词包成字符串）
            if selectedRange().length > 0, let wrapped = Self.wrapped(
                (string as NSString).substring(with: selectedRange()), with: ch) {
                insertText(wrapped, replacementRange: selectedRange())
                return
            }
            if selectedRange().length == 0 {
                let next = characterAfterCaret()
                // ① 下一个字符就是我要敲的符号 → 直接越过（VS Code type-over）：
                //    这样 `{|}` 里再敲 `}`、`{|}` 前敲 `{` 都不会多出一个符号
                if Self.isPairSymbol(ch), Self.stealsNext(next: next, typing: ch) {
                    setSelectedRange(NSRange(location: selectedRange().location + 1, length: 0))
                    return
                }
                if ch == "(" || ch == "[" || ch == "{" {
                    // ② 后面紧跟单词字符 / 正处在注释或字符串里 → 不补对，只输入本身
                    if Self.shouldAutoClose(next: next), !isInCommentOrString() {
                        if autoCloseBracket(ch) { return }
                    }
                } else if ch == ")" || ch == "]" || ch == "}" {
                    if skipOverCloser(ch) { return }
                } else if ch == "\"" || ch == "'" || ch == "`" {
                    if !isInCommentOrString(), autoCloseQuote(ch) { return }
                }
            }
        }
        // ⌘⇧\ 跳到匹配括号
        if event.modifierFlags.contains(.command), event.modifierFlags.contains(.shift),
           event.keyCode == 42 {   // kVK_ANSI_Backslash
            jumpMatchingBracket()
            return
        }
        // ⌘L 选中当前行
        if event.modifierFlags.contains(.command),
           event.modifierFlags.intersection([.shift, .option, .control]).isEmpty,
           event.keyCode == 37 {   // kVK_ANSI_L
            selectCurrentLine()
            return
        }
        // ⌃⌥↑ / ⌃⌥↓ 整行上移 / 下移（VSCode Alt+↑↓）
        if event.modifierFlags.contains(.control), event.modifierFlags.contains(.option),
           event.modifierFlags.intersection([.command, .shift]).isEmpty {
            if event.keyCode == 126 { moveLine(-1); return }   // ↑
            if event.keyCode == 125 { moveLine(1); return }    // ↓
        }
        // ⌘/ 注释 / 取消注释（VSCode 式）：按当前文件扩展名选注释符号 —— 受「代码智能编辑」开关控制
        if !FeatureModules.isEnabled(FeatureModules.editorCodeSmart) { return super.keyDown(with: event) }
        // ⌘/ 注释 / 取消注释（VSCode 式）：按当前文件扩展名选注释符号
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "/" {
            toggleComment()
            return
        }
        // HTML 标签自动闭合：**只对标记语言**（HTML/XML/Vue/Svelte… 以及 Markdown）
        // 生效。以前没判类型，于是 C++ 里 `#include <iostream>` 被补成 `</iostream>`（用户实测）。
        if Self.allowsTagAutoClose(fileExtension: fileExtension),
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           event.charactersIgnoringModifiers == ">" {
            if htmlGreaterCloses() { return }
        }
        super.keyDown(with: event)
    }


    /// 光标后面的一个字符（用于 type-over / 补全判定）
    private func characterAfterCaret() -> String? {
        let ns = string as NSString
        let loc = selectedRange().location
        guard loc < ns.length else { return nil }
        return ns.substring(with: NSRange(location: loc, length: 1))
    }

    /// 光标是否落在注释或字符串 token 里（用同一套代码着色器判断，避免在注释里乱补引号/括号）
    private func isInCommentOrString() -> Bool {
        let text = string
        guard text.utf16.count <= 100_000 else { return false }   // 大文件不为一次按键做全量解析
        let loc = selectedRange().location
        guard loc > 0 else { return false }
        let kind = CodeHighlighter.tokenize(text, language: CodeLanguage.of(ext: fileExtension))
            .last { loc > $0.range.location && loc <= $0.range.location + $0.range.length }?.kind
        return kind == .comment || kind == .string
    }

    /// 输入开括号：补闭合符并把光标移到中间
    private func autoCloseBracket(_ ch: String) -> Bool {
        let close: String
        switch ch {
        case "(": close = ")"
        case "[": close = "]"
        case "{": close = "}"
        default: return false
        }
        let sel = selectedRange()
        insertText(ch + close, replacementRange: sel)
        setSelectedRange(NSRange(location: sel.location + 1, length: 0))
        return true
    }

    /// 当前文件的缩进单位（C/C++/Python/Go/JS… 4；HTML/CSS/JSON/Markdown 2）
    private var indentUnit: Int { MarkdownEditorView.indentUnit(for: fileExtension) }

    /// Tab 该插几个空格：光标已在行首空白里 → 对齐到下一个制表位（VS Code 手感）
    static func tabInsertion(beforeCaret prefix: String, unit: Int) -> String {
        let u = max(1, unit)
        if prefix.allSatisfy({ $0 == " " }) {
            let pad = u - (prefix.count % u)
            return String(repeating: " ", count: pad)
        }
        return String(repeating: " ", count: u)
    }

    /// 选中一段文本后输入包围符号 → 用符号包住选区（VS Code 行为）
    static func wrapped(_ selection: String, with ch: String) -> String? {
        let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`"]
        guard let close = pairs[ch] else { return nil }
        return ch + selection + close
    }


    /// 成对符号（括号 + 引号）
    static func isPairSymbol(_ ch: String) -> Bool {
        ["(", ")", "[", "]", "{", "}", "\"", "'", "`"].contains(ch)
    }

    /// 下一个字符正好是我要输入的符号 → 越过，不再插入（VS Code type-over）
    static func stealsNext(next: String?, typing ch: String) -> Bool {
        guard let next, !next.isEmpty else { return false }
        return next == ch
    }

    /// 下一位是单词字符（字母/数字/下划线）→ 不自动补对（VS Code 规则）；
    /// 行尾或空白/符号则补。
    static func shouldAutoClose(next: String?) -> Bool {
        guard let next, let c = next.first else { return true }
        return !(c.isLetter || c.isNumber || c == "_")
    }

    /// 行注释续行：在 `//` 注释里回车 → 新行继续 `// `；空注释行不再续
    static func commentContinuation(beforeCaretInLine: String, indent: String, marker: String) -> String? {
        let trimmed = beforeCaretInLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(marker) else { return nil }
        let body = trimmed.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }
        return "\n" + indent + marker + " "
    }

    /// 光标两侧恰好是一对空符号 → 一次退格删掉整对
    static func isDeletablePair(prev: String, next: String) -> Bool {
        let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`"]
        return pairs[prev] == next
    }

    /// 退格：空对（() [] {} "" ''）一次删两个字符
    override func deleteBackward(_ sender: Any?) {
        if FeatureModules.isEnabled(FeatureModules.editorCodeSmart),
           Workspace.isEditorText(fileExtension),
           selectedRange().length == 0 {
            let ns = string as NSString
            let loc = selectedRange().location
            if loc >= 1, loc < ns.length {
                let prev = ns.substring(with: NSRange(location: loc - 1, length: 1))
                let next = ns.substring(with: NSRange(location: loc, length: 1))
                if Self.isDeletablePair(prev: prev, next: next) {
                    let range = NSRange(location: loc - 1, length: 2)
                    if shouldChangeText(in: range, replacementString: "") {
                        textStorage?.replaceCharacters(in: range, with: "")
                        didChangeText()
                        setSelectedRange(NSRange(location: loc - 1, length: 0))
                    }
                    return
                }
            }
        }
        super.deleteBackward(sender)
    }

    /// 输入闭括号时若下一字符即同款闭合符 → 跳过（VSCode type-over）
    private func skipOverCloser(_ ch: String) -> Bool {
        let sel = selectedRange()
        let ns = string as NSString
        guard sel.length == 0, sel.location < ns.length else { return false }
        let next = ns.substring(with: NSRange(location: sel.location, length: 1))
        guard next == ch else { return false }
        setSelectedRange(NSRange(location: sel.location + 1, length: 0))
        return true
    }

    /// 引号补全 / 越过：`"` `'` `` ` `` 都按 VS Code 的行为来
    /// - 下一字符就是同款引号 → 直接越过（不重复输入）
    /// - 下一字符是字母/数字 → 不补（在词中间不该乱插）
    /// - 其余情况 → 补一个闭合引号并把光标放中间
    private func autoCloseQuote(_ ch: String) -> Bool {
        let ns = string as NSString
        let sel = selectedRange()
        if sel.location < ns.length {
            let next = ns.substring(with: NSRange(location: sel.location, length: 1))
            if next == ch {                                  // 越过
                setSelectedRange(NSRange(location: sel.location + 1, length: 0))
                return true
            }
            if next.rangeOfCharacter(from: .alphanumerics) != nil { return false }
        }
        insertText(ch + ch, replacementRange: sel)
        setSelectedRange(NSRange(location: sel.location + 1, length: 0))
        return true
    }

    /// 代码智能换行：返回应插入的文本（含换行+缩进+括号补全）；nil = 走默认
    /// 智能换行的纯逻辑（可单测）：before/after = 光标前/后的**行内**文本
    /// - `{| }` / `[|]` / `(|)`（自动补全出来的空对）→ 中间起新行并按单位缩进，闭合符留在原处
    /// - 行尾是开括号且**没有**配对的闭合符 → 缩进一级，并补上闭合符
    /// - 整行只有闭括号 → 回退缩进
    /// - Python 冒号块 / 括号续行 → 缩进一级
    /// - 其余 → 沿用当前行缩进（普通换行）
    static func smartNewline(before: String, after: String, indent: String, unit: Int, isPython: Bool) -> String {
        let pad = String(repeating: " ", count: max(1, unit))
        let beforeCore = before.trimmingCharacters(in: .whitespaces)
        let afterCore = after.trimmingCharacters(in: .whitespaces)

        // 1) 自动补全的空对：光标夹在中间 → 只缩进，绝不再补一个闭合符
        let pairs: [(open: Character, close: Character)] = [("{", "}"), ("[", "]"), ("(", ")")]
        if let p = pairs.first(where: { beforeCore.last == $0.open && afterCore.first == $0.close }) {
            _ = p
            return "\n" + indent + pad
        }
        // 2) 整行只剩闭括号 → 回退一级
        if beforeCore.isEmpty, let c = afterCore.first, ")]}".contains(c) {
            return "\n" + (indent.count >= pad.count ? String(indent.dropLast(pad.count)) : "")
        }
        // 3) 行尾是开括号（没有自动补全的闭合符）→ 缩进一级；`{` 再补一行闭合符
        if let last = beforeCore.last, "{[(".contains(last) {
            if last == "{" { return "\n" + indent + pad + "\n" + indent + "}" }
            return "\n" + indent + pad
        }
        // 4) Python 的冒号块
        if isPython, beforeCore.hasSuffix(":") { return "\n" + indent + pad }
        // 5) 普通换行：沿用当前缩进
        return "\n" + indent
    }

    /// 行注释续行：只在"真的是注释"时触发，且只认行注释符（// # 等）
    private func commentContinuationAtCaret() -> String? {
        let marker = Workspace.lineComment(for: fileExtension)
        guard !marker.isEmpty, !marker.hasPrefix("<!--") else { return nil }
        let ns = string as NSString
        let sel = selectedRange()
        let lineRange = ns.lineRange(for: NSRange(location: min(sel.location, ns.length), length: 0))
        let line = ns.substring(with: lineRange).replacingOccurrences(of: "\n", with: "")
        let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        let caretInLine = max(0, min(sel.location - lineRange.location, (line as NSString).length))
        let before = (line as NSString).substring(to: caretInLine)
        return Self.commentContinuation(beforeCaretInLine: before, indent: indent, marker: marker)
    }

    private func codeSmarterNewline() -> String? {
        let ns = string as NSString
        let sel = selectedRange()
        guard ns.length > 0 else { return nil }
        let lineRange = ns.lineRange(for: NSRange(location: min(sel.location, ns.length), length: 0))
        let line = ns.substring(with: lineRange).replacingOccurrences(of: "\n", with: "")
        let caretInLine = max(0, min(sel.location - lineRange.location, (line as NSString).length))
        let before = (line as NSString).substring(to: caretInLine)
        let after = (line as NSString).substring(from: caretInLine)
        let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        if after.isEmpty, before.trimmingCharacters(in: .whitespaces).isEmpty {
            return "\n" + indent          // 空行照原缩进
        }
        return Self.smartNewline(before: before, after: after, indent: indent,
                                 unit: MarkdownEditorView.indentUnit(for: fileExtension),
                                 isPython: fileExtension.lowercased() == "py")
    }

    /// ⌘⇧\：跳转到匹配括号（光标可停在任一端）
    private func jumpMatchingBracket() {
        let sel = selectedRange()
        guard let (a, b) = BracketMatcher.match(in: string, at: sel.location) else { return }
        // 若光标紧贴 open 端 → 跳到 close 端，反之亦然
        let atOpen = abs(sel.location - a.location) <= 1
        let target = atOpen ? b : a
        setSelectedRange(NSRange(location: target.location, length: 0))
    }

    /// ⌘L：选中当前行（含换行）
    private func selectCurrentLine() {
        let ns = string as NSString
        guard ns.length > 0 else { return }
        let r = ns.lineRange(for: NSRange(location: min(selectedRange().location, ns.length), length: 0))
        setSelectedRange(r)
    }

    /// ⌃⌥↑/↓：整行上移 / 下移（与相邻行交换；多行选中整块移动）
    private func moveLine(_ delta: Int) {
        let ns = string as NSString
        let sel = selectedRange()
        guard ns.length > 0 else { return }
        let cur = ns.lineRange(for: NSRange(location: min(sel.location, ns.length), length: 0))
        let other: NSRange
        if delta < 0 {
            guard cur.location > 0 else { return }
            other = ns.lineRange(for: NSRange(location: cur.location - 1, length: 0))
        } else {
            guard cur.location + cur.length < ns.length else { return }
            other = ns.lineRange(for: NSRange(location: cur.location + cur.length, length: 0))
        }
        let start = min(cur.location, other.location)
        let end = max(cur.location + cur.length, other.location + other.length)
        let mid = ns.substring(with: NSRange(location: start, length: end - start))
        let curText = ns.substring(with: cur)
        let otherText = ns.substring(with: other)
        let swapped = delta < 0 ? (otherText + curText) : (curText + otherText)
        guard swapped == mid else {
            // 行尾处理：统一换行对换（mid 可能缺尾换行）
            let fixCur = curText.hasSuffix("\n") ? curText : curText + "\n"
            let fixOther = otherText.hasSuffix("\n") ? otherText : otherText + "\n"
            let fixed = delta < 0 ? (fixOther + fixCur) : (fixCur + fixOther)
            insertText(fixed, replacementRange: NSRange(location: start, length: end - start))
            let movedStart = delta < 0 ? start : (start + curText.count)
            setSelectedRange(NSRange(location: movedStart, length: curText.count))
            return
        }
        insertText(swapped, replacementRange: NSRange(location: start, length: end - start))
        let movedStart = delta < 0 ? start : (start + curText.count)
        setSelectedRange(NSRange(location: movedStart, length: curText.count))
    }

    /// ⌘/ 注释切换：当前行（选中多行则整块）；扩展名决定注释符号（Workspace.lineComment）
    private func toggleComment() {
        let ns = string as NSString
        let sel = selectedRange()
        guard ns.length > 0 else { return }
        let symbol = Workspace.lineComment(for: fileExtension)
        let lines = ns.lineRange(for: NSRange(location: min(sel.location, ns.length), length: 0))
        var start = lines.location
        var end = lines.location + lines.length
        // 若是选中的整块，扩至多行
        if sel.length > 0 {
            let range = ns.lineRange(for: sel)
            start = range.location
            end = range.location + range.length
        }
        var block = ns.substring(with: NSRange(location: start, length: end - start))
        let linesArr = block.components(separatedBy: "\n").dropLast()
        let prefix = symbol + " "
        let allCommented = linesArr.allSatisfy { $0.trimmingCharacters(in: CharacterSet.whitespaces).hasPrefix(symbol) }
        var newLines: [String] = []
        for line in linesArr {
            if allCommented {
                if let range = line.range(of: symbol) { newLines.append(String(line[range.upperBound...]).trimmingCharacters(in: CharacterSet.whitespaces)) }
                else { newLines.append(line) }
            } else {
                // 保留行内前导缩进 → 注释符在其后
                let indent = line.prefix(while: { $0 == " " || $0 == "\t" })
                let body = String(line.dropFirst(indent.count))
                newLines.append(String(indent) + prefix.trimmingCharacters(in: CharacterSet.whitespaces) + " " + body)
            }
        }
        let result = newLines.joined(separator: "\n") + "\n"
        insertText(result, replacementRange: NSRange(location: start, length: end - start))
    }

    /// 打 `>` 时：仅在“正在输入一个未闭合的开标签”时补 `</tag>`。
    /// 判定要点：最近一段 `<name`（无 `>`、不包含换行、不以 `/` 开头）且参数名合法；
    /// 若用户本就在写 `</span>`（前趋含 `/`）→ 放过；后文已有同名闭合 → 放过。
    /// `<tag>` 自动补 `</tag>` 的适用范围：标记语言 + Markdown；
    /// C/C++/Python/Java… 里 `<` `>` 是运算符或模板/包含符，绝不能当标签补。
    static func allowsTagAutoClose(fileExtension: String) -> Bool {
        let ext = fileExtension.lowercased()
        if ext.isEmpty { return false }
        if MarkdownEditorView.isMarkdownExt(ext) { return true }
        return CodeLanguage.of(ext: ext) == .markup
    }

    private func htmlGreaterCloses() -> Bool {
        let ns = string as NSString
        let caret = selectedRange().location
        guard caret > 0 else { return false }
        let before = ns.substring(with: NSRange(location: 0, length: caret))
        guard let lt = before.lastIndex(of: "<") else { return false }
        let seg = String(before[lt...]).dropFirst() // `<` 之后的原文片段
        // 片段必须干净：无 `>` `<` 换行，不以 `/` 开头（闭合标签不补）
        if seg.isEmpty || seg.contains(where: { $0 == ">" || $0 == "<" || $0 == "\n" }) { return false }
        if seg.hasPrefix("/") { return false }
        let name = seg
        guard name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return false }
        // HTML void 元素（无闭合标签）：<br>/<img>/<hr>/<input>... → 不补
        let voidElements: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input",
                                         "link", "meta", "param", "source", "track", "wbr"]
        if voidElements.contains(name.lowercased()) { return false }
        // 后文已有同名闭合 → 不补（防重复）
        let after = ns.substring(with: NSRange(location: caret, length: ns.length - caret))
        if after.lowercased().contains("</\(name.lowercased())") { return false }
        // 补 `>` + `</name>`，光标回到 `>` 之后
        insertText("></\(name)>", replacementRange: selectedRange())
        setSelectedRange(NSRange(location: caret + 1, length: 0))
        return true
    }

    // MARK: - 手感：列表延续 / 缩进 / Tab

    override func insertNewline(_ sender: Any?) {
        // 代码文件里在行注释中回车 → 自动续上注释符（VS Code 行为）
        if FeatureModules.isEnabled(FeatureModules.editorCodeSmart),
           Workspace.isEditorText(fileExtension), !MarkdownEditorView.isMarkdownExt(fileExtension),
           isInCommentOrString(),
           let cont = commentContinuationAtCaret() {
            insertText(cont, replacementRange: selectedRange())
            return
        }
        // 代码文件（C/C++ 等）：VSCode 智能换行 —— 括号自动补/缩进延续/回退
        if Workspace.isEditorText(fileExtension), !MarkdownEditorView.isMarkdownExt(fileExtension),
           let replacement = codeSmarterNewline() {
            insertText(replacement, replacementRange: selectedRange())
            return
        }
        // 文档：回车 = 纯换行（列表/引用延续见下方通用逻辑）
        super.insertNewline(sender)
    }

    /// Tab = 2 空格（轻量缩进）；多行选中 = 整块缩进（VS Code 手感）
    override func insertTab(_ sender: Any?) {
        let text = string as NSString
        let sel = selectedRange()
        if sel.length > 0,
           text.range(of: "\n", options: [], range: NSRange(location: sel.location, length: sel.length)) != nil {
            blockIndent(indent: true)
            return
        }
        // 行首空白里 → 对齐到下一个制表位；否则插入一个缩进单位（C/C++/Python 4、HTML/CSS 2）
        let lineStart = text.lineRange(for: NSRange(location: min(sel.location, text.length), length: 0)).location
        let prefix = text.substring(with: NSRange(location: lineStart,
                                                  length: max(0, sel.location - lineStart)))
        insertText(Self.tabInsertion(beforeCaret: prefix, unit: indentUnit), replacementRange: sel)
    }

    /// ⇧⇥：反缩进（多选或当前行）
    override func insertBacktab(_ sender: Any?) {
        blockIndent(indent: false)
    }

    /// 整块缩进/反缩进（REQ-ED-04）：选区覆盖的行（无选区 = 当前行）；注册标准 shouldChangeText 保持撤销链
    func blockIndent(indent: Bool) {
        let text = string as NSString
        let sel = selectedRange()
        guard text.length > 0, sel.location <= text.length else { return }
        // 有选区 → 操作选区所覆盖的行；无选区 → 当前光标行（缩进/反缩进均适用，勿用光标行覆盖选区）
        let caretLine = text.lineRange(for: NSRange(location: sel.location, length: 0))
        let range = sel.length > 0 ? NSRange(location: sel.location, length: sel.length) : caretLine
        let full = text.lineRange(for: NSRange(location: range.location, length: min(range.length, text.length - range.location)))
        guard full.length > 0 else { return }
        let sub = text.substring(with: full)
        let transformed = Self.transformIndent(sub, indent: indent, unit: indentUnit)
        guard transformed != sub else { return }
        guard shouldChangeText(in: full, replacementString: transformed) else { return }
        textStorage?.replaceCharacters(in: full, with: transformed)
        didChangeText()
        // 选区映射：按行重算（NSTextView 选区为 UTF-16 语义 → 行长度用 NSString.length 对齐）
        let lines = sub.components(separatedBy: "\n")
        let tLines = transformed.components(separatedBy: "\n")
        func mapOffset(_ rel: Int) -> Int {
            var acc = 0, tAcc = 0
            for i in 0..<lines.count {
                let lineLen = (lines[i] as NSString).length
                if rel <= acc + lineLen {
                    // 锚定内容而非行首：行内偏移随该行变换量平移（缩进 +2 跟上、反缩进 -2 回退），
                    // 钳制到变换后行边界内（反缩进不得越过行首、不得超出行尾）
                    let tLen = (tLines[i] as NSString).length
                    let p = tAcc + (rel - acc) + (tLen - lineLen)
                    return max(tAcc, min(p, tAcc + tLen))
                }
                acc += lineLen + 1
                tAcc += (tLines[i] as NSString).length + 1
            }
            return tAcc
        }
        let selRel = sel.location - full.location
        let subLen = (sub as NSString).length
        let start = mapOffset(min(selRel, subLen))
        let end = mapOffset(min(selRel + sel.length, subLen))
        setSelectedRange(NSRange(location: full.location + start, length: max(0, end - start)))
    }

    /// 每行加一个缩进单位 / 卸一个 Tab 或最多一个单位（行尾独立变换，行首空串不参与缩进）
    static func transformIndent(_ text: String, indent: Bool, unit: Int = 2) -> String {
        let pad = String(repeating: " ", count: max(1, unit))
        if text.isEmpty { return text }
        let lines = text.components(separatedBy: "\n")
        var out = [String]()
        out.reserveCapacity(lines.count)
        for (i, line) in lines.enumerated() {
            if indent {
                // 末尾空行不缩进（避免在下一行前插冗余空格）
                if line.isEmpty && i == lines.count - 1 && lines.count > 1 {
                    out.append(line)
                } else {
                    out.append(pad + line)
                }
            } else {
                if line.hasPrefix("\t") {
                    out.append(String(line.dropFirst()))
                } else {
                    let ws = line.prefix(while: { $0 == " " })
                    out.append(String(line.dropFirst(min(max(1, unit), ws.count))))
                }
            }
        }
        return out.joined(separator: "\n")
    }

    // MARK: - 粘贴

    override func paste(_ sender: Any?) {
        // Finder 复制的文件（图片/视频/PDF…）→ 直接复制入库，保留原始文件
        if let url = Self.fileURL(in: NSPasteboard.general), handleFileURL(url) {
            return
        }
        if let (data, ext) = Self.extractBitmap(NSPasteboard.general), handleImage(data, ext: ext) {
            return
        }
        // 非图片文件（Finder 复制 PDF/zip 等）→ 作为附件插入
        if let (data, name) = Self.extractFile(NSPasteboard.general), handleAttachment(data, name: name) {
            return
        }
        super.paste(sender)
    }

    // MARK: - 拖拽

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if Self.fileURL(in: sender.draggingPasteboard) != nil {
            return .copy
        }
        if Self.dragImageData(sender) != nil {
            return .copy
        }
        // 应用内素材拖拽携带的是「短引用文本」：走文本落点插入，不再重复入库
        if Self.dragAssetRef(sender) != nil {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // 素材库拖进来的短引用：插到**落点**（拖到哪儿放哪儿），而不是光标处
        if let ref = Self.dragAssetRef(sender) {
            let point = convert(sender.draggingLocation, from: nil)
            let idx = characterIndexForInsertion(at: point)
            let length = (string as NSString).length
            let range = NSRange(location: min(max(0, idx), length), length: 0)
            let text = Self.blockAligned(ref, in: string, at: range.location)
            if shouldChangeText(in: range, replacementString: text) {
                replaceCharacters(in: range, with: text)
                didChangeText()
            }
            return true
        }
        // Finder 文件（图片/视频/音频/文档）→ 入库并插入对应语法
        if let url = Self.fileURL(in: sender.draggingPasteboard), handleFileURL(url) {
            return true
        }
        if let (data, ext) = Self.dragImageData(sender), handleImage(data, ext: ext) {
            return true
        }
        if let (data, name) = Self.dragFileData(sender), handleAttachment(data, name: name) {
            return true
        }
        return super.performDragOperation(sender)
    }

    // MARK: - 核心

    /// 保存图片并在光标处插入引用；返回是否已被消费
    private func handleImage(_ data: Data, ext: String?) -> Bool {
        guard let handler = imageHandler else { return false }
        var finalData = data
        var finalExt = ext ?? "png"
        // PNG/TIFF 类位图统一转 PNG（WebView 里渲染稳定；Finder 拖的 jpg 保持原样）
        if ext == "tiff" || ext == "bmp" {
            guard let img = NSImage(data: data),
                  let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return false }
            finalData = png
            finalExt = "png"
        }
        guard let rel = handler(finalData, finalExt) else { return false }
        insertAssetReference(AssetSyntax.reference(name: "图片.\(finalExt)", path: rel))
        return true
    }

    /// 任意文件附件：保存 + 插入链接；返回是否被消费
    private func handleAttachment(_ data: Data, name: String) -> Bool {
        guard let handler = attachmentHandler else { return false }
        guard let rel = handler(data, name) else { return false }
        insertAssetReference(AssetSyntax.reference(name: name, path: rel))
        return true
    }

    /// Finder 文件 URL：复制入库 + 按类型插入语法；返回是否被消费（不读内存，大文件友好）
    private func handleFileURL(_ url: URL) -> Bool {
        guard let handler = fileURLHandler, let rel = handler(url) else { return false }
        insertAssetReference(AssetSyntax.reference(name: url.lastPathComponent, path: rel))
        return true
    }

    /// 在光标处插入素材引用（块级自动独占整行）
    @discardableResult
    private func insertAssetReference(_ ref: String) -> Bool {
        let range = selectedRange()
        let text = Self.blockAligned(ref, in: string, at: range.location)
        guard shouldChangeText(in: range, replacementString: text) else { return false }
        replaceCharacters(in: range, with: text)
        didChangeText()
        return true
    }

    // MARK: - 粘贴板解析

    /// 粘贴板 / 拖拽中的文件 URL（Finder 文件），取第一个
    private static func fileURL(in pb: NSPasteboard) -> URL? {
        guard let urls = pb.readObjects(forClasses: [NSURL.self],
                                        options: [.urlReadingFileURLsOnly: true]) as? [URL] else { return nil }
        return urls.first
    }

    private static func extractBitmap(_ pb: NSPasteboard) -> (Data, String?)? {
        // 1. Finder 复制文件（含图片文件）
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true, .urlReadingContentsConformToTypes: [UTType.image.identifier]]) as? [URL],
           let u = urls.first,
           imageExts.contains(u.pathExtension.lowercased()),
           let d = try? Data(contentsOf: u) {
            return (d, u.pathExtension.lowercased())
        }
        // 2. 位图数据（截图复制通常是 PNG/TIFF）
        for (pt, ext) in [(NSPasteboard.PasteboardType.png, "png"), (NSPasteboard.PasteboardType.tiff, "tiff")] {
            if let d = pb.data(forType: pt) {
                return (d, ext)
            }
        }
        // 3. 现代 provider 型剪贴板（浏览器/聊天工具复制的图片，按 item 逐个探测）
        if let items = pb.pasteboardItems {
            for item in items {
                for (pt, ext) in [(NSPasteboard.PasteboardType.png, "png"), (NSPasteboard.PasteboardType.tiff, "tiff")] {
                    if let d = item.data(forType: pt) {
                        return (d, ext)
                    }
                }
            }
        }
        // 4. NSImage 兜底（任何位图 → 统一转 PNG）
        if let img = NSImage(pasteboard: pb),
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return (png, "png")
        }
        return nil
    }

    /// 块级素材引用（`<video>` / `<audio>` / 附件卡 `@[…]`）应当独占整行：插入位置缺换行时自动补齐，
    /// 避免两个视频 / 卡片挤在同一行。行内语法（图片等）原样返回。
    static func blockAligned(_ text: String, in string: String, at index: Int) -> String {
        let isBlock = text.hasPrefix("<video") || text.hasPrefix("<audio") || text.hasPrefix("@[")
        guard isBlock else { return text }
        let ns = string as NSString
        let loc = min(max(0, index), ns.length)
        var out = text
        // 文首 / 文末分别视为「已是行首」「尚无字符」：文末要补换行，让块级元素闭合成整行
        let before = loc > 0 ? ns.substring(with: NSRange(location: loc - 1, length: 1)) : "\n"
        if before != "\n" { out = "\n" + out }
        let after = loc < ns.length ? ns.substring(with: NSRange(location: loc, length: 1)) : ""
        if after != "\n" { out += "\n" }
        return out
    }

    /// 素材拖拽识别（素材面板「插入 / 复制 / 拖拽」三处共用同一套写法，按素材类型分派）：
    /// · 图片 `![名称](img/xxx.png)`；附件卡 `@[名称](path)`；
    /// · 视频 / 音频内嵌播放器 `<video src="…" controls></video>`、`<audio …></audio>`。
    /// 只认这几种「素材引用」形态，避免把普通文本拖拽也吃掉。
    private static func dragAssetRef(_ sender: NSDraggingInfo) -> String? {
        let pb = sender.draggingPasteboard
        guard let text = pb.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty else { return nil }
        if (text.hasPrefix("![") || text.hasPrefix("@[")),
           text.hasSuffix(")"), text.contains("](") {
            return text
        }
        if text.hasPrefix("<video"), text.hasSuffix("</video>") { return text }
        if text.hasPrefix("<audio"), text.hasSuffix("</audio>") { return text }
        return nil
    }

    private static func dragImageData(_ sender: NSDraggingInfo) -> (Data, String?)? {
        let pb = sender.draggingPasteboard
        if let (data, ext) = extractBitmap(pb) {
            return (data, ext)
        }
        // 应用内拖拽（WebView/资源库等）以 NSImage 形式
        if let img = NSImage(pasteboard: pb),
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return (png, "png")
        }
        return nil
    }

    /// 任意文件（非图片）拖拽提取：返回 (data, fileName)
    private static func dragFileData(_ sender: NSDraggingInfo) -> (Data, String)? {
        let pb = sender.draggingPasteboard
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              let u = urls.first,
              let d = try? Data(contentsOf: u) else { return nil }
        return (d, u.lastPathComponent)
    }

    /// 粘贴板上的文件 URL（非图片）提取
    private static func extractFile(_ pb: NSPasteboard) -> (Data, String)? {
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              let u = urls.first,
              !imageExts.contains(u.pathExtension.lowercased()),
              let d = try? Data(contentsOf: u) else { return nil }
        return (d, u.lastPathComponent)
    }
}

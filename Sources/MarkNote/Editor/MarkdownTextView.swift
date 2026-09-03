import AppKit
import UniformTypeIdentifiers

/// 增强版 NSTextView：粘贴/拖拽图片时自动存入文件附件目录，
/// 并在光标处插入 Markdown 图片引用（否则回退默认文本粘贴行为）。
final class MarkdownTextView: NSTextView {

    /// (data, ext) -> 相对文件目录的引用路径；nil 表示保存失败
    var imageHandler: ((Data, String) -> String?)?
    /// 任意文件 (data, fileName) -> 引用路径；用于非图片文件的粘贴/拖拽
    var attachmentHandler: ((Data, String) -> String?)?
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

    /// 编辑器焦点下 ⌘⌫/⌘⌦（两种退格）也会被文本系统截胡 —— 拦截并转给"删除文件"命令
    override func keyDown(with event: NSEvent) {
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
        // 括号自动成对（VSCode 式）：码文件输入 ( [ { → 自动补闭合符并回退光标
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           Workspace.isEditorText(fileExtension),
           !MarkdownEditorView.isMarkdownExt(fileExtension),
           selectedRange().length == 0,
           let ch = event.charactersIgnoringModifiers {
            if ch == "(" || ch == "[" || ch == "{" {
                if autoCloseBracket(ch) { return }
            } else if ch == ")" || ch == "]" || ch == "}" {
                // 光标已停在闭合符上 → 直接越过（不重复输入）
                if skipOverCloser(ch) { return }
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
        // HTML 自动闭合（仅保留此项；成对补全已按用户决策删除）：无修饰键纯输入 ">"
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           event.charactersIgnoringModifiers == ">" {
            if htmlGreaterCloses() { return }
        }
        super.keyDown(with: event)
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

    /// 代码智能换行：返回应插入的文本（含换行+缩进+括号补全）；nil = 走默认
    private func codeSmarterNewline() -> String? {
        let ns = string as NSString
        let sel = selectedRange()
        guard ns.length > 0 else { return nil }
        let lineRange = ns.lineRange(for: NSRange(location: min(sel.location, ns.length), length: 0))
        let line = ns.substring(with: lineRange).replacingOccurrences(of: "\n", with: "")
        let ws = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        let core = String(line.dropFirst(ws.count)).trimmingCharacters(in: .whitespaces)
        let indentUnit = MarkdownEditorView.indentUnit(for: fileExtension)
        let unit = String(repeating: " ", count: indentUnit)   // 统一空格缩进（tabStops 同规）
        if core.isEmpty {
            return "\n" + ws
        }
        if core.hasSuffix("{") {
            // VSCode：{ 回车 → {⏎    ⏎}  光标落在中间行
            let middle = "\n" + ws + unit
            return middle + "\n" + ws + "}"
        }
        if core.hasPrefix("}") || core == "}" {
            return "\n" + (ws.count >= unit.count ? String(ws.dropLast(unit.count)) : ws)
        }
        return "\n" + ws
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
        insertText("  ", replacementRange: selectedRange())
    }

    /// ⇧⇥：反缩进（多选或当前行）
    override func insertBacktab(_ sender: Any?) {
        blockIndent(indent: false)
    }

    /// 整块缩进/反缩进（REQ-ED-04）：选区覆盖的行（无选区 = 当前行）；注册标准 shouldChangeText 保持撤销链
    func blockIndent(indent: Bool) {
        SelLog.log("BLOCKINDENT enter indent=\(indent) sel=\(selectedRange())")
        let text = string as NSString
        let sel = selectedRange()
        guard text.length > 0, sel.location <= text.length else { return }
        // 有选区 → 操作选区所覆盖的行；无选区 → 当前光标行（缩进/反缩进均适用，勿用光标行覆盖选区）
        let caretLine = text.lineRange(for: NSRange(location: sel.location, length: 0))
        let range = sel.length > 0 ? NSRange(location: sel.location, length: sel.length) : caretLine
        let full = text.lineRange(for: NSRange(location: range.location, length: min(range.length, text.length - range.location)))
        guard full.length > 0 else { return }
        let sub = text.substring(with: full)
        let transformed = Self.transformIndent(sub, indent: indent)
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
        SelLog.log("BLOCKINDENT done → mapped=\(selectedRange())")
    }

    /// 每行 +2 空格 / 卸一个 Tab 或最多 2 个空格（行尾独立变换，行开头的空串不参与缩进）
    static func transformIndent(_ text: String, indent: Bool) -> String {
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
                    out.append("  " + line)
                }
            } else {
                if line.hasPrefix("\t") {
                    out.append(String(line.dropFirst()))
                } else {
                    let ws = line.prefix(while: { $0 == " " })
                    out.append(String(line.dropFirst(min(2, ws.count))))
                }
            }
        }
        return out.joined(separator: "\n")
    }

    // MARK: - 粘贴

    override func paste(_ sender: Any?) {
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
        if Self.dragImageData(sender) != nil {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
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
        insertText(_L("![图片](\(rel))", "![Image](\(rel))"), replacementRange: selectedRange())
        return true
    }

    /// 任意文件附件：保存 + 插入链接；返回是否被消费
    private func handleAttachment(_ data: Data, name: String) -> Bool {
        guard let handler = attachmentHandler else { return false }
        guard let rel = handler(data, name) else { return false }
        insertText("[\(name)](\(rel))", replacementRange: selectedRange())
        return true
    }

    // MARK: - 粘贴板解析

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

import SwiftUI
import AppKit
import UniformTypeIdentifiers


/// 【临时诊断】选区/编辑路径日志 —— 修完即删
enum SelLog {
    static func log(_ s: String) {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MarkNote/sel.log")
        let line = "\(Date()) | " + s + "\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(line.data(using: .utf8)!)
            try? h.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

/// Markdown 源码编辑器 —— 纯 AppKit NSTextView 封装：
/// 行号标尺、等宽字体、原生撤销、智能替换关闭。
/// 性能优先：不经过 SwiftUI TextEditor，直接控制文本系统。
struct MarkdownEditorView: NSViewRepresentable {

    let text: String
    let fontSize: CGFloat
    /// 字体家族（mono=系统等宽 SF Mono；menlo/monaco/pingfang/kaiti/songti）
    var fontFamily: String = "mono"
    /// 毛玻璃强度（>0 = 编辑器背景透明，壁纸从窗口底部模糊透出）
    var glass: Double = 0
    var onChange: (String) -> Void
    /// 光标行/列变化（行号标尺 + 状态栏）
    var onLineChange: (Int, Int) -> Void
    /// 图片粘贴/拖拽回调：(data, ext) -> 相对路径；nil 表示不被处理
    var onImage: ((Data, String) -> String?)?
    /// 任意文件附件回调：(data, fileName) -> 相对路径
    var onAttachment: ((Data, String) -> String?)?
    /// AI 快捷操作（右键菜单）：action + 选中文本
    var onAIMenu: ((AIQuickAction, String) -> Void)?
    /// 当前文件扩展名（决定着色器：md→Markdown；c/cpp/…→CodeHighlighter）
    var fileExtension: String = ""
    /// 文档版本号（store.documentRevision）：区分"主动换文档"与"用户输入领先"
    var revision: Int
    @Binding var textViewRef: NSTextView?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = glass <= 0
        scrollView.backgroundColor = glass > 0 ? .clear : Self.editorBackground()
        scrollView.borderType = .noBorder

        let tv = MarkdownTextView()
        let ext = (text as NSString).pathExtension.lowercased()
        Self.configure(tv, fontSize: fontSize, family: fontFamily, glass: glass, tabSpaces: Self.indentUnit(for: ext))
        tv.delegate = context.coordinator
        let coordinator = context.coordinator
        tv.imageHandler = { [weak coordinator] data, ext in
            coordinator?.parent.onImage?(data, ext)
        }
        tv.attachmentHandler = { [weak coordinator] data, name in
            coordinator?.parent.onAttachment?(data, name)
        }
        tv.aiMenuHandler = { [weak coordinator] action, text in
            coordinator?.parent.onAIMenu?(action, text)
        }
        tv.fileExtension = (text as NSString).pathExtension.lowercased()

        let ruler = LineNumberRulerView(textView: tv)
        scrollView.documentView = tv
        let showLineNumbers = FeatureModules.isEnabled(FeatureModules.editorLineNumbers)
        scrollView.hasVerticalRuler = showLineNumbers
        scrollView.verticalRulerView = showLineNumbers ? ruler : nil
        scrollView.rulersVisible = showLineNumbers

        context.coordinator.textView = tv
        context.coordinator.scrollView = scrollView
        context.coordinator.ruler = ruler
        context.coordinator.lastFontSize = fontSize
        context.coordinator.lastFontFamily = fontFamily

        // 首次创建：直接装入期望文档（此后由 updateNSView 的 revision 仲裁接管）
        if !text.isEmpty {
            context.coordinator.suppress = true
            tv.string = text
            context.coordinator.suppress = false
        }
        context.coordinator.lastRevision = revision

        DispatchQueue.main.async {
            self.textViewRef = tv
            // 仅创建时聚焦一次（此后 updateNSView 不再抢焦点，避免干扰光标）
            if let window = tv.window {
                window.makeFirstResponder(tv)
            }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scrollView.documentView as? NSTextView else { return }
        // 行号厚度只在文本长度变化时重算（避免每帧全文档 lineCount 扫描）
        let len = tv.string.utf16.count
        if len != context.coordinator.lastTextLen {
            context.coordinator.lastTextLen = len
            context.coordinator.ruler?.refreshThickness()
        }
        // ═══ 仲裁逻辑（光标问题的根治）═══
        // revision 变化 = 程序性换文档（打开/恢复/导入）→ store 写入视图（唯一允许反写的时机）
        // revision 相同 + 内容不一致 = 用户输入领先（输入法末段字未回填 store）→ 以视图为准回填，
        //   绝不覆盖视图 —— 不丢字、不跳光标。
        if context.coordinator.lastRevision != revision {
            context.coordinator.lastRevision = revision
            context.coordinator.clearFind(tv)
            context.coordinator.suppress = true
            tv.string = text
            tv.undoManager?.removeAllActions()
            context.coordinator.suppress = false
            context.coordinator.ruler?.refreshThickness()
            context.coordinator.scheduleHighlight(tv)
            // 朴素默认：打开/换文档后光标位于文档顶部
            SelLog.log("REVISION-SWITCH last=\(context.coordinator.lastRevision) new=\(revision) → set(0,0)")
            tv.setSelectedRange(NSRange(location: 0, length: 0))
        } else if tv.string != text {
            // 视图领先 → 回填 store（防丢字、防跳顶）
            if !context.coordinator.suppress {
                onChange(tv.string)
            }
        }
        // 字体仅在字号/家族变化时赋值：每帧重赋会强制布局失效（大文档卡顿源之一）
        context.coordinator.applyFontIfNeeded(tv, fontSize: fontSize, family: fontFamily)
        context.coordinator.applyGlassIfNeeded(tv, glass: glass)
    }

    static func configure(_ tv: NSTextView, fontSize: CGFloat, family: String, glass: Double, tabSpaces: Int = 2) {
        tv.isRichText = false
        tv.allowsUndo = true
        tv.usesFontPanel = false
        tv.font = resolveFont(family: family, size: fontSize)
        tv.textColor = editorForeground()
        tv.drawsBackground = glass <= 0
        tv.backgroundColor = glass > 0 ? .clear : editorBackground()
        tv.insertionPointColor = .controlAccentColor
        tv.selectedTextAttributes = [
            .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.18),
            .foregroundColor: editorForeground(),
        ]
        // Markdown 书写场景全部关闭智能替换
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        // 等长 tab（2 格缩进）
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 4
        p.tabStops = (1...40).map {
            NSTextTab(textAlignment: .left, location: CGFloat($0) * CGFloat(tabSpaces) * (fontSize * 0.6), options: [:])
        }
        tv.defaultParagraphStyle = p
        // 文本区域布局
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainerInset = NSSize(width: 8, height: 14)
    }

    /// 缩进单位（空格数）：C 系/代码 4；文档/标记 2（VSCode 惯例）
    static func indentUnit(for ext: String) -> Int {
        if let o = PluginManager.shared.fileOverride(for: ext), let ind = o.indent, ind > 0 {
            return ind
        }
        let code4: Set<String> = ["c", "cpp", "cc", "h", "hpp", "m", "mm", "cs", "java", "kt", "go", "rs",
                                  "py", "rb", "php", "js", "jsx", "ts", "tsx", "swift", "css", "scss",
                                  "sass", "less", "styl", "vue", "svelte", "sh", "bash", "zsh", "sql",
                                  "gradle", "mk"]
        return code4.contains(ext.lowercased()) ? 4 : 2
    }

    /// Markdown 扩展名（Markdown 着色 + 预览渲染管线）
    static func isMarkdownExt(_ ext: String) -> Bool {
        ["md", "markdown", "mdown", "mdx"].contains(ext.lowercased())
    }

    /// 可编辑的非 Markdown 文本（代码着色管线；txt/json 等无关键字时退化为纯色显示并无害）
    static func isCodeExt(_ ext: String) -> Bool {
        !isMarkdownExt(ext) && Workspace.isEditorText(ext)
    }

    /// 编辑器底色：与预览主题 bg 完全对齐（晨曦 #FAF8F5 / 夜航者 #11131A），消除拼接缝
    static func editorBackground() -> NSColor {
        switch currentTheme {
        case .night:
            return NSColor(calibratedRed: 0.067, green: 0.075, blue: 0.102, alpha: 1) // #11131A
        case .dawn:
            return NSColor(calibratedRed: 0.980, green: 0.973, blue: 0.961, alpha: 1) // #FAF8F5
        }
    }

    /// 编辑器前景色（正文）—— 按主题显式决定，不依赖视图外观：
    /// 修复「夜航者黑底黑字」：.labelColor 按有效外观解析，主题联动时外观未同步 → 解析为黑。
    static func editorForeground() -> NSColor {
        switch currentTheme {
        case .night:  return NSColor.sRGB(0.93, 0.94, 0.96)   // 近白（深底 ≥14:1）
        case .dawn:   return NSColor.sRGB(0.13, 0.14, 0.17)   // 近黑（浅底 ≥14:1）
        }
    }

    /// 字体家族 → NSFont（macOS 内置字体；未知家族回退系统等宽）
    static func resolveFont(family: String, size: CGFloat) -> NSFont {
        let defaultMono = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        switch family {
        case "menlo": return NSFont(name: "Menlo-Regular", size: size) ?? defaultMono
        case "monaco": return NSFont(name: "Monaco", size: size) ?? defaultMono
        case "pingfang": return NSFont(name: "PingFangSC-Regular", size: size) ?? defaultMono
        case "kaiti": return NSFont(name: "KaitiSC-Regular", size: size) ?? defaultMono
        case "songti": return NSFont(name: "SongtiSC-Regular", size: size) ?? defaultMono
        default:
            // "mono" = SF Mono（系统等宽）；自定义导入家族名已经 CTFontManager 注册，直接按名解析
            return NSFont(name: family, size: size) ?? defaultMono
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditorView
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        weak var ruler: LineNumberRulerView?
        /// 已应用毛玻璃（同样只在变化时切换背景，避免每帧重绘）
        var lastGlass = -1.0
        var suppress = false
        var lastRevision = -1
        var lastTextLen = -1
        /// 当前行高亮范围（用于移除旧高亮）
        var highlightRange: NSRange?
        private let currentLineColor = NSColor.controlAccentColor.withAlphaComponent(0.09)
        /// 已应用字号/家族（字体仅在变化时赋值，避免每帧布局失效）
        var lastFontSize: CGFloat = -1
        var lastFontFamily = ""

        func applyFontIfNeeded(_ tv: NSTextView, fontSize: CGFloat, family: String) {
            guard abs(lastFontSize - fontSize) > 0.001 || lastFontFamily != family else { return }
            lastFontSize = fontSize
            lastFontFamily = family
            tv.font = MarkdownEditorView.resolveFont(family: family, size: fontSize)
            ruler?.refreshThickness()
        }

        /// 毛玻璃切换：编辑器/滚动区/行号标尺背景统一透明（壁纸透出）或还原
        func applyGlassIfNeeded(_ tv: NSTextView, glass: Double) {
            guard abs(lastGlass - glass) > 0.001 else { return }
            lastGlass = glass
            let on = glass > 0
            tv.drawsBackground = !on
            tv.backgroundColor = on ? .clear : MarkdownEditorView.editorBackground()
            if let sv = scrollView ?? tv.enclosingScrollView {
                sv.drawsBackground = !on
                sv.backgroundColor = on ? .clear : MarkdownEditorView.editorBackground()
            }
            // 行号标尺仅绘制数字与高亮条（不填充背景），随滚动区背景一起透明
        }
        // MARK: - VS Code 式查找/替换（⌘F / ⇧⌘F）

        private(set) var findMatches: [NSRange] = []
        private(set) var findCurrent = 0
        private var findActive = false
        private let findMatchColor = NSColor.systemYellow.withAlphaComponent(0.28)
        private let findCurrentColor = NSColor.systemOrange.withAlphaComponent(0.52)

        /// 执行查找/替换；action: find / next / prev / replace / replaceAll / clear
        func runFind(_ tv: NSTextView, query: String, replace: String?, action: String) -> (total: Int, current: Int) {
            let text = tv.string as NSString
            guard !query.isEmpty, text.length > 0 else {
                clearFind(tv)
                return (0, 0)
            }
            if action == "clear" || action == "replaceAll" && replace == nil {
                if action == "clear" { clearFind(tv); return (0, 0) }
            }
            if action == "replace" || action == "replaceAll" {
                performReplace(tv, query: query, replace: replace ?? "", all: action == "replaceAll")
                // 替换后重建匹配
            }
            let matches = findAll(tv, query: query)
            findMatches = matches
            findActive = true

            let currentIndex: Int
            switch action {
            case "next": currentIndex = nextIndex(tv)
            case "prev": currentIndex = prevIndex()
            default: currentIndex = findMatches.isEmpty ? 0 : 0
            }

            applyFindHighlights(tv, currentIndex: currentIndex)
            if !findMatches.isEmpty, findMatches.indices.contains(currentIndex) {
                let r = findMatches[currentIndex]
                tv.scrollRangeToVisible(r)
            }
            return (findMatches.count, findMatches.indices.contains(currentIndex) ? currentIndex : 0)
        }

        private func findAll(_ tv: NSTextView, query: String) -> [NSRange] {
            let text = tv.string as NSString
            let nsQuery = query as NSString
            var out: [NSRange] = []
            var start = 0
            while start < text.length {
                let r = text.range(of: nsQuery as String, options: [.caseInsensitive, .diacriticInsensitive],
                                   range: NSRange(location: start, length: text.length - start))
                if r.location == NSNotFound { break }
                out.append(r)
                guard r.length > 0 else { break }
                start = r.location + r.length
            }
            return out
        }

        private func applyFindHighlights(_ tv: NSTextView, currentIndex: Int) {
            guard let ts = tv.textStorage else { return }
            // 清理旧
            for r in findMatches where r.location + r.length <= ts.length {
                ts.removeAttribute(.backgroundColor, range: r)
                ts.removeAttribute(.underlineStyle, range: r)
            }
            for (i, r) in findMatches.enumerated() where r.location + r.length <= ts.length {
                ts.addAttribute(.backgroundColor, value: i == currentIndex ? findCurrentColor : findMatchColor, range: r)
                ts.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            }
        }

        private func nextIndex(_ tv: NSTextView) -> Int {
            let sel = tv.selectedRange()
            if let i = findMatches.firstIndex(where: { $0.location >= sel.location + sel.length && $0.location != NSNotFound }) {
                findCurrent = i
            } else { findCurrent = 0 }
            return findCurrent
        }

        private func prevIndex() -> Int {
            let sel = (textView?.selectedRange() ?? NSRange(location: 0, length: 0))
            var chosen = findMatches.count - 1
            for (i, r) in findMatches.enumerated() where r.location < sel.location {
                chosen = i
            }
            findCurrent = chosen
            return chosen
        }

        private func performReplace(_ tv: NSTextView, query: String, replace: String, all: Bool) {
            let text = tv.string as NSString
            if all {
                var acc = text.substring(with: NSRange(location: 0, length: text.length))
                let replaced = acc.replacingOccurrences(of: query, with: replace, options: [.caseInsensitive, .diacriticInsensitive])
                if replaced != acc {
                    tv.string = replaced
                    onChangeProgrammatic(tv)
                }
            } else {
                let sel = tv.selectedRange()
                var r = sel
                if sel.length == 0 {
                    let found = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: NSRange(location: 0, length: text.length))
                    if found.location == NSNotFound { return }
                    r = found
                }
                guard r.length > 0 else { return }
                tv.insertText(replace, replacementRange: r)
                onChangeProgrammatic(tv)
            }
        }

        func clearFind(_ tv: NSTextView) {
            guard let ts = tv.textStorage else { return }
            for r in findMatches where r.location + r.length <= ts.length {
                ts.removeAttribute(.backgroundColor, range: r)
                ts.removeAttribute(.underlineStyle, range: r)
            }
            findMatches = []
            findActive = false
        }

        /// 替换后同步 store（自动保存链）— 绕过 suppress
        private func onChangeProgrammatic(_ tv: NSTextView) {
            if !suppress { parent.onChange(tv.string) }
            reportLine(tv)
            scheduleHighlight(tv)
        }

        /// 语法着色调度（后台解析 + 主线程应用）
        private var highlightWork: DispatchWorkItem?

        // MARK: - 语法着色

        func scheduleHighlight(_ tv: NSTextView) {
            highlightWork?.cancel()
            let text = tv.string
            let isMarkdown = MarkdownEditorView.isMarkdownExt(parent.fileExtension)
            if !isMarkdown && !FeatureModules.isEnabled(FeatureModules.editorCodeSmart) { return }
            let isCode = MarkdownEditorView.isCodeExt(parent.fileExtension)
            // 后台解析 + 预计算颜色 → 主线程只应用（颜色表静态化，跨线程安全）
            let item = DispatchWorkItem { [weak self] in
                let pairs: [(NSRange, NSColor)] = isMarkdown
                    ? MarkdownHighlighter.tokenize(text).compactMap { tok in
                        MarkdownEditorView.Coordinator.color(for: tok.kind).map { (tok.range, $0) }
                    }
                    : CodeHighlighter.tokenize(text).map { tok in
                        (tok.range, MarkdownEditorView.Coordinator.codeColor(for: tok.kind))
                    }
                DispatchQueue.main.async {
                    guard let self, let tv = self.textView else { return }
                    if isMarkdown {
                        self.applyHighlight(MarkdownHighlighter.tokenize(text), tv: tv)
                    } else if isCode {
                        self.applyCodeHighlight(pairs, tv: tv)
                    }
                }
            }
            highlightWork = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
        }

        /// 上一轮应用了装饰属性的范围（高亮重算时先精确复位，不留残痕）
        private var lastStyleRanges: [NSRange] = []

        // MARK: - 代码着色（C/C++ 等：VSCode 原生体验）

        private func applyCodeHighlight(_ pairs: [(NSRange, NSColor)], tv: NSTextView) {
            guard let ts = tv.textStorage else { return }
            let len = ts.length
            guard len > 0 else { return }
            ts.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: len))
            for (range, color) in pairs where range.location + range.length <= len {
                ts.addAttribute(.foregroundColor, value: color, range: range)
            }
        }

        /// 代码语法色（明暗自适应：暗色变体 ≥4.5:1）
        static func codeColor(for kind: CodeKind) -> NSColor {
            let dark = currentTheme == .night
            switch kind {
            case .keyword: return dark ? NSColor.sRGB(1.00, 0.48, 0.45) : NSColor.sRGB(0.65, 0.15, 0.65)   // #FF7B72 / #A626A4
            case .type:    return dark ? NSColor.sRGB(0.47, 0.75, 1.00) : NSColor.sRGB(0.58, 0.22, 0.00)   // #79C0FF / #953800
            case .string:  return dark ? NSColor.sRGB(0.65, 0.84, 1.00) : NSColor.sRGB(0.01, 0.20, 0.38)   // #A5D6FF / #032F62
            case .comment: return dark ? NSColor.sRGB(0.55, 0.58, 0.62) : NSColor.sRGB(0.42, 0.46, 0.49)   // #8B949E / #6A737D
            case .preproc: return dark ? NSColor.sRGB(0.82, 0.66, 1.00) : NSColor.sRGB(0.40, 0.22, 0.73)   // #D2A8FF / #6639BA
            case .number:  return dark ? NSColor.sRGB(0.47, 0.75, 1.00) : NSColor.sRGB(0.00, 0.36, 0.77)   // #79C0FF / #005CC5
            }
        }

        // MARK: - 括号匹配高亮（VSCode 式：光标贴括号 → 配对高亮）

        private var bracketRanges: (NSRange, NSRange)?

        func updateBracketMatch(_ tv: NSTextView) {
            guard FeatureModules.isEnabled(FeatureModules.editorBracketMatch) else { return }
            guard let ts = tv.textStorage else { return }
            if let old = bracketRanges {
                ts.removeAttribute(.backgroundColor, range: old.0)
                if old.1.location + old.1.length <= ts.length {
                    ts.removeAttribute(.backgroundColor, range: old.1)
                }
                bracketRanges = nil
            }
            let sel = tv.selectedRange()
            guard sel.length == 0, let (a, b) = BracketMatcher.match(in: tv.string, at: sel.location) else { return }
            let color = NSColor.controlAccentColor.withAlphaComponent(0.38)
            if a.location + a.length <= ts.length { ts.addAttribute(.backgroundColor, value: color, range: a) }
            if b.location + b.length <= ts.length { ts.addAttribute(.backgroundColor, value: color, range: b) }
            bracketRanges = (a, b)
        }


        private func applyHighlight(_ tokens: [MDToken], tv: NSTextView) {
            guard let ts = tv.textStorage else { return }
            let len = ts.length
            guard len > 0 else { return }
            ts.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: len))
            // 1) 复位上一轮的装饰（字体回基座、删除线/下划线/背景清除）—— 精确到旧范围，不误伤正文
            let baseFont = MarkdownEditorView.resolveFont(family: lastFontFamily, size: lastFontSize)
            for r in lastStyleRanges where r.location + r.length <= len {
                ts.removeAttribute(.strikethroughStyle, range: r)
                ts.removeAttribute(.underlineStyle, range: r)
                ts.removeAttribute(.backgroundColor, range: r)
                ts.addAttribute(.font, value: baseFont, range: r)
            }
            lastStyleRanges = []
            // 2) 应用：颜色 + 装饰（等宽粗/斜体变体 advance 不变 → 打字不重排）
            var styleRanges: [NSRange] = []
            for t in tokens where t.range.location + t.range.length <= len {
                if let c = Self.color(for: t.kind) {
                    ts.addAttribute(.foregroundColor, value: c, range: t.range)
                }
                switch t.kind {
                case .heading, .bold:
                    ts.addAttribute(.font, value: Self.boldFont(baseFont), range: t.range)
                case .italic:
                    ts.addAttribute(.font, value: Self.italicFont(baseFont), range: t.range)
                case .code, .fenceBody:
                    ts.addAttribute(.backgroundColor, value: NSColor.labelColor.withAlphaComponent(0.07), range: t.range)
                case .fenceHead:
                    ts.addAttribute(.font, value: Self.boldFont(baseFont), range: t.range)
                    ts.addAttribute(.backgroundColor, value: NSColor.labelColor.withAlphaComponent(0.05), range: t.range)
                case .strikethrough:
                    ts.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: t.range)
                case .insert:
                    ts.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: t.range)
                case .highlight:
                    ts.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.28), range: t.range)
                case .linkLabel:
                    ts.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: t.range)
                case .taskBox:
                    ts.addAttribute(.backgroundColor, value: NSColor.systemGreen.withAlphaComponent(0.16), range: t.range)
                default:
                    break
                }
                styleRanges.append(t.range)
            }
            lastStyleRanges = styleRanges
        }

        private static func boldFont(_ base: NSFont) -> NSFont {
            NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
        }
        private static func italicFont(_ base: NSFont) -> NSFont {
            NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
        }

        /// 明暗自适应色：暗色变体保证 ≥4.5:1（夜航者 #11131A 深底），标题/代码不再发暗。
        /// 关键：以「主题」而非 NSView 有效外观决定（主题底色是显式的，外观可能未同步 —— 黑底黑字根因）。
        private static func adaptive(_ light: NSColor, _ dark: NSColor) -> NSColor {
            currentTheme == .night ? dark : light
        }

        static func color(for kind: MDKind) -> NSColor? {
            switch kind {
            case .heading:
                return adaptive(.sRGB(0.42, 0.31, 0.85), .sRGB(0.72, 0.61, 1.00))          // 紫
            case .bold:
                return NSColor.systemOrange
            case .italic:
                return NSColor.systemTeal
            case .code, .fenceHead, .fenceBody:
                return adaptive(NSColor.systemOrange, .sRGB(1.00, 0.72, 0.42))             // #FFB86C
            case .linkLabel:
                return adaptive(NSColor.systemBlue, .sRGB(0.42, 0.63, 1.00))               // #6CA0FF
            case .linkURL:
                return adaptive(NSColor.systemPurple, .sRGB(0.75, 0.55, 1.00))             // #C08CFF
            case .quote, .hr, .tableSep, .strikethrough:
                return NSColor.tertiaryLabelColor
            case .listBullet, .listNumber, .taskBox:
                return NSColor.secondaryLabelColor
            case .math:
                return adaptive(NSColor.systemPink, .sRGB(1.00, 0.56, 0.78))               // #FF8FC8
            case .highlight:
                return adaptive(NSColor.systemRed, .sRGB(1.00, 0.48, 0.45))                // #FF7B72
            case .insert:
                return adaptive(NSColor.systemGreen, .sRGB(0.49, 0.91, 0.53))              // #7EE787
            }
        }

        /// 当前行背景底纹（不影响 undo 栈与选区颜色）
        func updateCurrentLineHighlight(_ tv: NSTextView) {
            guard FeatureModules.isEnabled(FeatureModules.editorCurrentLine) else { return }
            guard let ts = tv.textStorage else { return }
            if let old = highlightRange, old.length > 0,
               old.location + old.length <= ts.length {
                ts.removeAttribute(.backgroundColor, range: old)
            }
            highlightRange = nil
            let text = tv.string as NSString
            guard text.length > 0 else { return }
            let sel = tv.selectedRange()
            let loc = min(sel.location, text.length)
            let lineRange = text.lineRange(for: NSRange(location: min(loc, text.length), length: 0))
            var length = lineRange.length
            if text.character(at: lineRange.location + lineRange.length - 1) == 0x0A, length > 0 { length -= 1 }
            let range = NSRange(location: lineRange.location, length: max(1, length))
            ts.addAttribute(.backgroundColor, value: currentLineColor, range: range)
            highlightRange = range
            updateBracketMatch(tv)
        }

        init(_ parent: MarkdownEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            ruler?.refreshThickness()
            if !suppress {
                parent.onChange(tv.string)
            }
            reportLine(tv)
            scheduleHighlight(tv)
        }

        func textDidChangeSelection(_ notification: Notification) {
            let tv = textView
            SelLog.log("SELCHANGED range=\(String(describing: tv?.selectedRange()))")
            guard let tv, tv.selectedRange().length == 0 else { return }
            reportLine(tv)
        }

        /// 当前光标所在行/列 → 标尺高亮 + 状态栏
        private func reportLine(_ tv: NSTextView) {
            let text = tv.string as NSString
            guard text.length > 0, let lm = tv.layoutManager else {
                ruler?.currentLine = 1
                parent.onLineChange(1, 1)
                return
            }
            let sel = tv.selectedRange()
            let loc = min(sel.location, text.length)
            let glyph = lm.glyphIndexForCharacter(at: min(loc, text.length - 1))
            let fragment = lm.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            let lineNumber = lineNumber(of: loc, in: text)
            let lineRange = text.lineRange(for: NSRange(location: min(loc, text.length), length: 0))
            _ = fragment
            ruler?.currentLine = lineNumber
            // 列号按字符（grapheme）而非 UTF-16 单元：Emoji/组合字符不虚增（C-10）
            parent.onLineChange(lineNumber, EditorMetrics.column(of: loc, in: lineRange, text: text))
            updateCurrentLineHighlight(tv)
        }

        /// 指定字符位置前的换行数 + 1（即全局行号，1-based）
        private func lineNumber(of location: Int, in text: NSString) -> Int {
            // 性能：逐字符扫到光标 = O(n)（大文档移动光标卡点）；改按行跳（O(行数)）
            var count = 1
            var i = 0
            var end = 0
            while i < min(location, text.length) {
                text.getLineStart(nil, end: &end, contentsEnd: nil, for: NSRange(location: i, length: min(1, text.length - i)))
                if end > i + 1 { count += 1 } // 行尾（含 \n）→ 下一行
                i = max(end, i + 1)
                if end <= i { break }
            }
            return count
        }
    }
}


/// 编辑器度量换算 —— 纯函数，便于单元测试（见 MarkNoteTests RegressionTests）
enum EditorMetrics {
    /// 光标 UTF-16 偏移 → 行内字符列（0-based，grapheme 计数，兼容 Emoji/组合字符）
    static func column(of location: Int, in lineRange: NSRange, text: NSString) -> Int {
        guard location >= lineRange.location else { return 0 }
        let capped = min(location, lineRange.location + lineRange.length)
        let length = capped - lineRange.location
        guard length > 0 else { return 0 }
        let prefix = text.substring(with: NSRange(location: lineRange.location, length: length))
        return prefix.count
    }
}

extension NSColor {
    /// 便捷 sRGB 构造（显式 sRGB 色域，避免 calibrated 在 P3 屏色偏）
    static func sRGB(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

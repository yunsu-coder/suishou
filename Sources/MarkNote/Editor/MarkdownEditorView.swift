import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Markdown 源码编辑器 —— 纯 AppKit NSTextView 封装：
/// 行号标尺、等宽字体、原生撤销、智能替换关闭。
/// 性能优先：不经过 SwiftUI TextEditor，直接控制文本系统。
struct MarkdownEditorView: NSViewRepresentable {

    let text: String
    let fontSize: CGFloat
    var onChange: (String) -> Void
    /// 光标行/列变化（行号标尺 + 状态栏）
    var onLineChange: (Int, Int) -> Void
    /// 图片粘贴/拖拽回调：(data, ext) -> 相对路径；nil 表示不被处理
    var onImage: ((Data, String) -> String?)?
    /// 任意文件附件回调：(data, fileName) -> 相对路径
    var onAttachment: ((Data, String) -> String?)?
    /// 文档版本号（store.documentRevision）：区分"主动换文档"与"用户输入领先"
    var revision: Int
    @Binding var textViewRef: NSTextView?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor
        scrollView.borderType = .noBorder

        let tv = MarkdownTextView()
        Self.configure(tv, fontSize: fontSize)
        tv.delegate = context.coordinator
        let coordinator = context.coordinator
        tv.imageHandler = { [weak coordinator] data, ext in
            coordinator?.parent.onImage?(data, ext)
        }
        tv.attachmentHandler = { [weak coordinator] data, name in
            coordinator?.parent.onAttachment?(data, name)
        }

        let ruler = LineNumberRulerView(textView: tv)
        scrollView.documentView = tv
        scrollView.hasVerticalRuler = true
        scrollView.verticalRulerView = ruler
        scrollView.rulersVisible = true

        context.coordinator.textView = tv
        context.coordinator.ruler = ruler

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
            let textLen = (text as NSString).length
            context.coordinator.suppress = true
            tv.string = text
            tv.undoManager?.removeAllActions()
            context.coordinator.suppress = false
            context.coordinator.ruler?.refreshThickness()
            context.coordinator.scheduleHighlight(tv)
            // 朴素默认：打开/换文档后光标位于文档顶部
            tv.setSelectedRange(NSRange(location: 0, length: 0))
        } else if tv.string != text {
            // 视图领先 → 回填 store（防丢字、防跳顶）
            if !context.coordinator.suppress {
                onChange(tv.string)
            }
        }
        tv.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        context.coordinator.ruler?.refreshThickness()
    }

    static func configure(_ tv: NSTextView, fontSize: CGFloat) {
        tv.isRichText = false
        tv.allowsUndo = true
        tv.usesFontPanel = false
        tv.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        tv.textColor = .labelColor
        tv.backgroundColor = .textBackgroundColor
        tv.insertionPointColor = .controlAccentColor
        tv.selectedTextAttributes = [
            .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.18),
            .foregroundColor: NSColor.labelColor,
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
            NSTextTab(textAlignment: .left, location: CGFloat($0) * 2 * (fontSize * 0.6), options: [:])
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

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditorView
        weak var textView: NSTextView?
        weak var ruler: LineNumberRulerView?
        var suppress = false
        var lastRevision = -1
        var lastTextLen = -1
        /// 当前行高亮范围（用于移除旧高亮）
        var highlightRange: NSRange?
        private let currentLineColor = NSColor.controlAccentColor.withAlphaComponent(0.09)
        /// 语法着色调度（后台解析 + 主线程应用）
        private var highlightWork: DispatchWorkItem?

        // MARK: - 语法着色

        func scheduleHighlight(_ tv: NSTextView) {
            highlightWork?.cancel()
            let text = tv.string
            let item = DispatchWorkItem { [weak self] in
                let tokens = MarkdownHighlighter.tokenize(text)
                DispatchQueue.main.async {
                    guard let self, let tv = self.textView else { return }
                    self.applyHighlight(tokens, tv: tv)
                }
            }
            highlightWork = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
        }

        private func applyHighlight(_ tokens: [MDToken], tv: NSTextView) {
            guard let ts = tv.textStorage else { return }
            let len = ts.length
            guard len > 0 else { return }
            ts.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: len))
            for t in tokens where t.range.location + t.range.length <= len {
                if let c = Self.color(for: t.kind) {
                    ts.addAttribute(.foregroundColor, value: c, range: t.range)
                }
            }
        }

        /// 中低饱和色（深浅主题通用可读）
        static func color(for kind: MDKind) -> NSColor? {
            switch kind {
            case .heading: return NSColor(calibratedRed: 0.52, green: 0.34, blue: 0.93, alpha: 1)
            case .bold: return NSColor.systemOrange
            case .italic: return NSColor.systemTeal
            case .code, .fenceHead, .fenceBody: return NSColor.systemOrange
            case .linkLabel: return NSColor.systemBlue
            case .linkURL: return NSColor.systemPurple
            case .quote, .hr, .tableSep, .strikethrough: return NSColor.tertiaryLabelColor
            case .listBullet, .listNumber, .taskBox: return NSColor.secondaryLabelColor
            case .math: return NSColor.systemPink
            case .highlight: return NSColor.systemRed
            case .insert: return NSColor.systemGreen
            }
        }

        /// 当前行背景底纹（不影响 undo 栈与选区颜色）
        func updateCurrentLineHighlight(_ tv: NSTextView) {
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
            guard let tv = textView, tv.selectedRange().length == 0 else { return }
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
            parent.onLineChange(lineNumber, loc - lineRange.location)
            updateCurrentLineHighlight(tv)
        }

        /// 指定字符位置前的换行数 + 1（即全局行号，1-based）
        private func lineNumber(of location: Int, in text: NSString) -> Int {
            var count = 1
            var i = 0
            while i < min(location, text.length) {
                if text.character(at: i) == 0x0A { count += 1 }
                i += 1
            }
            return count
        }
    }
}

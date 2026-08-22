import AppKit

/// 行号标尺 —— 挂在 NSScrollView.verticalRulerView 上，
/// 由 AppKit 自动处理滚动同步，用 NSLayoutManager 逐行计算位置绘制。
final class LineNumberRulerView: NSRulerView {

    private weak var textView: NSTextView?
    /// 当前光标所在行（高亮底条 + 加粗标号）— 由 editor 更新
    var currentLine: Int = 1 { didSet { needsDisplay = true } }

    /// 行高与文本可视范围的交集，用于绘制 & 判定
    private struct LineFragment { let y: CGFloat; let height: CGFloat }

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 48
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - 绘制

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView, let lm = tv.layoutManager else { return }
        let text = tv.string as NSString
        guard text.length > 0 else { return }

        let digitFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let para = NSMutableParagraphStyle()
        para.alignment = .right

        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: digitFont, .foregroundColor: NSColor.tertiaryLabelColor, .paragraphStyle: para,
        ]
        let highlightAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.controlAccentColor, .paragraphStyle: para,
        ]

        let x = ruleThickness - 8

        // 逐行（NSString 原生行），绘制 rect 相交的行号
        var charIndex = 0
        var lineNumber = 1
        while charIndex < text.length {
            let lineRange = text.lineRange(for: NSRange(location: charIndex, length: 1))
            let glyph = lm.glyphIndexForCharacter(at: charIndex)
            let fragment = lm.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            let numY = fragment.origin.y + tv.textContainerOrigin.y
            let numRect = NSRect(x: 0, y: numY, width: ruleThickness - 2, height: fragment.height)

            if numRect.maxY > rect.minY && numRect.minY < rect.maxY {
                let num = String(lineNumber)
                let width = (num as NSString).size(withAttributes: lineNumber == currentLine ? highlightAttrs : normalAttrs).width
                num.draw(at: NSPoint(x: x - width, y: numY + 3),
                         withAttributes: lineNumber == currentLine ? highlightAttrs : normalAttrs)
            }
            if numY > rect.maxY { break } // 已越过可视区，提前结束
            charIndex = lineRange.location + lineRange.length
            lineNumber += 1
            if lineNumber > 100_000 { break }
        }

        // 当前行高亮底条
        if currentLine >= 1 {
            var sel = tv.selectedRange()
            sel.location = min(sel.location, text.length)
            if text.length > 0 {
                let glyph = lm.glyphIndexForCharacter(at: sel.location == text.length ? text.length - 1 : sel.location)
                let fragment = lm.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
                let y = fragment.origin.y + tv.textContainerOrigin.y
                let bar = NSRect(x: 2, y: y, width: ruleThickness - 6, height: fragment.height).insetBy(dx: 0, dy: -1)
                NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()
                NSBezierPath(roundedRect: bar, xRadius: 3, yRadius: 3).fill()
            }
        }
    }

    /// 行数变化时标尺宽度自适应（位数决定）
    func refreshThickness() {
        let count = (textView?.string as NSString?)?.lineCount() ?? 1
        let digits = max(1, String(count).count)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let w = ceil(("8" as NSString).size(withAttributes: [.font: font]).width * CGFloat(digits)) + 26
        ruleThickness = max(40, w)
    }
}

extension NSString {
    func lineCount() -> Int {
        var count = 1
        var i = 0
        while i < length {
            let r = lineRange(for: NSRange(location: i, length: 1))
            count += 1
            i = r.location + r.length
        }
        return count
    }
}

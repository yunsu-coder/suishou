import XCTest
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import MarkNote

final class PreviewRenderStateTests: XCTestCase {
    func testSameLengthEditTriggersRender() {
        var st = PreviewRenderState()
        XCTAssertTrue(st.shouldRender(md: "abc", meta: "m", token: "n1").render)
        XCTAssertFalse(st.shouldRender(md: "abc", meta: "m", token: "n1").render, "内容/参数未变不渲染")
        let r = st.shouldRender(md: "abd", meta: "m", token: "n1")  // 同长度替换（旧 bug 漏渲染）
        XCTAssertTrue(r.render, "同长度内容替换必须触发渲染")
        XCTAssertFalse(r.resetScroll, "同笔记内编辑不重置滚动")
        XCTAssertTrue(st.shouldRender(md: "abd", meta: "m", token: "n2").resetScroll, "切换笔记重置滚动")
    }

    func testParameterChangeTriggersRender() {
        var st = PreviewRenderState()
        _ = st.shouldRender(md: "x", meta: "base|1", token: "t")
        XCTAssertTrue(st.shouldRender(md: "x", meta: "base|1.1", token: "t").render, "缩放变化应重渲染")
    }
}

final class EditorMetricsTests: XCTestCase {
    func testColumnCountsGraphemesNotUTF16() {
        let s = "abc" + "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}" + "xyz"  // abc + 家庭 emoji + xyz
        let text = s as NSString
        let lineRange = NSRange(location: 0, length: text.length)
        let xOffset = (text as String).distance(from: s.startIndex, to: s.range(of: "xyz")!.lowerBound)
        let column = EditorMetrics.column(of: xOffset, in: lineRange, text: text)
        XCTAssertEqual(column, 4, "a/b/c + 家庭 emoji（1 个 grapheme）→ 列号应为 4，而非 UTF-16 偏移")
    }
}

final class MarkdownHighlighterTests: XCTestCase {
    func testTokenKinds() {
        let md = "# 标题\n\n```swift\nlet x = 1\n```\n\n**bold** [code] $E=mc^2$"
        let tokens = MarkdownHighlighter.tokenize(md)
        func has(_ kind: MDKind) -> Bool {
            tokens.contains { if case kind = $0.kind { return true }; return false }
        }
        XCTAssertTrue(has(.heading))
        XCTAssertTrue(has(.fenceHead))
        XCTAssertTrue(has(.fenceBody))
        XCTAssertTrue(has(.bold))
        XCTAssertTrue(has(.math))
    }

    func testOversizedDocSkipped() {
        let big = String(repeating: "a", count: 600_000)
        XCTAssertTrue(MarkdownHighlighter.tokenize(big).isEmpty)
    }
}

final class ImagePipelineTests: XCTestCase {
    func testResampleWideImage() throws {
        // 纯 CGContext 生成 2000×1000 JPEG（避开 NSBitmapImageRep 在 CI/宿主环境的不稳定构造）
        let ctx = CGContext(
            data: nil, width: 2000, height: 1000, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        ctx.setFillColor(CGColor(gray: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 2000, height: 1000))
        let cg = try XCTUnwrap(ctx.makeImage())
        let jpeg = try XCTUnwrap(NotesStore.encodeCG(cg, jpeg: true))
        XCTAssertGreaterThan(jpeg.count, 0)

        let out = NotesStore.balancedImageData(jpeg, mime: "image/jpeg")
        let src = try XCTUnwrap(CGImageSourceCreateWithData(out as CFData, nil))
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let width = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        XCTAssertLessThanOrEqual(width, 1600, "大于1600px 的图必须重采样")
        XCTAssertGreaterThan(width, 0)
        // PNG 透明大图保持 PNG 输出（alpha 保真）：生成带 alpha 通道的 2000×1000 图
        let ctxA = CGContext(
            data: nil, width: 2000, height: 1000, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctxA.setFillColor(CGColor(gray: 0.3, alpha: 0.5))
        ctxA.fill(CGRect(x: 0, y: 0, width: 2000, height: 1000))
        let cgA = try XCTUnwrap(ctxA.makeImage())
        let png = try XCTUnwrap(NotesStore.encodeCG(cgA, jpeg: false))
        let outPNG = NotesStore.balancedImageData(png, mime: "image/png")
        let srcPNG = try XCTUnwrap(CGImageSourceCreateWithData(outPNG as CFData, nil))
        let t = CGImageSourceGetType(srcPNG) as String?
        XCTAssertEqual(t, UTType.png.identifier, "透明 PNG 不得被压成 JPEG")
        let wPNG = (CGImageSourceCopyPropertiesAtIndex(srcPNG, 0, nil) as? [CFString: Any])?[kCGImagePropertyPixelWidth] as? Int ?? 0
        XCTAssertLessThanOrEqual(wPNG, 1600, "透明大图同样重采样到 1600")
    }

    /// 编辑器字体家族解析：设置页六种选项均能命中内置字体，字号保持，未知家族回退等宽
    func testEditorFontResolution() {
        let size = 13.0
        for family in ["mono", "menlo", "monaco", "pingfang", "kaiti", "songti"] {
            let font = MarkdownEditorView.resolveFont(family: family, size: size)
            XCTAssertEqual(font.pointSize, size, "\(family) 字号应保持")
            XCTAssertFalse(font.pointSize == 0, "\(family) 不得解析为空字体")
        }
        let fallback = MarkdownEditorView.resolveFont(family: "unknown-family", size: size)
        XCTAssertEqual(fallback.pointSize, size, "未知家族应回退系统等宽（保留字号）")
    }

    /// REQ-ED-04 多行缩进/反缩进：纯字符串变换正确性（行尾空行不缩进、Tab/空格混排反缩进）
    func testIndentTransform() {
        // 整块缩进：每行 +2；末尾空行不补空格
        XCTAssertEqual(MarkdownTextView.transformIndent("- a\n- b", indent: true), "  - a\n  - b")
        XCTAssertEqual(MarkdownTextView.transformIndent("- a\n", indent: true), "  - a\n")
        // 反缩进：先卸一个 Tab，否则最多 2 个空格
        XCTAssertEqual(MarkdownTextView.transformIndent("  - a\n\t- b", indent: false), "- a\n- b")
        XCTAssertEqual(MarkdownTextView.transformIndent(" - a", indent: false), "- a")
        XCTAssertEqual(MarkdownTextView.transformIndent("- a", indent: false), "- a")
        // 空串与二次缩进
        XCTAssertEqual(MarkdownTextView.transformIndent("", indent: true), "")
        XCTAssertEqual(
            MarkdownTextView.transformIndent(MarkdownTextView.transformIndent("- a", indent: true), indent: true),
            "    - a"
        )
    }
}

/// 复现测试：在真实 NSTextView 上执行整块缩进，断言选区保持（VS Code 语义：锚内容、跨度含插入缩进）
final class BlockIndentLiveTests: XCTestCase {

    private func makeTV(_ text: String) -> MarkdownTextView {
        _ = NSApplication.shared
        let tv = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        tv.string = text
        return tv
    }

    private func selectedText(_ tv: MarkdownTextView) -> String {
        (tv.string as NSString).substring(with: tv.selectedRange())
    }

    func testIndentKeepsSelectedContent() {
        let tv = makeTV("AAAA\nBBBB\nCCCC\nDDDD\n")
        let ns = tv.string as NSString
        tv.setSelectedRange(ns.range(of: "BBBB\nCCCC"))
        tv.blockIndent(indent: true)
        XCTAssertEqual(tv.string, "AAAA\n  BBBB\n  CCCC\nDDDD\n", "整块 +2")
        XCTAssertEqual(selectedText(tv), "BBBB\n  CCCC", "选区覆盖整块（含新增缩进）")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 7, length: 11))
        // 再缩一次：选区保持 → 连续嵌套可行
        tv.blockIndent(indent: true)
        XCTAssertEqual(tv.string, "AAAA\n    BBBB\n    CCCC\nDDDD\n")
        XCTAssertEqual(selectedText(tv), "BBBB\n    CCCC")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 9, length: 13))
    }

    func testIndentSelectionAtEOF() {
        let tv = makeTV("AA\nBB")
        let ns = tv.string as NSString
        tv.setSelectedRange(ns.range(of: "BB"))
        tv.blockIndent(indent: true)
        XCTAssertEqual(tv.string, "AA\n  BB")
        XCTAssertEqual(selectedText(tv), "BB")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 5, length: 2))
    }

    /// 多行选区反缩进：曾用「光标行」误替换选区 → 只缩了第一行；此用例锁定修复
    func testOutdentKeepsSelectedContent() {
        let tv = makeTV("AA\n  BB\n  CC\nDD\n")
        let ns = tv.string as NSString
        tv.setSelectedRange(ns.range(of: "  BB\n  CC"))
        tv.blockIndent(indent: false)
        XCTAssertEqual(tv.string, "AA\nBB\nCC\nDD\n", "整块反缩进（原 bug：仅第一行）")
        XCTAssertEqual(selectedText(tv), "BB\nCC")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 3, length: 5))
    }

    func testIndentUnicodeLines() {
        let tv = makeTV("中文行\n😀行\nEMOJI🙂行\n")
        let ns = tv.string as NSString
        tv.setSelectedRange(ns.range(of: "中文行\n😀行"))
        tv.blockIndent(indent: true)
        XCTAssertEqual(tv.string, "  中文行\n  😀行\nEMOJI🙂行\n", "仅选区两行缩进，第三行不动")
        XCTAssertEqual(selectedText(tv), "中文行\n  😀行", "emoji UTF-16 2 单元不偏位")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 2, length: 9))
    }
}

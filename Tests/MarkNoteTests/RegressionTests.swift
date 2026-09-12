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

    /// v5：标记与内容分开（#、** 等走 .marker），标题带级别，表格结构与表头单独成 token。
    func testMarkerHeadingLevelAndTableTokens() {
        let md = """
        ### 三级标题

        **粗体** 与 ~~删除~~

        | 列 A | 列 B |
        | --- | --- |
        | 1 | 2 |
        """
        let tokens = MarkdownHighlighter.tokenize(md)
        func count(_ kind: MDKind) -> Int { tokens.filter { $0.kind == kind }.count }
        XCTAssertGreaterThanOrEqual(count(.marker), 4, "标题 #、**、~~ 都应标成标记")
        XCTAssertEqual(tokens.first { $0.kind == .heading }?.level, 3, "标题应带级别")
        XCTAssertGreaterThanOrEqual(count(.tableCell), 6, "表格竖线应标成单元格结构符")
        XCTAssertEqual(count(.tableSep), 1, "分隔行单独成 token")
        XCTAssertEqual(count(.tableHead), 2, "表头两个单元格")
    }

    /// 回归：编辑器扩展名必须落到 markdown，否则整条语法着色链路会被跳过（曾经的真实 bug）。
    func testEditorExtensionFallsBackToMarkdown() {
        XCTAssertEqual(EditorView.editorExtension(for: nil), "md")
        XCTAssertEqual(EditorView.editorExtension(for: "随手.md"), "md")
        XCTAssertEqual(EditorView.editorExtension(for: "source/code.SWIFT"), "swift")
        XCTAssertTrue(MarkdownEditorView.isMarkdownExt(EditorView.editorExtension(for: nil)),
                      "无扩展名文档必须走 Markdown 着色")
        XCTAssertTrue(MarkdownEditorView.isMarkdownExt(EditorView.editorExtension(for: "笔记")),
                      "无扩展名标题必须走 Markdown 着色")
    }

    /// 回归：嵌套列表的标记必须落在真实位置（曾经把颜色涂到缩进空格上，嵌套列表等于没着色）。

    /// API Key 策略：只存本机、粘贴带空白会被裁掉、掩码不泄露全量。
    func testAPIKeyHandling() {
        let original = UserDefaults.standard.string(forKey: LLM.kAPIKey)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: LLM.kAPIKey) }
            else { UserDefaults.standard.removeObject(forKey: LLM.kAPIKey) }
        }

        LLM.setAPIKey("  sk-test-1234567890abcdef  \n")
        XCTAssertEqual(UserDefaults.standard.string(forKey: LLM.kAPIKey), "sk-test-1234567890abcdef",
                       "粘贴的 key 必须裁掉首尾空白与换行")
        XCTAssertTrue(LLM.configured)
        XCTAssertFalse(LLM.maskedKey.contains("1234567890abcdef"), "设置页只能显示掩码")
        XCTAssertTrue(LLM.maskedKey.hasPrefix("sk-tes"))
        XCTAssertTrue(LLM.maskedKey.hasSuffix("cdef"))

        LLM.setAPIKey("   ")
        XCTAssertFalse(LLM.configured, "空白输入等于清除")
        LLM.setAPIKey("sk-again-1234567890")
        XCTAssertTrue(LLM.configured)
        LLM.clearAPIKey()
        XCTAssertFalse(LLM.configured)
    }
    func testNestedListMarkerRanges() {
        let md = "- 顶层\n  - 嵌套\n    - 更深\n    1. 深层有序\n  > 缩进引用\n"
        let ns = md as NSString
        let tokens = MarkdownHighlighter.tokenize(md)
        let text = { (kind: MDKind) in
            tokens.filter { $0.kind == kind }.map { ns.substring(with: $0.range) }
        }
        XCTAssertEqual(text(.listBullet), ["- ", "- ", "- "], "三层无序列表都要标到标记本身")
        XCTAssertEqual(text(.listNumber), ["1. "])
        XCTAssertEqual(text(.quote), [">"])
    }
}

final class ImagePipelineTests: XCTestCase {
    @MainActor
    func testShortImageReferenceImportsAndResolves() throws {
        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let ref = try XCTUnwrap(store.saveImage(
            Data([0x89, 0x50, 0x4E, 0x47]),
            ext: "png",
            noteID: "note",
            preferredName: "我的 图.png"
        ))
        // 写入按「日期-描述」命名、返回未编码的短相对路径；编码统一由 AssetSyntax.reference 负责
        XCTAssertTrue(ref.hasPrefix("img/"), "短引用前缀，实际：\(ref)")
        XCTAssertTrue(ref.hasSuffix("-我的 图.png"), "日期前缀 + 原描述，实际：\(ref)")
        let saved = try XCTUnwrap(store.resolvedImageURL(for: ref))
        XCTAssertEqual(saved.lastPathComponent, String(ref.dropFirst("img/".count)))
        XCTAssertEqual(saved.deletingLastPathComponent().lastPathComponent, "image")
        // 已编码的引用路径同样能解析（历史文件 / 预览链路）
        let encoded = AssetSyntax.escapePath(ref)
        XCTAssertEqual(store.resolvedImageURL(for: encoded)?.lastPathComponent, saved.lastPathComponent)

        let manualDir = dir.appendingPathComponent("source/img", isDirectory: true)
        try FileManager.default.createDirectory(at: manualDir, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: manualDir.appendingPathComponent("manual.png"))
        XCTAssertEqual(store.resolvedImageURL(for: "manual.png")?.lastPathComponent, "manual.png")
        XCTAssertEqual(store.resolvedImageURL(for: "img/manual.png")?.lastPathComponent, "manual.png")
        XCTAssertEqual(store.resolvedImageURL(for: "source/img/manual.png")?.lastPathComponent, "manual.png")
    }

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

    /// 素材拖拽 / 插入：块级引用（视频 / 音频 / 附件卡）独占整行；行内图片原样。
    func testAssetBlockAlignment() {
        // 行内图片：不做任何包裹
        XCTAssertEqual(MarkdownTextView.blockAligned("![a](img/a.png)", in: "文字", at: 2),
                       "![a](img/a.png)")
        // 块级：两侧都缺换行 → 首尾各补一个
        XCTAssertEqual(MarkdownTextView.blockAligned("<video src=\"a.mp4\" controls></video>",
                                                     in: "上一行", at: 3),
                       "\n<video src=\"a.mp4\" controls></video>\n")
        // 已经在行首、行尾是文末 → 只补尾部
        XCTAssertEqual(MarkdownTextView.blockAligned("@[名](p.pdf)", in: "标题\n", at: 3),
                       "@[名](p.pdf)\n")
        // 前后都已是换行（空行插入）→ 原样
        XCTAssertEqual(MarkdownTextView.blockAligned("<audio src=\"b.mp3\" controls></audio>",
                                                     in: "a\n\nb", at: 2),
                       "<audio src=\"b.mp3\" controls></audio>")
        // 空文档插入 → 只补尾部换行（开头视为行首）
        XCTAssertEqual(MarkdownTextView.blockAligned("<video src=\"v\" controls></video>", in: "", at: 0),
                       "<video src=\"v\" controls></video>\n")
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

import XCTest
import Foundation
@testable import MarkNote

/// 敲代码的交互规则（纯函数部分都在这儿测；UI 里只是调用它们）
final class CodeEditingTests: XCTestCase {

    // MARK: - Tab / 缩进

    func testTabAlignsToNextStop() {
        // C++ 缩进单位 4：行首 0/4 空格 → 补到下一个制表位
        XCTAssertEqual(MarkdownTextView.tabInsertion(beforeCaret: "", unit: 4), "    ")
        XCTAssertEqual(MarkdownTextView.tabInsertion(beforeCaret: "    ", unit: 4), "    ")
        XCTAssertEqual(MarkdownTextView.tabInsertion(beforeCaret: "  ", unit: 4), "  ")
        XCTAssertEqual(MarkdownTextView.tabInsertion(beforeCaret: "      ", unit: 4), "  ")
        // 行首已经不是纯空白（在代码中间按 Tab）→ 插入一个完整单位
        XCTAssertEqual(MarkdownTextView.tabInsertion(beforeCaret: "int a", unit: 4), "    ")
        // HTML/CSS 是 2
        XCTAssertEqual(MarkdownTextView.tabInsertion(beforeCaret: "", unit: 2), "  ")
    }

    func testIndentUnitPerLanguage() {
        XCTAssertEqual(MarkdownEditorView.indentUnit(for: "cpp"), 4)
        XCTAssertEqual(MarkdownEditorView.indentUnit(for: "py"), 4)
        XCTAssertEqual(MarkdownEditorView.indentUnit(for: "go"), 4)
        XCTAssertEqual(MarkdownEditorView.indentUnit(for: "html"), 2)
        XCTAssertEqual(MarkdownEditorView.indentUnit(for: "css"), 4)   // 随手既有规则：CSS 系按 4
        XCTAssertEqual(MarkdownEditorView.indentUnit(for: "json"), 2)
        XCTAssertEqual(MarkdownEditorView.indentUnit(for: "md"), 2)
    }

    func testTransformIndentUsesUnit() {
        let src = "a\n  b\n"
        XCTAssertEqual(MarkdownTextView.transformIndent(src, indent: true, unit: 4), "    a\n      b\n")
        XCTAssertEqual(MarkdownTextView.transformIndent("    a\n  b\n", indent: false, unit: 4), "a\nb\n")
        // 默认仍是 2（老调用点不变）
        XCTAssertEqual(MarkdownTextView.transformIndent("a\n", indent: true), "  a\n")
    }

    // MARK: - 成对符号

    func testWrapSelectionWithPair() {
        XCTAssertEqual(MarkdownTextView.wrapped("x + y", with: "("), "(x + y)")
        XCTAssertEqual(MarkdownTextView.wrapped("key", with: "\""), "\"key\"")
        XCTAssertEqual(MarkdownTextView.wrapped("k", with: "'"), "'k'")
        XCTAssertNil(MarkdownTextView.wrapped("k", with: "x"), "普通字符不做包围")
    }

    func testEmptyPairDeletion() {
        XCTAssertTrue(MarkdownTextView.isDeletablePair(prev: "(", next: ")"))
        XCTAssertTrue(MarkdownTextView.isDeletablePair(prev: "\"", next: "\""))
        XCTAssertFalse(MarkdownTextView.isDeletablePair(prev: "(", next: "]"), "不匹配的括号不能一起删")
        XCTAssertFalse(MarkdownTextView.isDeletablePair(prev: "a", next: "b"))
    }
}

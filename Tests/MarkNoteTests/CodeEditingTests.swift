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

    // MARK: - 代码文件与散文分开对待

    // MARK: - 智能换行（自动补全后的回车）

    // MARK: - 补全规则（对齐 VS Code）

    /// HTML 标签自动闭合只能作用于标记语言：C++ 的 `#include <iostream>` 被补成
    /// `</iostream>` 就是这条规则漏出去的（用户实测报的 bug）。
    func testTagAutoCloseOnlyForMarkup() {
        for ext in ["html", "htm", "xhtml", "xml", "svg", "vue", "svelte", "md", "markdown"] {
            XCTAssertTrue(MarkdownTextView.allowsTagAutoClose(fileExtension: ext),
                          "\(ext) 是标记语言，允许 <tag> 自动补闭合")
        }
        for ext in ["cpp", "c", "h", "hpp", "py", "js", "ts", "go", "rs", "java", "swift", "sh", "json", ""] {
            XCTAssertFalse(MarkdownTextView.allowsTagAutoClose(fileExtension: ext),
                           "\(ext) 里的 <> 不是标签，不能补闭合")
        }
    }

    func testTypeOverAndAutoCloseRules() {
        // 下一个字符就是我要敲的符号 → 越过，不再插入
        XCTAssertTrue(MarkdownTextView.stealsNext(next: "}", typing: "}"))
        XCTAssertTrue(MarkdownTextView.stealsNext(next: "{", typing: "{"))
        XCTAssertTrue(MarkdownTextView.stealsNext(next: "\"", typing: "\""))
        XCTAssertFalse(MarkdownTextView.stealsNext(next: "a", typing: "{"))
        XCTAssertFalse(MarkdownTextView.stealsNext(next: nil, typing: "{"))

        // 后面紧跟单词字符 → 不自动补对（VS Code 规则）
        XCTAssertTrue(MarkdownTextView.shouldAutoClose(next: nil), "行尾要补")
        XCTAssertTrue(MarkdownTextView.shouldAutoClose(next: " "), "空格要补")
        XCTAssertTrue(MarkdownTextView.shouldAutoClose(next: ";"), "符号要补")
        XCTAssertFalse(MarkdownTextView.shouldAutoClose(next: "int"), "后面是单词就不补")
        XCTAssertFalse(MarkdownTextView.shouldAutoClose(next: "9"))
        XCTAssertFalse(MarkdownTextView.shouldAutoClose(next: "_x"))
    }

    func testCommentContinuation() {
        // `// 说明` 回车 → 新行继续 `// `
        XCTAssertEqual(MarkdownTextView.commentContinuation(beforeCaretInLine: "    // 说明",
                                                            indent: "    ", marker: "//"),
                       "\n    // ")
        // 只有注释符（空注释）→ 不续，普通换行
        XCTAssertNil(MarkdownTextView.commentContinuation(beforeCaretInLine: "    //",
                                                          indent: "    ", marker: "//"))
        // 不是注释 → 不续
        XCTAssertNil(MarkdownTextView.commentContinuation(beforeCaretInLine: "    int a = 1;",
                                                          indent: "    ", marker: "//"))
        // Python 注释符
        XCTAssertEqual(MarkdownTextView.commentContinuation(beforeCaretInLine: "  # 步骤一",
                                                            indent: "  ", marker: "#"),
                       "\n  # ")
    }

    func testNewlineInsideAutoClosedPairPushesCloserDown() {
        // VS Code：`{|}` 回车 → 中间缩进一行、闭合符单独一行
        //     {
        //         |
        //     }
        XCTAssertEqual(MarkdownTextView.smartNewline(before: "    {", after: "}", indent: "    ",
                                                     unit: 4, isPython: false),
                       "\n        \n    ")
        let out = try? XCTUnwrap(MarkdownTextView.smartNewline(before: "    int main() {", after: "}",
                                                               indent: "    ", unit: 4, isPython: false))
        XCTAssertEqual(out?.filter { $0 == "}" }.count, 0, "不应该再补一个 }（VS Code 也不补）")
        XCTAssertEqual(MarkdownTextView.smartNewline(before: "x = [", after: "]", indent: "",
                                                     unit: 4, isPython: false), "\n    \n")
        XCTAssertEqual(MarkdownTextView.smartNewline(before: "f(", after: ")", indent: "",
                                                     unit: 4, isPython: false), "\n    \n")
        // 闭合符后面还跟着代码（如 `{});`）→ 不拆行，只缩进
        XCTAssertEqual(MarkdownTextView.smartNewline(before: "f(", after: ");", indent: "",
                                                     unit: 4, isPython: false), "\n    ")
    }

    func testNewlineAfterBareOpenBraceAddsCloser() {
        // 行尾是 `{` 且没有闭合符 → 缩进一级 + 补一行 }（VS Code 行为）
        XCTAssertEqual(MarkdownTextView.smartNewline(before: "if (x) {", after: "",
                                                     indent: "", unit: 4, isPython: false),
                       "\n    \n}")
        // 只有 ( 或 [ 时补缩进即可，不补闭合符
        XCTAssertEqual(MarkdownTextView.smartNewline(before: "while (", after: "", indent: "", unit: 4, isPython: false),
                       "\n    ")
    }

    func testNewlineDedentAndPythonColon() {
        // 整行只剩 } → 回退一级
        XCTAssertEqual(MarkdownTextView.smartNewline(before: "    ", after: "}", indent: "    ", unit: 4, isPython: false),
                       "\n")
        XCTAssertEqual(MarkdownTextView.smartNewline(before: "        ", after: "}", indent: "        ", unit: 4, isPython: false),
                       "\n    ")
        // Python 冒号块缩进一级
        XCTAssertEqual(MarkdownTextView.smartNewline(before: "    if x:", after: "", indent: "    ", unit: 4, isPython: true),
                       "\n        ")
        // 普通行沿用缩进
        XCTAssertEqual(MarkdownTextView.smartNewline(before: "    int a = 1;", after: "", indent: "    ", unit: 4, isPython: false),
                       "\n    ")
    }

    func testCodeFilesAreClassifiedAsCode() {
        XCTAssertTrue(EditorView.isCodeNote("test/1.cpp"))
        XCTAssertTrue(EditorView.isCodeNote("script.py"))
        XCTAssertTrue(EditorView.isCodeNote("web/index.html"))
        XCTAssertTrue(EditorView.isCodeNote("data.json"))
        // 散文类：Markdown 与纯文本仍走「编辑 + 预览」那套
        XCTAssertFalse(EditorView.isCodeNote("note.md"))
        XCTAssertFalse(EditorView.isCodeNote("readme.txt"))
        XCTAssertFalse(EditorView.isCodeNote("run.log"))
        XCTAssertFalse(EditorView.isCodeNote(""))
        XCTAssertFalse(EditorView.isCodeNote(nil))
    }
}

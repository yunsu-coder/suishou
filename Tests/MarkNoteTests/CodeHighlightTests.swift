import XCTest
import Foundation
@testable import MarkNote

final class CodeHighlightTests: XCTestCase {

    func testKeywordAndTypeAndComment() {
        let src = "int main() {\n    // hello\n    return 0;\n}"
        let tokens = CodeHighlighter.tokenize(src)
        func has(_ kind: CodeKind, _ text: String) -> Bool {
            tokens.contains { t in
                t.kind == kind && (src as NSString).substring(with: t.range).contains(text)
            }
        }
        XCTAssertTrue(has(.keyword, "return"))
        XCTAssertTrue(has(.type, "int"))
        XCTAssertTrue(has(.comment, "hello"))
        XCTAssertTrue(has(.number, "0"))
    }

    func testBlockCommentSpansLines() {
        let src = "int a;\n/* start\nstill\nend */\nint b;"
        let tokens = CodeHighlighter.tokenize(src)
        let comments = tokens.filter { $0.kind == .comment }
        XCTAssertGreaterThanOrEqual(comments.count, 2, "跨行块注释应有多段 comment token")
        let joined = comments
            .map { (src as NSString).substring(with: $0.range) }
            .joined(separator: "\n")
        XCTAssertTrue(joined.contains("start"), "块注释含 start")
        XCTAssertTrue(joined.contains("end"), "块注释含 end")
        XCTAssertFalse(joined.contains("int b"), "不应吞掉 int b")
    }

    func testStringNotKeywordInside() {
        let src = "char *s = \"return\";"
        let tokens = CodeHighlighter.tokenize(src)
        let strs = tokens.filter { $0.kind == .string }
        XCTAssertEqual(strs.count, 1)
        let kw = tokens.filter { $0.kind == .keyword }
        XCTAssertFalse(kw.contains { (src as NSString).substring(with: $0.range) == "return" },
                       "字符串内的 return 不当关键字")
    }

    func testBracketMatcherNested() {
        let text = "foo(bar[baz]{q})"
        // 光标在第一个 ( 之后 → 匹配其闭括号
        let openIdx = (text as NSString).range(of: "(").location
        let m = BracketMatcher.match(in: text, at: openIdx + 1)
        XCTAssertNotNil(m)
        let closeText = (text as NSString).substring(with: m!.1)
        XCTAssertEqual(closeText, ")", "应匹配最外层 )")
        // 站在闭括号上
        let closeIdx = (text as NSString).range(of: "q").location - 1   // 定位 { 
        let m2 = BracketMatcher.match(in: text, at: closeIdx + 1)
        XCTAssertNotNil(m2)
        XCTAssertEqual((text as NSString).substring(with: m2!.0), "{")
    }
}

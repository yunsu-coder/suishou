import XCTest
@testable import MarkNote

final class CodeCompletionTests: XCTestCase {

    func testPrefixRange() {
        let ns = "int thr" as NSString
        let r = CodeCompletion.prefixRange(in: ns, at: ns.length)
        XCTAssertEqual(ns.substring(with: r), "thr")
        XCTAssertEqual(r.location, 4)
    }

    func testPrefixRangeStopsAtOperator() {
        let ns = "std::th" as NSString
        let r = CodeCompletion.prefixRange(in: ns, at: ns.length)
        XCTAssertEqual(ns.substring(with: r), "th")
    }

    func testCppCandidatesIncludeThread() {
        let c = CodeCompletion.candidates(prefix: "thr", ext: "cpp", documentWords: [], limit: 10)
        XCTAssertTrue(c.contains("thread"), "C++ 常用库词应包含 thread：\(c)")
    }

    func testDocumentWordsFrequencyOrder() {
        let words = CodeCompletion.documentWords(in: "foo bar foo baz foo qux bar")
        XCTAssertEqual(words.first?.word, "foo")
        XCTAssertEqual(words.first?.count, 3)
        XCTAssertEqual(words.dropFirst().first?.word, "bar")
    }

    func testCandidatesIncludeDocumentWords() {
        let words = CodeCompletion.documentWords(in: "int babyCount = 0; babyCount += 1;")
        let c = CodeCompletion.candidates(prefix: "baby", ext: "c", documentWords: words, limit: 10)
        XCTAssertTrue(c.contains("babyCount"))
    }

    func testLspPosition() {
        let ns = "ab\ncd\nef" as NSString
        let p0 = CodeCompletion.lspPosition(in: ns, at: 0)
        XCTAssertEqual(p0.line, 0)
        XCTAssertEqual(p0.character, 0)
        let p1 = CodeCompletion.lspPosition(in: ns, at: 4)
        XCTAssertEqual(p1.line, 1)
        XCTAssertEqual(p1.character, 1)
        let p2 = CodeCompletion.lspPosition(in: ns, at: ns.length)
        XCTAssertEqual(p2.line, 2)
        XCTAssertEqual(p2.character, 2)
    }
}

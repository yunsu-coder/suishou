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
        let joined = comments
            .map { (src as NSString).substring(with: $0.range) }
            .joined(separator: "\n")
        XCTAssertTrue(joined.contains("start"), "块注释含 start")
        XCTAssertTrue(joined.contains("end"), "块注释含 end")
        XCTAssertFalse(joined.contains("int b"), "不应吞掉 int b")
    }

    // MARK: - 多语言原生着色（专业文件类型）

    private func tokens(_ src: String, ext: String) -> [(CodeKind, String)] {
        let ns = src as NSString
        return CodeHighlighter.tokenize(src, language: CodeLanguage.of(ext: ext))
            .map { ($0.kind, ns.substring(with: $0.range)) }
    }

    private func has(_ list: [(CodeKind, String)], _ kind: CodeKind, _ text: String) -> Bool {
        list.contains { $0.0 == kind && $0.1.contains(text) }
    }

    func testLanguageDetection() {
        XCTAssertEqual(CodeLanguage.of(ext: "cpp"), .cFamily)
        XCTAssertEqual(CodeLanguage.of(ext: "c"), .cFamily)
        XCTAssertEqual(CodeLanguage.of(ext: "h"), .cFamily)
        XCTAssertEqual(CodeLanguage.of(ext: "py"), .python)
        XCTAssertEqual(CodeLanguage.of(ext: "go"), .go)
        XCTAssertEqual(CodeLanguage.of(ext: "js"), .javascript)
        XCTAssertEqual(CodeLanguage.of(ext: "ts"), .typescript)
        XCTAssertEqual(CodeLanguage.of(ext: "html"), .markup)
        XCTAssertEqual(CodeLanguage.of(ext: "css"), .css)
        XCTAssertEqual(CodeLanguage.of(ext: "txt"), .plain)
    }

    func testCppNativeHighlighting() {
        let src = """
        #include <iostream>
        std::vector<int> v;   // 注释
        int main() {
            const char* s = "hello";
            return 0;
        }
        """
        let t = tokens(src, ext: "cpp")
        XCTAssertTrue(has(t, .preproc, "#include"), "预处理指令")
        XCTAssertTrue(has(t, .type, "vector"), "STL 类型")
        XCTAssertTrue(has(t, .type, "int"))
        XCTAssertTrue(has(t, .comment, "注释"))
        XCTAssertTrue(has(t, .string, "hello"))
        XCTAssertTrue(has(t, .keyword, "const"))
        XCTAssertTrue(has(t, .keyword, "return"))
        XCTAssertTrue(has(t, .function, "main"))
        XCTAssertTrue(has(t, .number, "0"))
    }

    func testPythonNativeHighlighting() {
        let src = """
        # 顶部注释
        @app.route("/")
        def greet(name):
            \"\"\"多行
            docstring\"\"\"
            msg = f"hi {name}"
            if name is None:
                return True
            return len(name)
        """
        let t = tokens(src, ext: "py")
        XCTAssertTrue(has(t, .comment, "顶部注释"), "# 注释")
        XCTAssertTrue(has(t, .preproc, "@app.route"), "@ 装饰器")
        XCTAssertTrue(has(t, .keyword, "def"))
        XCTAssertTrue(has(t, .function, "greet"), "def 后面的函数名")
        XCTAssertTrue(has(t, .string, "docstring"), "三引号 docstring（可跨行）")
        XCTAssertTrue(has(t, .constant, "None"), "None 常量")
        XCTAssertTrue(has(t, .constant, "True"))
        XCTAssertFalse(has(t, .keyword, "def greet"), "def 与函数名应分开着色")
    }

    func testGoNativeHighlighting() {
        let src = """
        package main

        import "fmt"

        func main() {
            raw := `多行
        原始串`
            n := len(raw) // 注释
            if n > 0 {
                fmt.Println(n)
            }
        }
        """
        let t = tokens(src, ext: "go")
        XCTAssertTrue(has(t, .keyword, "package"))
        XCTAssertTrue(has(t, .keyword, "func"))
        XCTAssertTrue(has(t, .function, "main"))
        XCTAssertTrue(has(t, .string, "fmt"), "import 的字符串")
        XCTAssertTrue(has(t, .string, "原始串"), "反引号原始串（可跨行）")
        XCTAssertTrue(has(t, .comment, "注释"))
        XCTAssertTrue(has(t, .number, "0"))
    }

    func testJavaScriptAndTypeScriptHighlighting() {
        let js = """
        // 注释
        const el = `模板 ${name}`;
        function run(a) { return a * 2; }
        """
        let t = tokens(js, ext: "js")
        XCTAssertTrue(has(t, .comment, "注释"))
        XCTAssertTrue(has(t, .keyword, "const"))
        XCTAssertTrue(has(t, .keyword, "function"))
        XCTAssertTrue(has(t, .function, "run"))
        XCTAssertTrue(has(t, .string, "模板"))
        XCTAssertTrue(has(t, .keyword, "return"))

        let ts = """
        interface User { id: number; name: string }
        export async function load(id: number): Promise<User> { return null; }
        """
        let tt = tokens(ts, ext: "ts")
        XCTAssertTrue(has(tt, .keyword, "interface"))
        XCTAssertTrue(has(tt, .keyword, "export"))
        XCTAssertTrue(has(tt, .keyword, "async"))
        XCTAssertTrue(has(tt, .type, "number"))
        XCTAssertTrue(has(tt, .type, "string"))
        XCTAssertTrue(has(tt, .type, "Promise"))
        XCTAssertTrue(has(tt, .function, "load"))
        XCTAssertTrue(has(tt, .constant, "null"))
    }

    func testHTMLNativeHighlighting() {
        let src = """
        <!DOCTYPE html>
        <div class="card" id='main'>
          <!-- 注释 -->
          <span>文本</span>
        </div>
        <script>const n = 1;</script>
        """
        let t = tokens(src, ext: "html")
        XCTAssertTrue(has(t, .preproc, "DOCTYPE"))
        XCTAssertTrue(has(t, .tag, "div"))
        XCTAssertTrue(has(t, .tag, "span"))
        XCTAssertTrue(has(t, .property, "class"))
        XCTAssertTrue(has(t, .property, "id"))
        XCTAssertTrue(has(t, .string, "card"))
        XCTAssertTrue(has(t, .comment, "注释"))
        XCTAssertTrue(has(t, .keyword, "const"), "内联 <script> 走 JS 着色")
        XCTAssertTrue(has(t, .number, "1"))
    }

    func testCSSNativeHighlighting() {
        let src = """
        /* 注释 */
        @media screen and (max-width: 600px) {
          .card { color: #ff0000; padding: 8px; display: flex; }
        }
        """
        let t = tokens(src, ext: "css")
        XCTAssertTrue(has(t, .comment, "注释"))
        XCTAssertTrue(has(t, .preproc, "@media"))
        XCTAssertTrue(has(t, .tag, ".card"))
        XCTAssertTrue(has(t, .property, "color"))
        XCTAssertTrue(has(t, .property, "padding"))
        XCTAssertTrue(has(t, .property, "display"))
        XCTAssertTrue(has(t, .number, "#ff0000"), "颜色值")
        XCTAssertTrue(has(t, .number, "8px"), "带单位的数值")
        XCTAssertTrue(has(t, .constant, "flex"), "值关键字")
    }

    // MARK: - 配色细化（2026-10-04 完善）

    func testCppIncludeAngleBracketsAreString() {
        let src = "#include <vector>\n#include \"local.h\"\n"
        let t = tokens(src, ext: "cpp")
        XCTAssertTrue(has(t, .preproc, "#include"), "#include 走预处理色")
        XCTAssertTrue(has(t, .string, "<vector>"), "尖括号头文件名走字符串色")
        XCTAssertTrue(has(t, .string, "\"local.h\""), "引号头文件名还是字符串色")
    }

    func testTypeNameAfterClassKeyword() {
        let src = """
        class Widget : public Base {};
        struct Point { int x; };
        enum Color { Red, Green };
        """
        let t = tokens(src, ext: "cpp")
        XCTAssertTrue(has(t, .keyword, "class"))
        XCTAssertTrue(has(t, .type, "Widget"), "class 后面的名字按类型上色")
        XCTAssertTrue(has(t, .type, "Point"), "struct 后面的名字按类型上色")
        XCTAssertTrue(has(t, .type, "Color"), "enum 后面的名字按类型上色")

        let py = tokens("class Greeter:\n    pass\n", ext: "py")
        XCTAssertTrue(has(py, .type, "Greeter"), "Python class 名同理")
        let ts = tokens("interface User { id: number }\n", ext: "ts")
        XCTAssertTrue(has(ts, .type, "User"), "TS interface 名同理")
    }

    func testStringEscapesAreHighlighted() {
        let src = "const char* s = \"line\\n\\t\\\"q\\\" \\u00e9\";"
        let t = tokens(src, ext: "cpp")
        XCTAssertTrue(has(t, .string, "line"), "整串还是字符串色")
        XCTAssertTrue(has(t, .escape, "\\n"), "\\n 单独上色")
        XCTAssertTrue(has(t, .escape, "\\t"), "\\t 单独上色")
        XCTAssertTrue(has(t, .escape, "\\u00e9"), "\\uXXXX 整体上色")

        let py = tokens("s = f\"a\\nb\"\n", ext: "py")
        XCTAssertTrue(has(py, .escape, "\\n"), "Python 字符串里的转义同样上色")
    }

    /// 大文件不能把输入卡死：40 万字符内单遍扫描要够快（后台队列跑，这里给宽松上限）
    func testLargeFileTokenizePerformance() {
        let unit = "int add(int a, int b) { return a + b; }  // 注释\n"
        let src = String(repeating: unit, count: 8_000)       // ≈ 37 万字符（编辑器着色上限 40 万）
        let start = Date()
        let t = CodeHighlighter.tokenize(src, language: .cFamily)
        let cost = Date().timeIntervalSince(start)
        XCTAssertFalse(t.isEmpty)
        XCTAssertLessThan(cost, 3.0, "40 万字符扫描耗时 \(cost)s")
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

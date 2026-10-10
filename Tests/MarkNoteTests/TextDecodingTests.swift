import XCTest
import Foundation
@testable import MarkNote

/// 文本解码：UTF-8 / GB18030 / UTF-16 都要能正确还原中文，
/// 且**不再**出现 U+FFFD（界面上那些"菱形问号"）。
final class TextDecodingTests: XCTestCase {

    func testUTF8WithAndWithoutBOM() {
        let s = "// 中文注释 counter(0);"
        let data = Data(s.utf8)
        XCTAssertEqual(TextDecoding.string(from: data), s)
        var bom = Data([0xEF, 0xBB, 0xBF])
        bom.append(data)
        XCTAssertEqual(TextDecoding.string(from: bom), s, "BOM 要被剥掉")
    }

    func testGB18030DecodesToChineseNotMojibake() throws {
        let s = "// 步骤：启动线程，等待结束"
        // 用系统编码把中文编成 GB18030 字节（Windows 记事本/老工具常见）
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let data = try XCTUnwrap(s.data(using: gb))
        XCTAssertNil(String(data: data, encoding: .utf8), "前提：这段字节不是合法 UTF-8")
        let decoded = try XCTUnwrap(TextDecoding.string(from: data))
        XCTAssertEqual(decoded, s, "应按 GB18030 还原成中文，而不是乱码")
        XCTAssertFalse(TextDecoding.looksCorrupted(decoded), "不该出现 U+FFFD")
    }

    func testUTF16Decodes() throws {
        let s = "// UTF-16 的中文"
        let data = try XCTUnwrap(s.data(using: .utf16))
        XCTAssertEqual(TextDecoding.string(from: data), s)
    }

    func testCorruptedTextIsDetected() {
        XCTAssertFalse(TextDecoding.looksCorrupted("正常中文 // ok"))
        XCTAssertTrue(TextDecoding.looksCorrupted("// \u{FFFD}\u{FFFD}\u{FFFD}"), "含替换字符应被识别为坏文本")
    }
}

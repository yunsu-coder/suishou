import XCTest
import AppKit
@testable import MarkNote

/// 文件类型外观：文件树 / 标签页 / 状态栏共用同一套（图标槽位、语言色、扩展名标签）
final class FileTypeStyleTests: XCTestCase {

    func testExtensionLabelForTabs() {
        XCTAssertEqual(FileTypeStyle.extensionLabel(for: "test/1.cpp"), "CPP")
        XCTAssertEqual(FileTypeStyle.extensionLabel(for: "web/index.html"), "HTML")
        XCTAssertEqual(FileTypeStyle.extensionLabel(for: "a.MD"), "MD", "大小写统一成大写显示")
        XCTAssertNil(FileTypeStyle.extensionLabel(for: "README"), "没有扩展名就不显示标签")
    }

    func testThemeIconKeyAndFallbackSymbol() {
        XCTAssertEqual(FileTypeStyle.themeIconKey(for: "cpp"), "file.cpp")
        XCTAssertEqual(FileTypeStyle.themeIconKey(for: "py"), "file.python")
        XCTAssertEqual(FileTypeStyle.symbol(for: "cpp"), Workspace.fileSymbol(for: "cpp"))
    }

    func testLanguageTintsDiffer() {
        let cpp = FileTypeStyle.tint(for: "cpp")
        let py = FileTypeStyle.tint(for: "py")
        let md = FileTypeStyle.tint(for: "md")
        XCTAssertNotEqual(cpp, py, "不同语言要有不同兜底色")
        XCTAssertNotEqual(cpp, md)
        // 兜底色不能是系统次要色（说明映射没命中）
        XCTAssertNotEqual(cpp, NSColor.secondaryLabelColor)
        XCTAssertNotEqual(FileTypeStyle.tint(for: "xyz"), NSColor.secondaryLabelColor,
                          "每种扩展名都要有兜底色（未知类型走 file.other）")
    }
}

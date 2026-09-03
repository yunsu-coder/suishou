import XCTest
import Foundation
@testable import MarkNote

final class L10nTests: XCTestCase {
    func testLanguageSwitch() {
        UserDefaults.standard.set("zh", forKey: "appLanguage")
        XCTAssertEqual(_L("工作台", "Workspace"), "工作台")
        UserDefaults.standard.set("en", forKey: "appLanguage")
        XCTAssertEqual(_L("工作台", "Workspace"), "Workspace")
        // system 跟随偏好（测试环境通常 en）
        UserDefaults.standard.set("system", forKey: "appLanguage")
        let expected = Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "工作台" : "Workspace"
        XCTAssertEqual(_L("工作台", "Workspace"), expected)
        UserDefaults.standard.set("zh", forKey: "appLanguage")
    }
}

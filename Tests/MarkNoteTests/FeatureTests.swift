import XCTest
import Foundation
@testable import MarkNote

final class FeatureTests: XCTestCase {
    func testDefaultsAllOn() {
        for (id, _, _) in FeatureModules.all {
            UserDefaults.standard.removeObject(forKey: "featureModule.\(id)")
            XCTAssertTrue(FeatureModules.isEnabled(id), "缺省应开启：\(id)")
        }
    }

    func testSetAndGet() {
        FeatureModules.setEnabled("exportPDF", false)
        XCTAssertFalse(FeatureModules.isEnabled("exportPDF"))
        FeatureModules.setEnabled("exportPDF", true)
        XCTAssertTrue(FeatureModules.isEnabled("exportPDF"))
    }
}

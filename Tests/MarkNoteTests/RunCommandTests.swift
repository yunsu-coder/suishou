import XCTest
@testable import MarkNote

final class RunCommandTests: XCTestCase {
    func testCanRunCoversCommonLanguages() {
        XCTAssertTrue(RunCommand.canRun(ext: "cpp"))
        XCTAssertTrue(RunCommand.canRun(ext: "py"))
        XCTAssertTrue(RunCommand.canRun(ext: "go"))
        XCTAssertTrue(RunCommand.canRun(ext: "swift"))
        XCTAssertFalse(RunCommand.canRun(ext: "md"))
        XCTAssertFalse(RunCommand.canRun(ext: "png"))
    }
}

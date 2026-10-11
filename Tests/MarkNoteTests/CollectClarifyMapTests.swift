import XCTest
@testable import MarkNote

/// 追问回答 → 需求字段（结构化直落）与「分辨率底线」硬规则
final class CollectClarifyMapTests: XCTestCase {

    func testApplyAnswersMapsMinSize() {
        var r = CollectRequest()
        CollectorClarify.applyAnswers([(field: "minSize", question: "?", answer: "至少 2K")], to: &r)
        XCTAssertEqual(r.minSize, CollectMinSize.qhd1440.rawValue)
        CollectorClarify.applyAnswers([(field: "minSize", question: "?", answer: "越大越好（原图优先）")], to: &r)
        XCTAssertEqual(r.minSize, CollectMinSize.uhd2160.rawValue)
        CollectorClarify.applyAnswers([(field: "minSize", question: "?", answer: "不限，能用就行")], to: &r)
        XCTAssertEqual(r.minSize, CollectMinSize.any.rawValue)
    }

    func testApplyAnswersMapsOrientation() {
        var r = CollectRequest()
        CollectorClarify.applyAnswers([(field: "orientation", question: "?", answer: "竖图")], to: &r)
        XCTAssertEqual(r.orientation, CollectOrientation.portrait.rawValue)
    }

    func testImageMissingMinSizeIsAsked() {
        var r = CollectRequest()
        r.kind = "image"
        r.subject = "猫"
        r.usage = "笔记封面"
        r.orientation = CollectOrientation.landscape.rawValue
        let gaps = CollectorClarify.missingKeyFields(r)
        XCTAssertTrue(gaps.contains { $0.field == "minSize" },
                      "图片分辨率底线应被追问：\(gaps.map(\.field))")
    }
}

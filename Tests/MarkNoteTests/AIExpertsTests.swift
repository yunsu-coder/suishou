import XCTest
import Foundation
@testable import MarkNote

final class AIExpertsTests: XCTestCase {

    func testAtLeastTenExpertsWithUniqueIdsAndPrompts() {
        XCTAssertGreaterThanOrEqual(AIExperts.all.count, 10, "预设专家应 ≥ 10 位")
        let ids = AIExperts.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "专家 id 必须唯一")
        for e in AIExperts.all {
            XCTAssertFalse(e.name.isEmpty)
            XCTAssertFalse(e.system.isEmpty, "\(e.id) 缺少系统提示词")
        }
        // byID 兜底：找不到回退首位
        XCTAssertEqual(AIExperts.byID("不存在"), AIExperts.all[0])
    }

    func testQuickActionsComplete() {
        let raws = AIQuickAction.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count, "快捷操作标识唯一")
        for a in AIQuickAction.allCases {
            XCTAssertFalse(a.title.isEmpty)
            XCTAssertGreaterThan(a.systemPrompt.count, 20)
            XCTAssertTrue((0.0...1.0).contains(a.temperature))
        }
    }

    func testQuickActionPromptsDistinct() {
        let prompts = AIQuickAction.allCases.map(\.systemPrompt)
        XCTAssertEqual(Set(prompts).count, prompts.count, "翻译/改写/润色提示词应互不相同")
    }
}

import XCTest
@testable import MarkNote

/// 采集相关度：装饰图剔除 + 标题不沾边的剔除 + 有词元的排序
final class CollectRelevanceTests: XCTestCase {

    private func cand(_ title: String, _ url: String, kind: String = "image") -> CollectCandidate {
        CollectCandidate(id: url, kind: kind, title: title,
                         thumbURL: nil, fullURL: URL(string: url), pageURL: nil, duration: nil)
    }

    func testJunkIsDropped() {
        let list = [cand("site logo", "https://a.com/logo.png"),
                    cand("猫咪壁纸", "https://a.com/cat.jpg")]
        let refined = CollectRelevance.refine(list, query: "猫")
        XCTAssertEqual(refined.count, 1)
        XCTAssertTrue(refined[0].title.contains("猫"))
    }

    func testIrrelevantTitledItemsAreDropped() {
        let list = [cand("王者荣耀攻略", "https://a.com/wzry.jpg"),
                    cand("可爱猫咪", "https://a.com/cat.jpg")]
        let refined = CollectRelevance.refine(list, query: "猫咪")
        XCTAssertEqual(refined.map(\.title), ["可爱猫咪"])
    }

    func testUntitledItemsAreKeptAndRankedLast() {
        let list = [cand("可爱猫咪", "https://a.com/cat.jpg"),
                    cand("", "https://a.com/unknown.jpg")]
        let refined = CollectRelevance.refine(list, query: "猫咪")
        XCTAssertEqual(refined.count, 2)
        XCTAssertEqual(refined.first?.title, "可爱猫咪")
    }

    func testSingleCharQueryDoesNotOverFilter() {
        // 单个汉字成不了词元 → 不过筛（避免误杀一大片）
        let list = [cand("任何东西", "https://a.com/x.jpg")]
        XCTAssertEqual(CollectRelevance.refine(list, query: "猫").count, 1)
    }
}

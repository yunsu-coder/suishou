import XCTest
import Foundation
@testable import MarkNote

/// 采集图片质量：能拿原图就别拿缩略图；同图不同尺寸按原图判重
final class CollectImageQualityTests: XCTestCase {

    private func up(_ s: String) -> String {
        CollectImageQuality.upgrade(URL(string: s)!).absoluteString
    }

    func testTwitterUpgradesToOrig() {
        XCTAssertEqual(up("https://pbs.twimg.com/media/ABC123?format=jpg&name=small"),
                       "https://pbs.twimg.com/media/ABC123?format=jpg&name=orig")
        XCTAssertEqual(up("https://pbs.twimg.com/media/ABC123?format=jpg&name=900x900&w=300"),
                       "https://pbs.twimg.com/media/ABC123?format=jpg&name=orig")
    }

    func testWeiboSmallDirsBecomeLarge() {
        XCTAssertEqual(up("https://wx1.sinaimg.cn/thumb150/abc.jpg"),
                       "https://wx1.sinaimg.cn/large/abc.jpg")
        XCTAssertEqual(up("https://wx1.sinaimg.cn/mw690/abc.jpg"),
                       "https://wx1.sinaimg.cn/large/abc.jpg")
        XCTAssertEqual(up("https://wx1.sinaimg.cn/orj360/abc.jpg"),
                       "https://wx1.sinaimg.cn/large/abc.jpg")
        XCTAssertEqual(up("https://wx1.sinaimg.cn/large/abc.jpg"),
                       "https://wx1.sinaimg.cn/large/abc.jpg", "已经是 large 就别动")
    }

    func testCosmeticQueryParamsAreDropped() {
        XCTAssertEqual(up("https://img.example.com/a.jpg?w=200&h=200&quality=60&keep=1"),
                       "https://img.example.com/a.jpg?keep=1")
        XCTAssertEqual(up("https://img.example.com/a.jpg?x-oss-process=image/resize,w_200"),
                       "https://img.example.com/a.jpg")
        // 签名参数必须保留（去掉了就取不到图）
        XCTAssertEqual(up("https://img.example.com/a.jpg?x-expires=123&x-signature=abc&w=100"),
                       "https://img.example.com/a.jpg?x-expires=123&x-signature=abc")
    }

    func testSizeSuffixIsStripped() {
        XCTAssertEqual(up("https://cdn.example.com/pic@300w.webp"), "https://cdn.example.com/pic")
        XCTAssertEqual(up("https://cdn.example.com/pic@720w_1e_1c.jpg"), "https://cdn.example.com/pic")
        XCTAssertEqual(up("https://cdn.example.com/pic~300x300.image"), "https://cdn.example.com/pic")
        XCTAssertEqual(up("https://cdn.example.com/pic.jpg"), "https://cdn.example.com/pic.jpg",
                       "正常文件名不动")
    }

    func testIdentityDedupesSameImageAtDifferentSizes() {
        let a = URL(string: "https://pbs.twimg.com/media/ABC?format=jpg&name=small")!
        let b = URL(string: "https://pbs.twimg.com/media/ABC?format=jpg&name=900x900")!
        XCTAssertEqual(CollectImageQuality.identity(for: a), CollectImageQuality.identity(for: b),
                       "同图不同尺寸应判为同一张")
        let c = URL(string: "https://cdn.example.com/pic@300w.webp")!
        let d = URL(string: "https://cdn.example.com/pic")!
        XCTAssertEqual(CollectImageQuality.identity(for: c), CollectImageQuality.identity(for: d))
    }
}

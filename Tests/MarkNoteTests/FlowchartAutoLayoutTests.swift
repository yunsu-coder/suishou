import XCTest
import Foundation
@testable import MarkNote

/// 流程图自动布局：编给 dagre 的图数据要正确（悬空边过滤、尺寸带上），
/// 以及真跑一次 dagre 后节点坐标应当分层排开（纵向布局时 y 随层级递增）。
final class FlowchartAutoLayoutTests: XCTestCase {

    private func doc() -> FCDocument {
        var d = FCDocument()
        var a = FCNode(kind: .roundedRect, text: "开始")
        a.id = "A"
        var b = FCNode(kind: .rect, text: "处理")
        b.id = "B"
        var c = FCNode(kind: .diamond, text: "判断")
        c.id = "C"
        var dangling = FCNode(kind: .roundedRect, text: "孤立")
        dangling.id = "D"
        d.nodes = [a, b, c, dangling]
        d.edges = [FCEdge(fromNode: "A", toNode: "B"),
                   FCEdge(fromNode: "B", toNode: "C"),
                   FCEdge(fromNode: "C", toNode: "A"),      // 环：dagre 也要能吃
                   FCEdge(fromNode: "B", toNode: "NOPE")]   // 悬空：应被过滤
        return d
    }

    func testGraphPayloadFiltersDanglingEdgesAndKeepsSizes() throws {
        let json = FlowchartAutoLayout.graphPayload(doc(), direction: .topBottom)
        let data = try XCTUnwrap(json.data(using: .utf8))
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let nodes = try XCTUnwrap(obj["nodes"] as? [[String: Any]])
        let edges = try XCTUnwrap(obj["edges"] as? [[String: Any]])
        XCTAssertEqual(nodes.count, 4, "四个节点都该在")
        XCTAssertEqual(edges.count, 3, "指向不存在节点的边要被过滤")
        XCTAssertEqual(obj["rankdir"] as? String, "TB")
        XCTAssertTrue(nodes.allSatisfy { ($0["width"] as? Double ?? 0) > 0 && ($0["height"] as? Double ?? 0) > 0 },
                      "每个节点都要带尺寸，dagre 才能分层")
        XCTAssertFalse(edges.contains { ($0["w"] as? String) == "NOPE" })
    }

    /// 真跑 dagre（隐藏 WebView + 随包脚本）：纵向布局里 A 应该在 B 上方、B 在 C 上方
    @MainActor
    func testDagreLaysOutLayersVertically() async throws {
        let positions = await FlowchartAutoLayout.layout(doc(), direction: .topBottom)
        let p = try XCTUnwrap(positions, "dagre 应当返回坐标（没返回说明隐藏 WebView 或脚本没加载成功）")
        XCTAssertEqual(p.count, 4)
        let a = try XCTUnwrap(p["A"]), b = try XCTUnwrap(p["B"]), c = try XCTUnwrap(p["C"])
        XCTAssertLessThan(a.y, b.y, "A 应在 B 上方（y 更小）")
        XCTAssertLessThan(b.y, c.y, "B 应在 C 上方")
    }
}

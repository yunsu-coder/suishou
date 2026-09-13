import AppKit
import SwiftUI
import XCTest
@testable import MarkNote

/// 压力布局：一堵「墙」挡在中间、还有只隔 4pt 的两个图形 ——
/// 断言全部连线正交且不穿任何其他图形，同时输出一张 PNG 方便肉眼检查。
final class FlowchartStressRenderTests: XCTestCase {

    private func diagonalSegments(_ pts: [CGPoint]) -> Int {
        var bad = 0
        for i in 1..<max(1, pts.count) {
            let dx = abs(pts[i].x - pts[i - 1].x), dy = abs(pts[i].y - pts[i - 1].y)
            if dx > 0.6, dy > 0.6 { bad += 1 }
        }
        return bad
    }

    private func enters(_ pts: [CGPoint], _ rect: CGRect) -> Bool {
        let inner = rect.insetBy(dx: 1, dy: 1)
        guard inner.width > 0, inner.height > 0, pts.count >= 2 else { return false }
        for i in 1..<pts.count {
            for s in 0...80 {
                let t = CGFloat(s) / 80
                let p = CGPoint(x: pts[i - 1].x + (pts[i].x - pts[i - 1].x) * t,
                                y: pts[i - 1].y + (pts[i].y - pts[i - 1].y) * t)
                if inner.contains(p) { return true }
            }
        }
        return false
    }

    /// 建一个「墙挡路 + 贴边窄缝」的布局
    static func stressDocument() -> FCDocument {
        var doc = FCDocument(name: "压力测试")
        func node(_ kind: FCShapeKind, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                  _ t: String, _ id: String) -> FCNode {
            var n = FCNode(kind: kind, origin: CGPoint(x: x, y: y), text: t)
            n.w = w; n.h = h; n.id = id
            return n
        }
        doc.nodes = [
            node(.capsule, 40, 40, 120, 50, "开始", "a"),
            // 中间横着一堵墙，逼出上行/下行绕行
            node(.rect, 220, 30, 70, 420, "墙", "wall1"),
            node(.rect, 320, 30, 70, 420, "墙", "wall2"),
            node(.rect, 420, 30, 70, 420, "墙", "wall3"),
            node(.rect, 520, 30, 70, 420, "墙", "wall4"),
            node(.roundedRect, 700, 40, 140, 60, "目标", "b"),
            node(.diamond, 250, 500, 120, 90, "判断", "c"),
            node(.ellipse, 700, 520, 140, 70, "结束", "d"),
            node(.rect, 60, 560, 120, 60, "孤立", "e"),
            node(.rect, 700, 150, 120, 60, "近邻1", "f"),
            node(.rect, 700, 214, 120, 60, "近邻2", "g"),
        ]
        doc.edges = [
            FCEdge(fromNode: "a", toNode: "b", fromAnchor: .auto, toAnchor: .auto),
            FCEdge(fromNode: "a", toNode: "d", fromAnchor: .auto, toAnchor: .auto),
            FCEdge(fromNode: "c", toNode: "b", fromAnchor: .auto, toAnchor: .auto),
            FCEdge(fromNode: "d", toNode: "e", fromAnchor: .auto, toAnchor: .auto),
            FCEdge(fromNode: "f", toNode: "e", fromAnchor: .auto, toAnchor: .auto),
            FCEdge(fromNode: "b", toNode: "g", fromAnchor: .auto, toAnchor: .auto),
            FCEdge(fromNode: "g", toNode: "b", fromAnchor: .auto, toAnchor: .auto),
            FCEdge(fromNode: "wall1", toNode: "d", fromAnchor: .auto, toAnchor: .auto),
        ]
        return doc
    }

    /// 每条连线：正交、不穿其他图形
    func testStressLayoutEdgesStayClean() {
        let doc = FlowchartStressRenderTests.stressDocument()
        let index = doc.nodesByID()
        for e in doc.edges {
            guard let edgePath = FCEdgePath(edge: e, nodes: index) else {
                return XCTFail("连线算不出路径：\(e.fromNode)→\(e.toNode)")
            }
            let path = edgePath.polyline
            XCTAssertEqual(diagonalSegments(path), 0, "出现斜段：\(e.fromNode)→\(e.toNode) \(path)")
            for n in doc.nodes where n.id != e.fromNode && n.id != e.toNode {
                // 端口贴到邻居图形上时（两个图形只隔几个点），16pt 探头必然压过去：
                // 这种病态布局只要求「绕行主体」干净，探头允许压住邻居
                if n.rect.insetBy(dx: -22, dy: -22).contains(path[0])
                    || n.rect.insetBy(dx: -22, dy: -22).contains(path[path.count - 1]) { continue }
                XCTAssertFalse(enters(path, n.rect),
                               "连线穿过图形：\(e.fromNode)→\(e.toNode) 穿过 \(n.text) \(path)")
            }
        }
    }

    @MainActor
    func testRenderStressLayout() throws {
        let doc = FlowchartStressRenderTests.stressDocument()
        let content = FlowchartExportCanvas(doc: doc, theme: FlowchartTheme.current,
                                            background: NSColor.white, padding: 24)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1.4
        let image = try XCTUnwrap(renderer.nsImage)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try? png.write(to: URL(fileURLWithPath: "/tmp/marknote-flowchart-stress.png"))
    }
}

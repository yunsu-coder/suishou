import CoreGraphics
import XCTest
@testable import MarkNote

/// 连线路由的属性测试（固定种子，确定性回归）：
/// 随机画一堆互不重叠的图形 + 一条连线，逐个断言路由输出的硬性不变量。
final class FlowchartRouterPropertyTests: XCTestCase {

    /// SplitMix64：固定种子 → 样本固定，测试不漂移
    private struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// 随机布局：所有图形两两不重叠且至少留 24pt 间距（真实画布的常见形态）
    private func randomDoc(_ rng: inout SeededRNG) -> FCDocument {
        var doc = FCDocument()
        var nodes: [FCNode] = []
        let target = Int.random(in: 2...5, using: &rng)
        var guardCount = 0
        while nodes.count < target, guardCount < 300 {
            guardCount += 1
            var n = FCNode(kind: .rect,
                           origin: CGPoint(x: Int.random(in: 0...900, using: &rng),
                                           y: Int.random(in: 0...700, using: &rng)))
            n.w = CGFloat(Int.random(in: 60...180, using: &rng))
            n.h = CGFloat(Int.random(in: 40...120, using: &rng))
            if nodes.contains(where: { n.rect.insetBy(dx: -24, dy: -24).intersects($0.rect) }) { continue }
            nodes.append(n)
        }
        doc.nodes = nodes
        return doc
    }

    private func diagonalSegments(_ pts: [CGPoint]) -> Int {
        var bad = 0
        for i in 1..<max(1, pts.count) {
            let dx = abs(pts[i].x - pts[i - 1].x), dy = abs(pts[i].y - pts[i - 1].y)
            if dx > 0.6, dy > 0.6 { bad += 1 }
        }
        return bad
    }

    /// 折线是否进入某矩形内部（严格内部，留 1pt 容差）
    private func enters(_ pts: [CGPoint], _ rect: CGRect) -> Bool {
        let inner = rect.insetBy(dx: 1, dy: 1)
        guard inner.width > 0, inner.height > 0 else { return false }
        guard pts.count >= 2 else { return inner.contains(pts[0]) }
        for i in 1..<pts.count {
            let steps = 80
            for s in 0...steps {
                let t = CGFloat(s) / CGFloat(steps)
                let p = CGPoint(x: pts[i - 1].x + (pts[i].x - pts[i - 1].x) * t,
                                y: pts[i - 1].y + (pts[i].y - pts[i - 1].y) * t)
                if inner.contains(p) { return true }
            }
        }
        return false
    }

    /// 400 个随机布局 × 连线：正交 / 端点 / 不穿源目标 / 不穿障碍 / 探头方向
    func testRouterPropertiesAcrossRandomLayouts() {
        var rng = SeededRNG(seed: 20260913)
        var checked = 0
        for _ in 0..<400 {
            let doc = randomDoc(&rng)
            guard doc.nodes.count >= 2 else { continue }
            for i in 0..<doc.nodes.count {
                for j in 0..<doc.nodes.count where j != i {
                    let a = doc.nodes[i], b = doc.nodes[j]
                    let fromAnchor = FCEdgePath.autoAnchor(from: a.rect, toward: b.rect)
                    let toAnchor = FCEdgePath.autoAnchor(from: b.rect, toward: a.rect)
                    let edge = FCEdge(fromNode: a.id, toNode: b.id,
                                      fromAnchor: fromAnchor, toAnchor: toAnchor)
                    guard let path = FCEdgePath(edge: edge, nodes: doc.nodesByID())?.polyline,
                          path.count >= 2 else {
                        XCTFail("路由结果为空：\(edge)")
                        continue
                    }
                    checked += 1
                    let p0 = path[0], p1 = path[path.count - 1]

                    // 1) 恒为正交折线（无斜段）
                    XCTAssertEqual(diagonalSegments(path), 0,
                                   "出现斜段：A=\(a.rect) B=\(b.rect) path=\(path)")
                    // 2) 端点正好落在锚点上
                    XCTAssertEqual(p0.x, FCEdgePath.point(fromAnchor, in: a.rect).x, accuracy: 0.6)
                    XCTAssertEqual(p0.y, FCEdgePath.point(fromAnchor, in: a.rect).y, accuracy: 0.6)
                    XCTAssertEqual(p1.x, FCEdgePath.point(toAnchor, in: b.rect).x, accuracy: 0.6)
                    XCTAssertEqual(p1.y, FCEdgePath.point(toAnchor, in: b.rect).y, accuracy: 0.6)
                    // 3) 出线沿锚点法向、入线与法向反向（探头不会被拉直吞掉）
                    let d0 = CGVector(dx: path[1].x - p0.x, dy: path[1].y - p0.y)
                    let l0 = max(0.001, hypot(d0.dx, d0.dy))
                    let dotStart = (d0.dx / l0) * fromAnchor.vector.dx + (d0.dy / l0) * fromAnchor.vector.dy
                    XCTAssertGreaterThan(dotStart, 0.999, "出线方向不对：A=\(a.rect) path=\(path)")
                    let d1 = CGVector(dx: p1.x - path[path.count - 2].x, dy: p1.y - path[path.count - 2].y)
                    let l1 = max(0.001, hypot(d1.dx, d1.dy))
                    let dotEnd = (d1.dx / l1) * toAnchor.vector.dx + (d1.dy / l1) * toAnchor.vector.dy
                    XCTAssertLessThan(dotEnd, -0.999, "入线方向不对：B=\(b.rect) path=\(path)")
                    // 4) 不钻进源 / 目标图形，也不穿别的图形
                    XCTAssertFalse(enters(path, a.rect), "钻进源图形：A=\(a.rect) path=\(path)")
                    XCTAssertFalse(enters(path, b.rect), "钻进目标图形：B=\(b.rect) path=\(path)")
                    for n in doc.nodes where n.id != a.id && n.id != b.id {
                        XCTAssertFalse(enters(path, n.rect),
                                       "穿过障碍：A=\(a.rect) B=\(b.rect) O=\(n.rect) path=\(path)")
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 1000, "样本量太少，属性测试没跑够")
    }

    /// 回归：BFS 端点替换留下的「小于半格斜线」在拉直失败时会留在路径里
    /// （已复现：线以小角度斜插进图形底部）。orthogonalize 兜底必须拆成正交两段。
    func testRouterNormalizesResidualDiagonal() {
        let a = CGRect(x: 616, y: 537, width: 179, height: 44)
        let b = CGRect(x: 169, y: 224, width: 113, height: 54)
        let o = CGRect(x: 224, y: 302, width: 171, height: 101)
        var doc = FCDocument()
        var na = FCNode(kind: .rect, origin: a.origin); na.w = a.width; na.h = a.height
        var nb = FCNode(kind: .rect, origin: b.origin); nb.w = b.width; nb.h = b.height
        var no = FCNode(kind: .rect, origin: o.origin); no.w = o.width; no.h = o.height
        doc.nodes = [na, nb, no]
        let edge = FCEdge(fromNode: na.id, toNode: nb.id)
        let path = try? XCTUnwrap(FCEdgePath(edge: edge, nodes: doc.nodesByID())?.polyline)
        guard let path else { return }
        XCTAssertEqual(diagonalSegments(path), 0, "斜段未拆正交：\(path)")
        XCTAssertFalse(enters(path, o.insetBy(dx: -6, dy: -6)), "绕行贴得太近 / 穿障碍：\(path)")
    }

}

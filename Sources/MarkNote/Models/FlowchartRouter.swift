import Foundation
import CoreGraphics

/// 正交连线路由（draw.io / GoJS 风格）。
///
/// 策略（性能与效果的平衡）：
/// 1) **快路径**：先枚举简单候选（两条 L 形 + 两条 Z 形），不与任何障碍碰撞且最短者直接采用；
/// 2) **绕行**：候选全部碰撞 → 网格 BFS（4 向）绕开障碍，再做**视线拉直**（string pulling）
///    消掉锯齿式多余拐弯；
/// 3) 圆角由渲染层负责（FCRenderer.roundedPolyline）。
enum FCRouter {

    /// 锚点出线探头长度（画布坐标）
    static let stub: CGFloat = 16
    /// 障碍外扩（避免线条贴边）
    static let padding: CGFloat = 10

    // MARK: - 主入口

    /// 返回从锚点 p0（法向 n0）到 p1（法向 n1）的正交折线（含两端锚点，已去共线）。
    ///
    /// - Parameter obstacles: 中途要绕开的其他图形（会按 `padding` 外扩）
    /// - Parameter avoid: 源 / 目标图形本体（不外扩）。线可以贴着自己的锚点出发，
    ///   但**不允许钻进图形内部**——否则贴着边框走、甚至横穿自己的图形。
    static func route(p0: CGPoint, n0: CGVector, p1: CGPoint, n1: CGVector,
                      obstacles: [CGRect], avoid: [CGRect] = []) -> [CGPoint] {
        let s0 = CGPoint(x: p0.x + n0.dx * stub, y: p0.y + n0.dy * stub)
        let s1 = CGPoint(x: p1.x + n1.dx * stub, y: p1.y + n1.dy * stub)
        let padded = obstacles.map { $0.insetBy(dx: -padding, dy: -padding) }
        let rects = padded + avoid

        // 候选：L 形 ×2 + Z 形 ×2（端点探头保留，让线从锚点方向"探出去"再走）
        let midX = (s0.x + s1.x) / 2
        let midY = (s0.y + s1.y) / 2
        let candidates: [[CGPoint]] = [
            [p0, s0, CGPoint(x: s1.x, y: s0.y), s1, p1],   // L：先横后竖
            [p0, s0, CGPoint(x: s0.x, y: s1.y), s1, p1],   // L：先竖后横
            [p0, s0, CGPoint(x: midX, y: s0.y), CGPoint(x: midX, y: s1.y), s1, p1],  // Z（横-横）
            [p0, s0, CGPoint(x: s0.x, y: midY), CGPoint(x: s1.x, y: midY), s1, p1],  // Z（竖-竖）
        ].map { mergeCollinear($0) }

        let clean = candidates.filter { !collides($0, rects) }
        if let best = clean.min(by: { length($0) < length($1) }) {
            return best
        }

        // 绕行：BFS + 拉直。
        // 注意：拉直只在**中段**（s0 → s1）进行，两端 16pt 探头必须原样保留 ——
        // 否则拉直会把探头吞掉，线贴着图形边框走、箭头从侧面插进图形（已复现）。
        let detour = bfsDetour(from: s0, to: s1, obstacles: obstacles, avoid: avoid)
        let middle = stringPull(mergeCollinear(detour), rects: rects)
        return orthogonalize(mergeCollinear([p0] + middle + [p1]))
    }

    /// 正交化兜底：任何一段斜线拆成两段正交线（先横后竖）。
    ///
    /// 为什么需要：BFS 网格端点会被替换成精确的锚点探头点，这一步会留下
    /// 一段「小于半格」的斜线；若视线拉直无法处理它（被障碍挡住），
    /// 斜线会原样留在最终路径里（已复现：线以小角度斜插进图形）。
    /// 有了这道兜底，`route` 的输出**恒为正交折线**。
    static func orthogonalize(_ pts: [CGPoint]) -> [CGPoint] {
        guard pts.count >= 2 else { return pts }
        var out: [CGPoint] = [pts[0]]
        for i in 1..<pts.count {
            let a = out[out.count - 1], b = pts[i]
            if abs(b.x - a.x) > 0.5, abs(b.y - a.y) > 0.5 {
                out.append(CGPoint(x: b.x, y: a.y))
            }
            out.append(b)
        }
        return mergeCollinear(out)
    }

    // MARK: - 几何工具

    static func length(_ pts: [CGPoint]) -> CGFloat {
        var total: CGFloat = 0
        for i in 1..<max(1, pts.count) {
            total += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
        }
        return total
    }

    /// 去重 + 合并共线点
    static func mergeCollinear(_ raw: [CGPoint]) -> [CGPoint] {
        var pts: [CGPoint] = []
        for p in raw {
            if let last = pts.last, hypot(last.x - p.x, last.y - p.y) < 0.5 { continue }
            pts.append(p)
        }
        guard pts.count > 2 else { return pts }
        var out: [CGPoint] = [pts[0]]
        for i in 1..<(pts.count - 1) {
            let a = out.last!, b = pts[i], c = pts[i + 1]
            let sameX = abs(a.x - b.x) < 0.5 && abs(b.x - c.x) < 0.5
            let sameY = abs(a.y - b.y) < 0.5 && abs(b.y - c.y) < 0.5
            if sameX || sameY { continue }
            out.append(b)
        }
        out.append(pts.last!)
        return out
    }

    /// 路径是否与任一矩形相交（正交线段判定；贴边不算）
    static func collides(_ pts: [CGPoint], _ rects: [CGRect]) -> Bool {
        guard pts.count >= 2 else { return false }
        for i in 1..<pts.count {
            for r in rects where segmentIntersects(pts[i - 1], pts[i], r) {
                return true
            }
        }
        return false
    }

    static func segmentIntersects(_ a: CGPoint, _ b: CGPoint, _ rect: CGRect) -> Bool {
        if abs(a.y - b.y) < 0.5 {           // 水平段
            let x0 = min(a.x, b.x), x1 = max(a.x, b.x)
            return rect.minY + 0.5 < a.y && a.y < rect.maxY - 0.5 && x1 > rect.minX + 0.5 && x0 < rect.maxX - 0.5
        }
        if abs(a.x - b.x) < 0.5 {           // 垂直段
            let y0 = min(a.y, b.y), y1 = max(a.y, b.y)
            return rect.minX + 0.5 < a.x && a.x < rect.maxX - 0.5 && y1 > rect.minY + 0.5 && y0 < rect.maxY - 0.5
        }
        return false
    }

    // MARK: - BFS 绕行

    /// - Parameter rects: 已外扩的障碍（网格封锁用保守规则：宁肯多堵一格）
    /// - Parameter avoid: 源 / 目标图形本体。它们**只堵格心落在图形内部的格子** ——
    ///   保守规则会把端点所在格子周围也一起堵死（端点离图形只有 16pt，
    ///   两格以内），BFS 直接失败退化成 L 形，线就穿过障碍了（已复现）。
    static func bfsDetour(from a: CGPoint, to b: CGPoint, obstacles: [CGRect],
                          avoid: [CGRect] = [], step: CGFloat = 12) -> [CGPoint] {
        let margin: CGFloat = 240
        let minX = min(a.x, b.x) - margin, maxX = max(a.x, b.x) + margin
        let minY = min(a.y, b.y) - margin, maxY = max(a.y, b.y) + margin
        let cols = Int((maxX - minX) / step) + 1
        let rows = Int((maxY - minY) / step) + 1
        // 兜底也保持正交（L 形）；绝不返回斜线
        guard cols > 1, rows > 1, cols < 500, rows < 500 else {
            return [a, CGPoint(x: b.x, y: a.y), b]
        }

        func idx(_ i: Int, _ j: Int) -> Int { j * cols + i }
        func grid(_ p: CGPoint) -> (Int, Int) {
            (min(max(0, Int(((p.x - minX) / step).rounded())), cols - 1),
             min(max(0, Int(((p.y - minY) / step).rounded())), rows - 1))
        }
        func point(_ i: Int, _ j: Int) -> CGPoint {
            CGPoint(x: minX + CGFloat(i) * step, y: minY + CGFloat(j) * step)
        }

        let (si, sj) = grid(a)
        let (ti, tj) = grid(b)
        let startI = idx(si, sj), targetI = idx(ti, tj)
        let dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]

        /// 构造封锁网格。
        /// - conservative：障碍按「外扩 padding + 整格保守封锁」——
        ///   宁肯多堵一格，路径尽量离图形远一点；
        /// - 否则只堵【格心落在真实障碍内】的格子：让线能从贴边的窄缝挤过去
        ///   （端点距离别的图形只有几个点时，保守规则会把出口整个封死，
        ///   BFS 失败退化成 L 形兜底 → 线直接穿图形，已复现）。
        func makeBlocked(conservative: Bool) -> [Bool] {
            var blocked = [Bool](repeating: false, count: cols * rows)
            let rects = conservative ? obstacles.map { $0.insetBy(dx: -padding, dy: -padding) } : obstacles
            for r in rects {
                let i0 = conservative ? max(0, Int(floor((r.minX - minX) / step)))
                                      : max(0, Int(ceil((r.minX - minX) / step)))
                let i1 = conservative ? min(cols - 1, Int(ceil((r.maxX - minX) / step)))
                                      : min(cols - 1, Int(floor((r.maxX - minX) / step)))
                let j0 = conservative ? max(0, Int(floor((r.minY - minY) / step)))
                                      : max(0, Int(ceil((r.minY - minY) / step)))
                let j1 = conservative ? min(rows - 1, Int(ceil((r.maxY - minY) / step)))
                                      : min(rows - 1, Int(floor((r.maxY - minY) / step)))
                guard i0 <= i1, j0 <= j1 else { continue }
                for j in j0...j1 {
                    for i in i0...i1 { blocked[idx(i, j)] = true }
                }
            }
            // 源/目标图形本体：只堵格心落在图形内的格子（端点必在图形外 10pt 以上）
            for r in avoid {
                let i0 = max(0, Int(ceil((r.minX - minX) / step)))
                let i1 = min(cols - 1, Int(floor((r.maxX - minX) / step)))
                let j0 = max(0, Int(ceil((r.minY - minY) / step)))
                let j1 = min(rows - 1, Int(floor((r.maxY - minY) / step)))
                guard i0 <= i1, j0 <= j1 else { continue }
                for j in j0...j1 {
                    for i in i0...i1 { blocked[idx(i, j)] = true }
                }
            }
            // 端点周围清空：网格取整可能把端点贴进障碍 padding，
            // 只清单格会因邻格被挡导致 BFS 失败（表现为兜底 L 形穿图形）。
            // 从 3×3 起，若整个清空区四周仍被堵死（探头被邻居图形压住，
            // 两个图形只隔几个点）就逐圈扩大，直到出现出口 —— 宁可让线在
            // 端口附近贴着邻居走，也不要全局兜底 L 形横穿别的图形。
            // 源/目标图形本体的格子永远不清（不能在自己身上开洞）。
            for (ci, cj) in [(si, sj), (ti, tj)] {
                var radius = 1
                while true {
                    for dj in -radius...radius {
                        for di in -radius...radius {
                            let ni = ci + di, nj = cj + dj
                            guard ni >= 0, ni < cols, nj >= 0, nj < rows else { continue }
                            if avoid.contains(where: { $0.contains(point(ni, nj)) }) { continue }
                            blocked[idx(ni, nj)] = false
                        }
                    }
                    if radius >= 4 { break }
                    // 出口检测：清空区里任意一格，在区域外是否有可走邻居
                    var escaped = false
                    for dj in -radius...radius where !escaped {
                        for di in -radius...radius where !escaped {
                            let ni = ci + di, nj = cj + dj
                            guard ni >= 0, ni < cols, nj >= 0, nj < rows else { continue }
                            for (ddi, ddj) in dirs {
                                let mi = ni + ddi, mj = nj + ddj
                                guard mi >= 0, mi < cols, mj >= 0, mj < rows else { continue }
                                if abs(mi - ci) <= radius, abs(mj - cj) <= radius { continue }
                                if !blocked[idx(mi, mj)] { escaped = true; break }
                            }
                        }
                    }
                    if escaped { break }
                    radius += 1
                }
            }
            // 清空不能开洞：源/目标图形内部重新堵上
            for r in avoid {
                let i0 = max(0, Int(ceil((r.minX - minX) / step)))
                let i1 = min(cols - 1, Int(floor((r.maxX - minX) / step)))
                let j0 = max(0, Int(ceil((r.minY - minY) / step)))
                let j1 = min(rows - 1, Int(floor((r.maxY - minY) / step)))
                guard i0 <= i1, j0 <= j1 else { continue }
                for j in j0...j1 {
                    for i in i0...i1 { blocked[idx(i, j)] = true }
                }
            }
            blocked[startI] = false
            blocked[targetI] = false
            return blocked
        }

        /// 跑一次 BFS；找到返回网格路径，找不到返回 nil。
        func search(_ blocked: [Bool]) -> [CGPoint]? {
            var prev = [Int32](repeating: -1, count: cols * rows)
            prev[startI] = Int32(startI)
            var queue: [Int] = [startI]
            var head = 0
            var found = false
            while head < queue.count {
                let cur = queue[head]
                head += 1
                if cur == targetI { found = true; break }
                let ci = cur % cols, cj = cur / cols
                for (di, dj) in dirs {
                    let ni = ci + di, nj = cj + dj
                    guard ni >= 0, ni < cols, nj >= 0, nj < rows else { continue }
                    let nidx = idx(ni, nj)
                    if blocked[nidx] || prev[nidx] != -1 { continue }
                    prev[nidx] = Int32(cur)
                    queue.append(nidx)
                }
            }
            guard found else { return nil }
            var path: [CGPoint] = []
            var cur = targetI
            while cur != startI {
                path.append(point(cur % cols, cur / cols))
                cur = Int(prev[cur])
            }
            path.append(point(si, sj))
            path.reverse()
            if !path.isEmpty {
                path[0] = a
                path[path.count - 1] = b
            }
            return path
        }

        // 两轮都跑一遍：优先「完全没碰到真实障碍」的结果；
        // 都被迫贴边时，取碰得少的那条（最后一手 L 形兜底只留给彻底无解的布局）。
        let conservative = search(makeBlocked(conservative: true))
        if let path = conservative, collisionCount(path, obstacles) == 0 { return path }
        let relaxed = search(makeBlocked(conservative: false))
        if let path = relaxed, collisionCount(path, obstacles) == 0 { return path }
        if let a1 = conservative, let b1 = relaxed {
            return collisionCount(a1, obstacles) <= collisionCount(b1, obstacles) ? a1 : b1
        }
        return conservative ?? relaxed ?? [a, CGPoint(x: b.x, y: a.y), b]
    }

    /// 折线穿过多少段障碍（用于比较两轮 BFS 结果谁更干净）
    static func collisionCount(_ pts: [CGPoint], _ rects: [CGRect]) -> Int {
        guard pts.count >= 2 else { return 0 }
        var count = 0
        for i in 1..<pts.count {
            for r in rects where segmentIntersects(pts[i - 1], pts[i], r) { count += 1 }
        }
        return count
    }

    // MARK: - 视线拉直（string pulling）

    /// 贪心拉直：从当前点尽量跳到最远的可正交直达点（L 形两段都不碰撞），消掉 BFS 的锯齿拐弯。
    static func stringPull(_ pts: [CGPoint], rects: [CGRect]) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        var out: [CGPoint] = [pts[0]]
        var i = 0
        while i < pts.count - 1 {
            var advanced = false
            if i < pts.count - 2 {
                for j in stride(from: pts.count - 1, through: i + 2, by: -1) {
                    if let link = directLink(pts[i], pts[j], rects: rects) {
                        out.append(contentsOf: link.dropFirst())
                        i = j
                        advanced = true
                        break
                    }
                }
            }
            if !advanced {
                out.append(pts[i + 1])
                i += 1
            }
        }
        return mergeCollinear(out)
    }

    /// 两点之间能否用「直段或 L 形」正交直达（不碰障碍）；能则返回完整子路径。
    static func directLink(_ a: CGPoint, _ b: CGPoint, rects: [CGRect]) -> [CGPoint]? {
        if abs(a.x - b.x) < 0.5 || abs(a.y - b.y) < 0.5 {
            return collides([a, b], rects) ? nil : [a, b]
        }
        let l1 = [a, CGPoint(x: b.x, y: a.y), b]
        if !collides(l1, rects) { return mergeCollinear(l1) }
        let l2 = [a, CGPoint(x: a.x, y: b.y), b]
        if !collides(l2, rects) { return mergeCollinear(l2) }
        return nil
    }
}

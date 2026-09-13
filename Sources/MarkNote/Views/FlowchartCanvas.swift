import AppKit
import SwiftUI

// MARK: - 画布坐标变换（doc 坐标 ⇄ 视图坐标）

struct FCViewTransform {
    var zoom: CGFloat = 1
    var offset: CGSize = .zero

    func p(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * zoom + offset.width, y: p.y * zoom + offset.height)
    }

    func r(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX * zoom + offset.width, y: r.minY * zoom + offset.height,
               width: r.width * zoom, height: r.height * zoom)
    }

    func len(_ v: CGFloat) -> CGFloat { v * zoom }

    func doc(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - offset.width) / zoom, y: (p.y - offset.height) / zoom)
    }

    func docRect(_ r: CGRect) -> CGRect {
        CGRect(x: (r.minX - offset.width) / zoom, y: (r.minY - offset.height) / zoom,
               width: r.width / zoom, height: r.height / zoom)
    }
}

// MARK: - 文字排版（画布 / 导出 / 测量共用一套换行规则）

enum FCTextLayout {
    static func lineHeight(_ font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    /// 贪心换行：CJK 逐字断，拉丁文优先在空格处断
    static func lines(_ text: String, width: CGFloat, font: NSFont) -> [String] {
        guard width > 4 else { return text.isEmpty ? [] : [text] }
        var out: [String] = []
        for raw in text.components(separatedBy: "\n") {
            if raw.isEmpty { out.append(""); continue }
            var current = ""
            var lastBreak = -1
            for ch in raw {
                let candidate = current + String(ch)
                if measure(candidate, font: font) <= width {
                    current = candidate
                    if ch == " " || ch == "-" { lastBreak = current.count }
                } else {
                    if lastBreak > 0, lastBreak < current.count {
                        let head = String(current.prefix(lastBreak))
                        out.append(head.trimmingCharacters(in: .whitespaces))
                        current = String(current.dropFirst(lastBreak)) + String(ch)
                    } else {
                        out.append(current)
                        current = String(ch)
                    }
                    lastBreak = -1
                }
            }
            out.append(current)
        }
        return out
    }

    static func measure(_ s: String, font: NSFont) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: font]).width
    }

    static func blockHeight(_ lines: [String], font: NSFont) -> CGFloat {
        CGFloat(lines.count) * lineHeight(font)
    }
}

// MARK: - 渲染器（画布与 PNG 导出共用）

/// 解析后的绘制样式：全局样式 × 主题 → 具体颜色/粗细
struct FCRenderStyle {
    var fill: NSColor?
    var stroke: NSColor
    var lineWidth: CGFloat
    var corner: CGFloat
    var fontSize: Double
    var text: NSColor
    var dashed: Bool
}

extension FCGlobalStyle {
    /// 全局样式 + 主题 → 实际绘制参数
    func resolved(theme: FlowchartTheme) -> FCRenderStyle {
        let a = accent.flatMap { NSColor.fcHex($0) } ?? theme.accent
        let width = CGFloat(max(0.5, min(6, lineWidth)))
        let radius = CGFloat(max(0, min(40, corner)))
        switch preset {
        case .soft:
            // 淡底：纸底里调进一点点强调色（fillOpacity 是强调色的比例）
            let tinted = (theme.background.blended(withFraction: CGFloat(min(max(fillOpacity, 0), 1)),
                                                   of: a) ?? a)
            return FCRenderStyle(fill: tinted, stroke: a, lineWidth: width, corner: radius,
                                 fontSize: fontSize, text: theme.text, dashed: dashed)
        case .outline:
            return FCRenderStyle(fill: theme.surface, stroke: a, lineWidth: width, corner: radius,
                                 fontSize: fontSize, text: theme.text, dashed: dashed)
        case .flat:
            return FCRenderStyle(fill: a, stroke: a, lineWidth: width, corner: radius,
                                 fontSize: fontSize, text: theme.background, dashed: dashed)
        case .plain:
            return FCRenderStyle(fill: nil, stroke: theme.secondary, lineWidth: width, corner: radius,
                                 fontSize: fontSize, text: theme.text, dashed: dashed)
        }
    }
}

enum FCRenderer {

    /// 折线画成圆角：每个拐角用二次曲线倒角（半径按相邻段长度自动收敛）
    static func roundedPolyline(_ path: inout Path, _ pts: [CGPoint], radius: CGFloat) {
        guard pts.count >= 2 else { return }
        path.move(to: pts[0])
        guard pts.count > 2 else {
            path.addLine(to: pts[1])
            return
        }
        for i in 1..<(pts.count - 1) {
            let prev = pts[i - 1], cur = pts[i], next = pts[i + 1]
            let l1 = hypot(cur.x - prev.x, cur.y - prev.y)
            let l2 = hypot(next.x - cur.x, next.y - cur.y)
            let r = min(radius, l1 / 2, l2 / 2)
            guard r > 0.5, l1 > 0.001, l2 > 0.001 else {
                path.addLine(to: cur)
                continue
            }
            let a = CGPoint(x: cur.x + (prev.x - cur.x) / l1 * r,
                            y: cur.y + (prev.y - cur.y) / l1 * r)
            let b = CGPoint(x: cur.x + (next.x - cur.x) / l2 * r,
                            y: cur.y + (next.y - cur.y) / l2 * r)
            path.addLine(to: a)
            path.addQuadCurve(to: b, control: cur)
        }
        path.addLine(to: pts[pts.count - 1])
    }

    static func grid(_ ctx: inout GraphicsContext, size: CGSize, transform: FCViewTransform,
                     theme: FlowchartTheme, step: CGFloat = 20) {
        let minor = theme.border.withAlphaComponent(0.35)
        let major = theme.border.withAlphaComponent(0.7)
        let scaled = max(6, transform.len(step))
        guard scaled > 3 else { return }
        let ox = transform.offset.width.truncatingRemainder(dividingBy: scaled * 5)
        let oy = transform.offset.height.truncatingRemainder(dividingBy: scaled * 5)
        var minorPath = Path()
        var majorPath = Path()
        var x = ox - scaled * 5
        var i = 0
        while x <= size.width + scaled {
            let isMajor = (i % 5) == 0
            let px = x.rounded()
            if isMajor {
                majorPath.move(to: CGPoint(x: px, y: 0))
                majorPath.addLine(to: CGPoint(x: px, y: size.height))
            } else {
                minorPath.move(to: CGPoint(x: px, y: 0))
                minorPath.addLine(to: CGPoint(x: px, y: size.height))
            }
            x += scaled
            i += 1
        }
        var y = oy - scaled * 5
        i = 0
        while y <= size.height + scaled {
            let isMajor = (i % 5) == 0
            let py = y.rounded()
            if isMajor {
                majorPath.move(to: CGPoint(x: 0, y: py))
                majorPath.addLine(to: CGPoint(x: size.width, y: py))
            } else {
                minorPath.move(to: CGPoint(x: 0, y: py))
                minorPath.addLine(to: CGPoint(x: size.width, y: py))
            }
            y += scaled
            i += 1
        }
        ctx.stroke(minorPath, with: .color(Color(nsColor: minor)), lineWidth: 0.5)
        ctx.stroke(majorPath, with: .color(Color(nsColor: major)), lineWidth: 1)
    }

    /// 图形 / 连线 / 文本（不含选中框与手柄）
    static func content(_ doc: FCDocument, theme: FlowchartTheme, transform: FCViewTransform,
                        jumpErase: NSColor? = nil, ctx: inout GraphicsContext) {
        let rs = doc.style.resolved(theme: theme)
        let paths = doc.edges.compactMap { e in doc.edgePath(e).map { (e, $0) } }
        for g in doc.groups { group(g, style: rs, theme: theme, transform: transform, ctx: &ctx) }
        for (i, item) in paths.enumerated() {
            // 交叉跳线（断点再连）：这条线从前面画过的线上面「跳过」
            var jumpPoints: [CGPoint] = []
            for j in 0..<i {
                jumpPoints.append(contentsOf: Self.crossings(item.1.polyline, paths[j].1.polyline))
            }
            edge(item.0, path: item.1, style: rs, theme: theme, transform: transform,
                 jumps: jumpPoints, ctx: &ctx)
        }
        for n in doc.nodes { node(n, style: rs, theme: theme, transform: transform, ctx: &ctx) }
        for t in doc.texts { textItem(t, style: rs, theme: theme, transform: transform, ctx: &ctx) }
    }

    /// 两条折线的正交交叉点（只取垂直相交、且都在线段内部）
    static func crossings(_ a: [CGPoint], _ b: [CGPoint]) -> [CGPoint] {
        var out: [CGPoint] = []
        for i in 1..<max(1, a.count) {
            let a0 = a[i - 1], a1 = a[i]
            for j in 1..<max(1, b.count) {
                let b0 = b[j - 1], b1 = b[j]
                let aHor = abs(a0.y - a1.y) < 0.5, bHor = abs(b0.y - b1.y) < 0.5
                guard aHor != bHor else { continue }
                let h0 = aHor ? a0 : b0, h1 = aHor ? a1 : b1     // 水平段
                let v0 = aHor ? b0 : a0, v1 = aHor ? b1 : a1     // 垂直段
                let x = v0.x, y = h0.y
                let hx0 = min(h0.x, h1.x), hx1 = max(h0.x, h1.x)
                let vy0 = min(v0.y, v1.y), vy1 = max(v0.y, v1.y)
                if x > hx0 + 3, x < hx1 - 3, y > vy0 + 3, y < vy1 - 3 {
                    out.append(CGPoint(x: x, y: y))
                }
            }
        }
        return out
    }

    /// 折线 + 圆角 + 跳线：交叉处**在线上留缺口**再搭一段拱（不用底色挖洞，
    /// 所以分组底色、透明背景导出都不会留白斑）。
    static func jumpAwarePath(_ pts: [CGPoint], jumps: [CGPoint],
                              radius: CGFloat, jump: CGFloat) -> Path {
        var path = Path()
        guard pts.count >= 2 else { return path }
        var run: [CGPoint] = [pts[0]]
        func flush(_ run: inout [CGPoint]) {
            guard let last = run.last else { return }
            if run.count >= 2 { roundedPolyline(&path, run, radius: radius) }
            run = [last]
        }
        for i in 0..<(pts.count - 1) {
            let a = pts[i], b = pts[i + 1]
            let len = hypot(b.x - a.x, b.y - a.y)
            guard len > 0.5 else { continue }
            let dir = CGVector(dx: (b.x - a.x) / len, dy: (b.y - a.y) / len)
            let normal = CGVector(dx: -dir.dy, dy: dir.dx)
            // 落在这条段上的交叉点（按沿线距离排序，太靠两端就不跳）
            var hits: [(d: CGFloat, p: CGPoint)] = []
            for c in jumps {
                let d = (c.x - a.x) * dir.dx + (c.y - a.y) * dir.dy
                let perp = abs((c.x - a.x) * normal.dx + (c.y - a.y) * normal.dy)
                if perp < 0.75, d > jump * 1.7, len - d > jump * 1.7 { hits.append((d, c)) }
            }
            hits.sort { $0.d < $1.d }
            for h in hits {
                let start = CGPoint(x: h.p.x - dir.dx * jump, y: h.p.y - dir.dy * jump)
                let end = CGPoint(x: h.p.x + dir.dx * jump, y: h.p.y + dir.dy * jump)
                run.append(start)
                flush(&run)
                let ctrl = CGPoint(x: h.p.x + normal.dx * jump * 1.6,
                                   y: h.p.y + normal.dy * jump * 1.6)
                path.move(to: start)
                path.addQuadCurve(to: end, control: ctrl)
                run = [end]
            }
            run.append(b)
        }
        flush(&run)
        return path
    }

    /// 画一个小胶囊标签（拉线实时距离 / 缩放实时尺寸用）
    static func drawBadge(ctx: inout GraphicsContext, theme: FlowchartTheme,
                          at point: CGPoint, text: String) {
        let font = theme.nsFont(size: 10)
        let size = (text as NSString).size(withAttributes: [.font: font])
        let box = CGRect(x: point.x - size.width / 2 - 5, y: point.y - size.height / 2 - 2,
                         width: size.width + 10, height: size.height + 4)
        ctx.fill(Path(roundedRect: box, cornerRadius: 4),
                 with: .color(Color(nsColor: theme.surface).opacity(0.92)))
        ctx.stroke(Path(roundedRect: box, cornerRadius: 4),
                   with: .color(Color(nsColor: theme.border)), lineWidth: 0.8)
        ctx.draw(Text(text).font(theme.font(size: 10))
                    .foregroundStyle(Color(nsColor: theme.secondary)),
                 at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
    }

    static func node(_ n: FCNode, style rs: FCRenderStyle, theme: FlowchartTheme, transform: FCViewTransform,
                     ctx: inout GraphicsContext) {
        let rect = transform.r(n.rect)
        let path = FCShape.path(kind: n.kind, rect: rect, corner: transform.len(rs.corner))
        let lineWidth = max(0.5, transform.len(rs.lineWidth))
        let dash: [CGFloat] = rs.dashed ? [max(2, lineWidth * 4), max(2, lineWidth * 3)] : []

        if let fill = rs.fill {
            ctx.fill(path, with: .color(Color(nsColor: fill)))
        }
        ctx.stroke(path, with: .color(Color(nsColor: rs.stroke)),
                   style: StrokeStyle(lineWidth: lineWidth, dash: dash))
        if let detail = FCShape.detail(kind: n.kind, rect: rect) {
            ctx.stroke(detail, with: .color(Color(nsColor: rs.stroke)), lineWidth: lineWidth)
        }
        textBlock(n.text, in: rect, style: n.style, global: rs,
                  widthScale: textWidthScale(n.kind), theme: theme,
                  transform: transform, ctx: &ctx,
                  verticalInset: n.kind == .cylinder ? transform.len(10) : transform.len(6))
    }

    static func textItem(_ t: FCTextItem, style rs: FCRenderStyle, theme: FlowchartTheme,
                         transform: FCViewTransform,
                         ctx: inout GraphicsContext) {
        let rect = transform.r(t.rect)
        textBlock(t.text, in: rect, style: t.style, global: rs,
                  widthScale: 1, theme: theme, transform: transform, ctx: &ctx)
    }

    static func group(_ g: FCGroup, style rs: FCRenderStyle, theme: FlowchartTheme,
                      transform: FCViewTransform,
                      ctx: inout GraphicsContext) {
        let rect = transform.r(g.rect)
        let path = Path(roundedRect: rect, cornerRadius: transform.len(max(4, rs.corner)))
        let fill = NSColor.fcHex(g.style.fill)
        if let fill {
            ctx.fill(path, with: .color(Color(nsColor: fill)))
        }
        let lineWidth = max(0.5, transform.len(rs.lineWidth))
        let dash: [CGFloat] = rs.dashed ? [max(3, lineWidth * 4), max(3, lineWidth * 3)] : []
        ctx.stroke(path, with: .color(Color(nsColor: rs.stroke)),
                   style: StrokeStyle(lineWidth: lineWidth, dash: dash))
        guard !g.title.isEmpty else { return }
        let font = theme.nsFont(size: rs.fontSize, bold: true, display: true)
        let lines = FCTextLayout.lines(g.title, width: max(20, rect.width - transform.len(16)), font: font)
        let lh = FCTextLayout.lineHeight(font)
        for (i, line) in lines.enumerated() {
            ctx.draw(Text(line).font(theme.font(size: rs.fontSize, bold: true, display: true))
                        .foregroundStyle(Color(nsColor: rs.text)),
                     at: CGPoint(x: rect.minX + transform.len(8),
                                 y: rect.minY + transform.len(6) + CGFloat(i) * lh + lh / 2),
                     anchor: .leading)
        }
    }

    static func edge(_ e: FCEdge, path docPath: FCEdgePath, style rs: FCRenderStyle, theme: FlowchartTheme,
                     transform: FCViewTransform, jumps: [CGPoint] = [], ctx: inout GraphicsContext) {
        let stroke = rs.stroke
        let lineWidth = max(0.5, transform.len(rs.lineWidth))
        let dash: [CGFloat] = rs.dashed ? [max(2, lineWidth * 4), max(2, lineWidth * 3)] : []
        var path = Path()
        let allLines = docPath.segments.allSatisfy { if case .line = $0 { return true } else { return false } }
        if allLines, docPath.segments.count >= 2 {
            // 折线圆角过渡（draw.io 观感：拐角是柔和圆弧，不是生硬尖角）
            var pts = [docPath.start] + docPath.segments.compactMap { seg -> CGPoint? in
                if case .line(let p) = seg { return p }
                return nil
            }
            // 正交化防御：任何斜段（旧存档 / 异常数据）自动插拐点拆成 L，
            // 保证「折线」风格下永远不出现斜线
            var ortho: [CGPoint] = []
            for p in pts {
                if let last = ortho.last,
                   abs(last.x - p.x) > 0.6, abs(last.y - p.y) > 0.6 {
                    ortho.append(CGPoint(x: p.x, y: last.y))
                }
                ortho.append(p)
            }
            pts = ortho
            let screenPts = pts.map { transform.p($0) }
            if jumps.isEmpty {
                Self.roundedPolyline(&path, screenPts, radius: 8)
            } else {
                path = Self.jumpAwarePath(screenPts,
                                          jumps: jumps.map { transform.p($0) },
                                          radius: 8, jump: 5)
            }
        } else {
            path.move(to: transform.p(docPath.start))
            for seg in docPath.segments {
                switch seg {
                case .line(let p): path.addLine(to: transform.p(p))
                case .cubic(let c0, let c1, let p):
                    path.addCurve(to: transform.p(p), control1: transform.p(c0), control2: transform.p(c1))
                }
            }
        }
        ctx.stroke(path, with: .color(Color(nsColor: stroke)),
                   style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: dash))

        let arrowSize = max(7, lineWidth * 4.2)
        if e.arrow == .end || e.arrow == .both {
            let tip = transform.p(docPath.polyline.last ?? docPath.start)
            ctx.fill(FCShape.arrow(tip: tip, direction: docPath.endDirection, size: arrowSize),
                     with: .color(Color(nsColor: stroke)))
        }
        if e.arrow == .both {
            let tip = transform.p(docPath.start)
            ctx.fill(FCShape.arrow(tip: tip, direction: docPath.startDirection, size: arrowSize),
                     with: .color(Color(nsColor: stroke)))
        }
        guard !e.label.isEmpty else { return }
        let font = theme.nsFont(size: max(9, rs.fontSize - 1), bold: e.style.bold)
        let lines = FCTextLayout.lines(e.label, width: transform.len(160), font: font)
        let lh = FCTextLayout.lineHeight(font)
        let widest = lines.map { FCTextLayout.measure($0, font: font) }.max() ?? 10
        let mid = transform.p(docPath.midpoint)
        let boxW = widest + transform.len(10)
        let boxH = CGFloat(lines.count) * lh + transform.len(4)
        let box = CGRect(x: mid.x - boxW / 2, y: mid.y - boxH / 2, width: boxW, height: boxH)
        let labelShape = Path(roundedRect: box, cornerRadius: transform.len(4))
        ctx.fill(labelShape, with: .color(Color(nsColor: theme.surface)))
        ctx.stroke(labelShape, with: .color(Color(nsColor: stroke).opacity(0.28)),
                   lineWidth: 0.8)
        for (i, line) in lines.enumerated() {
            ctx.draw(Text(line).font(theme.font(size: max(9, rs.fontSize - 1), bold: e.style.bold))
                        .foregroundStyle(Color(nsColor: rs.text)),
                     at: CGPoint(x: box.midX,
                                 y: box.minY + transform.len(2) + CGFloat(i) * lh + lh / 2),
                     anchor: .center)
        }
    }

    /// 图形内文字（自动换行 + 垂直居中 + 对齐）
    static func textBlock(_ text: String, in rect: CGRect, style: FCStyle, global rs: FCRenderStyle,
                          widthScale: CGFloat = 1,
                          theme: FlowchartTheme,
                          transform: FCViewTransform, ctx: inout GraphicsContext,
                          verticalInset: CGFloat = 6) {
        guard !text.isEmpty else { return }
        let size = max(8, transform.len(rs.fontSize))
        let font = theme.nsFont(size: size, bold: style.bold)
        // 按形状收窄排版宽度：菱形/椭圆/胶囊的斜边与弧边会切掉文字（精细绘制）
        let lines = FCTextLayout.lines(text, width: max(10, rect.width * widthScale - transform.len(16)), font: font)
        let lh = FCTextLayout.lineHeight(font)
        let total = CGFloat(lines.count) * lh
        let top = rect.midY - total / 2
        let anchor: UnitPoint = style.align == .leading ? .leading : (style.align == .trailing ? .trailing : .center)
        let x: CGFloat = style.align == .leading ? rect.minX + transform.len(8)
            : (style.align == .trailing ? rect.maxX - transform.len(8) : rect.midX)
        for (i, line) in lines.enumerated() {
            ctx.draw(Text(line).font(theme.font(size: size, bold: style.bold))
                        .foregroundStyle(Color(nsColor: rs.text)),
                     at: CGPoint(x: x, y: top + CGFloat(i) * lh + lh / 2),
                     anchor: anchor)
        }
    }

    /// 每种形状的可用文字宽度比例（越「斜」的形状越窄）
    static func textWidthScale(_ kind: FCShapeKind) -> CGFloat {
        switch kind {
        case .rect, .note: return 1.0
        case .roundedRect: return 0.94
        case .capsule: return 0.86
        case .ellipse: return 0.78
        case .diamond: return 0.58
        case .parallelogram: return 0.76
        case .cylinder: return 0.9
        }
    }
}

// MARK: - 导出用的静态画布（无网格 / 无选中 / 可选背景）

struct FlowchartExportCanvas: View {
    let doc: FCDocument
    let theme: FlowchartTheme
    let background: NSColor?
    let padding: CGFloat

    var body: some View {
        let bounds = doc.contentBounds.insetBy(dx: -padding, dy: -padding)
        let transform = FCViewTransform(zoom: 1,
                                        offset: CGSize(width: -bounds.minX, height: -bounds.minY))
        ZStack(alignment: .topLeading) {
            if let background {
                Color(nsColor: background)
            }
            Canvas { ctx, _ in
                // 跳线的「断开」要用实际背景色；透明导出时传 nil（只画拱，不填底色）
                FCRenderer.content(doc, theme: theme, transform: transform,
                                   jumpErase: background, ctx: &ctx)
            }
            .frame(width: bounds.width, height: bounds.height)
        }
        .frame(width: max(1, bounds.width), height: max(1, bounds.height), alignment: .topLeading)
    }
}

// MARK: - 手柄

enum FCHandle: String, CaseIterable {
    case tl, t, tr, r, br, b, bl, l

    /// 缩放手柄只用四个角：边中点位置让给连线锚点（两套热区原本完全重合，
    /// 手柄优先级又更高 —— 结果是"从边缘拉不出线"）
    static let corners: [FCHandle] = [.tl, .tr, .br, .bl]

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .tl: return CGPoint(x: rect.minX, y: rect.minY)
        case .t: return CGPoint(x: rect.midX, y: rect.minY)
        case .tr: return CGPoint(x: rect.maxX, y: rect.minY)
        case .r: return CGPoint(x: rect.maxX, y: rect.midY)
        case .br: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .b: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bl: return CGPoint(x: rect.minX, y: rect.maxY)
        case .l: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    /// 拖动后新的矩形（保持最小尺寸 24）
    func apply(_ rect: CGRect, dx: CGFloat, dy: CGFloat) -> CGRect {
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        switch self {
        case .tl, .l, .bl: minX += dx
        case .tr, .r, .br: maxX += dx
        default: break
        }
        switch self {
        case .tl, .t, .tr: minY += dy
        case .bl, .b, .br: maxY += dy
        default: break
        }
        let minSize: CGFloat = 24
        if maxX - minX < minSize {
            switch self {
            case .tl, .l, .bl: minX = maxX - minSize
            default: maxX = minX + minSize
            }
        }
        if maxY - minY < minSize {
            switch self {
            case .tl, .t, .tr: minY = maxY - minSize
            default: maxY = minY + minSize
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

// MARK: - 画布（交互）

/// 拉线过程中的点击判定（选择工具从边缘拖线、连线工具点-点，都走这一套）
enum FCDrawGate {
    enum Action: Equatable {
        case finish      // 点在图形上 → 收尾连接
        case cancel      // 空白处双击 → 取消整条拉线
        case keep        // 空白处单击 → 继续拉（线挂在光标上）
        case idle        // 没在拉线，交给常规点击逻辑
    }

    static let doubleClickWindow: TimeInterval = 0.45
    /// 从边缘起线的最小位移（屏幕 pt）：仅仅点一下不该起线
    static let edgeStartThreshold: CGFloat = 4

    static func action(drawing: Bool, moved: Bool, onNode: Bool,
                       lastBlankClick: Date, now: Date,
                       window: TimeInterval = doubleClickWindow) -> Action {
        guard drawing, !moved else { return .idle }
        if onNode { return .finish }
        return now.timeIntervalSince(lastBlankClick) < window ? .cancel : .keep
    }

    /// 边缘按下后是否已经拖够距离、可以真正起一条线
    static func shouldStartEdge(from start: CGPoint, to current: CGPoint, zoom: CGFloat) -> Bool {
        hypot(current.x - start.x, current.y - start.y) * max(zoom, 0.2) >= edgeStartThreshold
    }
}

struct FlowchartCanvas: View {
    @ObservedObject var editor: FlowchartEditor
    let theme: FlowchartTheme
    var onRequestFit: () -> Void = {}

    private enum Drag {
        case none
        case pan(startOffset: CGSize, start: CGPoint)
        case move(start: CGPoint, origins: [String: CGRect], ids: Set<String>)
        case resize(id: String, handle: FCHandle, original: CGRect)
        case create(id: String, start: CGPoint)
        /// 在图形边缘按下：还不确定是「点选/拖动」还是「拉线」，等真的拖起来才算
        case maybeEdge(node: String, anchor: FCAnchor, start: CGPoint)
        case edge(from: String, anchor: FCAnchor)
        /// 拖动连线端点改接（draw.io：选中连线后拖端点换目标）
        case reconnect(id: String, isFrom: Bool)
        case marquee(start: CGPoint)
    }

    @State private var drag: Drag = .none
    @State private var marquee: CGRect?
    @State private var hoverAnchor: (node: String, anchor: FCAnchor)?
    /// hover 的文档坐标（draw.io 式：绿点跟随光标，落在浮动连接点上）
    @State private var hoverPoint: CGPoint?
    /// 鼠标悬停的连线（加粗高亮，提示可点选）
    @State private var hoverEdgeID: String?
    /// 连线工具的起点（draw.io 同款：点源图形 → 点目标图形，不用按住拖）
    @State private var edgeStartNode: String?
    /// 点击-点击连线时，起点落在哪条边（用户点哪条边就从哪条边出）
    @State private var edgeStartAnchor: FCAnchor = .auto
    /// 连线工具本次按下的起始图形（决定「拖拽连线」还是「点击-点击连线」）
    @State private var edgePressNode: String?
    @State private var guideX: CGFloat?
    @State private var guideY: CGFloat?
    /// 画布在窗口中的位置：由 NSView 自己记录，供滚轮命中判断读取。
    /// 注意：不能在 NSView.layout() 里回写 SwiftUI 状态 —— AppKit 会在布局期抛异常（实测崩溃）。
    @State private var scrollTarget = FCScrollTargetBox()
    @State private var scrollMonitor: Any?
    @State private var magnifyMonitor: Any?
    /// 自判双击用（DragGesture(0) 吞掉了 SwiftUI 的双击手势）
    @State private var lastClickAt: Date = .distantPast
    /// 拉线中「双击空白取消」的自判时间（只在空白点击上累计，避免和双击建框冲突）
    @State private var lastBlankClickAt: Date = .distantPast
    /// 拉线过程中光标悬停的目标图形（draw.io 式高亮 + 落点吸附）
    @State private var edgeTargetID: String?

    private var transform: FCViewTransform {
        FCViewTransform(zoom: editor.zoom, offset: editor.offset)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    if editor.doc.showGrid { FCRenderer.grid(&ctx, size: size, transform: transform, theme: theme) }
                    FCRenderer.content(editor.doc, theme: theme, transform: transform,
                                       jumpErase: theme.background, ctx: &ctx)
                    drawOverlays(&ctx)
                }
                .background(FCScrollTargetReporter(box: scrollTarget))
                editingOverlay
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
            // 从左侧形状库拖入 → 直接在落点放置（draw.io 习惯）
            .dropDestination(for: String.self) { items, location in
                guard let raw = items.first, let tool = FCTool(rawValue: raw), let shape = tool.shape else {
                    return false
                }
                let p = transform.doc(location)
                let node = FCNode(kind: shape, origin: p)   // 形状不带默认文字
                editor.commit { $0.nodes.append(node) }
                editor.selection = [node.id]
                editor.tool = .select   // 即用即销：放下就回选择工具，之后单击是选中而不是又建一个
                return true
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): updateHover(transform.doc(p))
                case .ended: hoverAnchor = nil
                }
            }
            // 右键菜单：命中什么显示什么操作（AppKit 原生菜单，左键完全放行给手势）
            .overlay(FCRightClickCatcher { windowPoint, screen in
                presentContextMenu(windowPoint: windowPoint, screen: screen)
            })
            .onAppear {
                updateCanvasSize(geo.size)
                installScrollMonitors()
            }
            .onDisappear { removeScrollMonitors() }
            .onChange(of: geo.size) { _, size in updateCanvasSize(size) }
            .onChange(of: editor.tool) { _, _ in
                // 切换工具时清掉「点击-点击连线」的半途状态
                if edgeStartNode != nil || !editor.pendingWaypoints.isEmpty {
                    edgeStartNode = nil
                    editor.pendingEdge = nil
                    editor.pendingWaypoints = []
                    edgeTargetID = nil
                }
            }
        }
        .background(Color(nsColor: theme.background))
    }

    /// 画布尺寸回填（异步 + 去重：布局期直接写状态会触发 AppKit 异常）
    private func updateCanvasSize(_ size: CGSize) {
        guard size.width > 1, size.height > 1, editor.canvasSize != size else { return }
        DispatchQueue.main.async {
            guard editor.canvasSize != size else { return }
            editor.canvasSize = size
        }
    }

    // MARK: 叠加层（选中框 / 手柄 / 框选 / 连线预览 / 对齐线）

    /// 拉线中的实时预览路径：起点 = 源图形锚点（.auto 按光标方向选边），
    /// 终点 = 悬停高亮的目标图形最近的边，否则就是光标点本身；
    /// 中间交给真正的正交路由器绕障（预览即所见：放下后就是这条线）。
    private func pendingPreview(_ pending: (from: String, anchor: FCAnchor, point: CGPoint)) -> [CGPoint] {
        guard let source = editor.doc.nodes.first(where: { $0.id == pending.from }) else { return [] }
        let fromAnchor: FCAnchor = pending.anchor == .auto
            ? FCEdgePath.autoAnchor(from: source.rect,
                                    toward: CGRect(origin: pending.point, size: .zero))
            : pending.anchor
        let p0 = FCEdgePath.point(fromAnchor, in: source.rect)
        var p1 = pending.point
        var n1 = CGVector(dx: 0, dy: 0)
        var targetRect: CGRect?
        if let tid = edgeTargetID,
           let target = editor.doc.nodes.first(where: { $0.id == tid }) {
            if tid == pending.from {
                // 自环预览（写循环）：上边出、侧边回
                let fromAnchor = pending.anchor == .auto ? FCAnchor.top : pending.anchor
                return FCEdgePath.selfLoop(rect: source.rect, from: fromAnchor,
                                           to: fromAnchor.selfLoopPartner, out: 26)
            }
            // 落点边 = 鼠标所在的那条边（不再按两框相对位置猜）
            let toAnchor = nearestAnchor(to: pending.point, node: target)
            p1 = FCEdgePath.point(toAnchor, in: target.rect)
            n1 = toAnchor.vector
            targetRect = target.rect
        } else {
            // 悬空：按光标进入方向收线，预览的拐弯与最终连线一致
            let dx = p1.x - p0.x, dy = p1.y - p0.y
            n1 = abs(dx) >= abs(dy) ? CGVector(dx: dx >= 0 ? 1 : -1, dy: 0)
                                    : CGVector(dx: 0, dy: dy >= 0 ? 1 : -1)
        }
        let obstacles = editor.doc.nodes
            .filter { $0.id != pending.from && $0.id != edgeTargetID }
            .map(\.rect)
        let avoid = [source.rect] + (targetRect.map { [$0] } ?? [])
        // 有手动断点：按断点走（预览 = 最终那条线）
        if !editor.pendingWaypoints.isEmpty {
            return FCEdgePath.throughWaypoints(p0: p0, p1: p1, waypoints: editor.pendingWaypoints)
        }
        return FCRouter.route(p0: p0, n0: fromAnchor.vector, p1: p1, n1: n1,
                              obstacles: obstacles, avoid: avoid)
    }

    private func drawOverlays(_ ctx: inout GraphicsContext) {
        let accent = Color(nsColor: theme.accent)
        for id in editor.selection {
            guard let rect = editor.doc.rect(of: id) else { continue }
            let r = transform.r(rect).insetBy(dx: -2, dy: -2)
            var p = Path()
            p.addRect(r)
            ctx.stroke(p, with: .color(accent), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
        if editor.selection.count == 1, let id = editor.selection.first,
           let rect = editor.doc.rect(of: id), !editor.doc.edges.contains(where: { $0.id == id }) {
            let r = transform.r(rect)
            for h in FCHandle.corners {   // 只画角手柄；边中点让给连线锚点（hover 显示圆点）
                let c = h.point(in: r)
                let box = CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)
                ctx.fill(Path(roundedRect: box, cornerRadius: 1.5),
                         with: .color(Color(nsColor: theme.background)))
                ctx.stroke(Path(roundedRect: box, cornerRadius: 1.5), with: .color(accent), lineWidth: 1.5)
            }
        }
        // draw.io 式浮动连接点：源图形描边变亮 + 绿点跟随光标
        if let hover = hoverAnchor, let hp = hoverPoint,
           let node = editor.doc.nodes.first(where: { $0.id == hover.node }) {
            let rr = transform.r(node.rect).insetBy(dx: -2, dy: -2)
            ctx.stroke(Path(roundedRect: rr, cornerRadius: 5),
                       with: .color(accent.opacity(0.65)), lineWidth: 1.5)
            let q = transform.p(hp)
            let dot = CGRect(x: q.x - 5, y: q.y - 5, width: 10, height: 10)
            ctx.fill(Path(ellipseIn: dot), with: .color(accent))
            ctx.stroke(Path(ellipseIn: dot), with: .color(Color(nsColor: theme.background)), lineWidth: 1.5)
        }
        if let pending = editor.pendingEdge {
            // 实时预览就用**真正的正交路由**：跟着鼠标拐弯，指到哪个图形就吸附到哪条边。
            // 不再是「只有始末两点」的直虚线。
            let pts = pendingPreview(pending).map { transform.p($0) }
            var p = Path()
            FCRenderer.roundedPolyline(&p, pts, radius: transform.len(8))
            ctx.stroke(p, with: .color(accent.opacity(0.9)),
                       style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            // 手动断点：画成小方块，提示「这里已经断了，会从这儿继续」
            for w in editor.pendingWaypoints {
                let q = transform.p(w)
                let box = CGRect(x: q.x - 3.5, y: q.y - 3.5, width: 7, height: 7)
                ctx.fill(Path(roundedRect: box, cornerRadius: 1.5),
                         with: .color(Color(nsColor: theme.background)))
                ctx.stroke(Path(roundedRect: box, cornerRadius: 1.5),
                           with: .color(accent), lineWidth: 1.5)
            }
            if let tip = pts.last, let prev = pts.dropLast().last {
                ctx.fill(FCShape.arrow(tip: tip,
                                       direction: CGVector(dx: tip.x - prev.x, dy: tip.y - prev.y),
                                       size: 9),
                         with: .color(accent))
            }
            // 拉线过程中一直显示「还没走到终点」的实时像素距离（放下即消失）
            if let tip = pts.last, pts.count >= 2 {
                var total: CGFloat = 0
                for i in 1..<max(1, pts.count) {
                    total += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
                }
                if total > 1 {
                    FCRenderer.drawBadge(ctx: &ctx, theme: theme,
                                         at: CGPoint(x: tip.x + 20, y: tip.y - 18),
                                         text: "\(Int(total.rounded())) px")
                }
            }
        }
        // 拉线目标高亮（draw.io 式：光标贴到哪个图形，哪个整框变亮）
        if let tid = edgeTargetID, let node = editor.doc.nodes.first(where: { $0.id == tid }) {
            let r = transform.r(node.rect).insetBy(dx: -3, dy: -3)
            ctx.stroke(Path(roundedRect: r, cornerRadius: 6),
                       with: .color(accent), style: StrokeStyle(lineWidth: 2.5))
        }
        // 悬停连线：整条线加粗高亮（可点提示）
        if let hid = hoverEdgeID, let e = editor.doc.edges.first(where: { $0.id == hid }),
           let path = editor.doc.edgePath(e) {
            var p = Path()
            p.move(to: transform.p(path.start))
            for seg in path.segments {
                switch seg {
                case .line(let q): p.addLine(to: transform.p(q))
                case .cubic(let c0, let c1, let q):
                    p.addCurve(to: transform.p(q), control1: transform.p(c0), control2: transform.p(c1))
                }
            }
            ctx.stroke(p, with: .color(accent.opacity(0.45)),
                       style: StrokeStyle(lineWidth: max(4, transform.len(e.style.strokeWidth) + 3),
                                          lineCap: .round))
        }
        // 选中连线 → 两端端点手柄（可拖动改接）
        if editor.selection.count == 1, let id = editor.selection.first,
           let edge = editor.doc.edges.first(where: { $0.id == id }),
           let path = editor.doc.edgePath(edge),
           let s = path.polyline.first, let e = path.polyline.last {
            for pt in [s, e] {
                let q = transform.p(pt)
                let box = CGRect(x: q.x - 5, y: q.y - 5, width: 10, height: 10)
                ctx.fill(Path(ellipseIn: box), with: .color(Color(nsColor: theme.background)))
                ctx.stroke(Path(ellipseIn: box), with: .color(accent), lineWidth: 2)
            }
        }
        if let m = marquee {
            let r = transform.r(m)
            ctx.fill(Path(r), with: .color(Color(nsColor: theme.accent).opacity(0.12)))
            ctx.stroke(Path(r), with: .color(accent), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        // 缩放 / 画框时显示实时尺寸（像素）
        switch drag {
        case .resize(let id, _, _), .create(let id, _):
            if let rect = editor.doc.rect(of: id) {
                let r = transform.r(rect)
                FCRenderer.drawBadge(ctx: &ctx, theme: theme,
                                     at: CGPoint(x: r.midX, y: r.maxY + 14),
                                     text: "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded())) px")
            }
        default:
            break
        }
        if let x = guideX {
            var p = Path()
            p.move(to: CGPoint(x: transform.p(CGPoint(x: x, y: 0)).x, y: 0))
            p.addLine(to: CGPoint(x: transform.p(CGPoint(x: x, y: 0)).x, y: 100000))
            ctx.stroke(p, with: .color(Color(nsColor: NSColor.systemRed).opacity(0.6)), lineWidth: 0.8)
        }
        if let y = guideY {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: transform.p(CGPoint(x: 0, y: y)).y))
            p.addLine(to: CGPoint(x: 100000, y: transform.p(CGPoint(x: 0, y: y)).y))
            ctx.stroke(p, with: .color(Color(nsColor: NSColor.systemRed).opacity(0.6)), lineWidth: 0.8)
        }
    }

    @ViewBuilder
    private var editingOverlay: some View {
        if let id = editor.editingID, let rect = editor.doc.rect(of: id) {
            let r = transform.r(rect)
            FCTextEditor(text: editor.doc.text(of: id),
                         theme: theme,
                         align: editor.doc.style(of: id)?.align ?? .center,
                         bold: editor.doc.style(of: id)?.bold ?? false,
                         onChange: { value in editor.preview { $0.setText(id, value) } },
                         onEnd: { finishTextEditing() })
            .frame(width: max(90, r.width), height: max(30, r.height))
            .position(x: r.midX, y: r.midY)
        }
    }

    // MARK: 手势

    // MARK: 右键菜单

    /// 弹出右键菜单：命中的元素先自动选中，菜单项按类型给（图形 / 连线 / 空白）
    private func presentContextMenu(windowPoint: CGPoint, screen: CGPoint) {
        let local = FCContextGeometry.canvasPoint(windowPoint: windowPoint,
                                                  canvasFrameInWindow: scrollTarget.view?.frameInWindow)
        let p = transform.doc(local)
        // 正在拉线：右键 = 在这里落一个断点，线从断点继续拉（不弹菜单）
        if let pending = editor.pendingEdge {
            var point = p
            if editor.doc.snap {
                point = CGPoint(x: (p.x / 5).rounded() * 5, y: (p.y / 5).rounded() * 5)
            }
            editor.pendingWaypoints.append(point)
            // 断点落下后就转入「点击-点击」继续模式：即使左键松了，线也还挂在光标上，
            // 可以继续右键落断点、或点目标框收尾
            edgeStartNode = pending.from
            editor.pendingEdge = (from: pending.from, anchor: pending.anchor, point: point)
            return
        }
        let hitID = editor.doc.hit(p, tolerance: 11 / max(editor.zoom, 0.2))
        if let id = hitID, !editor.selection.contains(id) { editor.selection = [id] }
        let entries = FCContextMenu.entries(doc: editor.doc, selection: editor.selection,
                                            hitID: hitID, at: p)
        let menu = buildMenu(entries, hitID: hitID, at: p)
        menu.popUp(positioning: nil, at: screen, in: nil)
    }

    /// 纯描述 → NSMenu（动作在这里落到 editor）
    private func buildMenu(_ entries: [FCMenuEntry], hitID: String?, at p: CGPoint) -> NSMenu {
        let menu = NSMenu()
        for entry in entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .submenu(let title, let children):
                let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                parent.submenu = buildMenu(children, hitID: hitID, at: p)
                menu.addItem(parent)
            case .item(let title, let checked, let action):
                let item = menuItem(title) { perform(action, hitID: hitID, at: p) }
                item.state = checked ? .on : .off
                menu.addItem(item)
            }
        }
        return menu
    }

    private func perform(_ action: FCMenuAction, hitID: String?, at p: CGPoint) {
        switch action {
        case .editText, .editLabel:
            if let id = hitID { beginEdit(id) }
        case .duplicate:
            editor.duplicateSelection()
        case .bringToFront:
            let ids = editor.selection; editor.commit { $0.bringToFront(ids) }
        case .sendToBack:
            let ids = editor.selection; editor.commit { $0.sendToBack(ids) }
        case .startEdge:
            if let id = hitID {
                editor.tool = .edge
                edgeStartNode = id
                editor.pendingEdge = (from: id, anchor: .auto, point: p)
            }
        case .delete:
            editor.deleteSelection()
        case .route(let r):
            editor.applyEdges { $0.route = r }
        case .arrow(let a):
            editor.applyEdges { $0.arrow = a }
        case .newProcess:
            let node = FCNode(kind: .rect, origin: p)
            editor.commit { $0.nodes.append(node) }
            editor.selection = [node.id]
        case .paste:
            editor.pasteFromClipboard(at: p)
        case .toggleGrid:
            editor.commit { $0.showGrid.toggle() }
        case .selectAll:
            editor.selection = editor.allIDs
        case .fit:
            editor.fit(in: editor.canvasSize)
        }
    }

    private func beginEdit(_ id: String) {
        editor.selection = [id]
        editor.editingID = id
        editor.beginInteraction()
    }

    /// 取消整条拉线（含已落的手动断点）
    private func cancelDrawing() {
        editor.pendingEdge = nil
        editor.pendingWaypoints = []
        edgeStartNode = nil
        edgeTargetID = nil
        lastBlankClickAt = .distantPast
    }

    /// 收尾：把当前拉线连到目标框（用起点边 + 落点边 + 手动断点）
    private func finishDrawing(at p: CGPoint, target: FCNode) {
        guard let from = edgeStartNode else { cancelDrawing(); return }
        let source = editor.doc.nodes.first { $0.id == from }
        let fromAnchor: FCAnchor = edgeStartAnchor != .auto
            ? edgeStartAnchor
            : (source.map { FCEdgePath.autoAnchor(from: $0.rect, toward: target.rect) } ?? .right)
        var edge = FCEdge(fromNode: from, toNode: target.id,
                          fromAnchor: fromAnchor,
                          toAnchor: nearestAnchor(to: p, node: target))
        edge.waypoints = editor.pendingWaypoints
        editor.commit { $0.edges.append(edge) }
        editor.selection = [edge.id]
        editor.pendingWaypoints = []
        editor.pendingEdge = nil
        edgeStartNode = nil
        edgeTargetID = nil
        lastBlankClickAt = .distantPast
    }

    /// 菜单项包装（闭包 → target/action）
    private func menuItem(_ title: String, _ run: @escaping () -> Void) -> NSMenuItem {
        let target = FCMenuTarget(run)
        let item = NSMenuItem(title: title, action: #selector(FCMenuTarget.fire), keyEquivalent: "")
        item.target = target
        item.representedObject = target   // 保活：NSMenuItem 的 target 是弱引用
        return item
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in dragChanged(value) }
            .onEnded { value in dragEnded(value) }
    }

    private func dragChanged(_ value: DragGesture.Value) {
        // 点画布任意处 = 结束文字编辑（NSTextView 不一定会失焦）
        if editor.editingID != nil, case .none = drag { finishTextEditing() }
        let start = transform.doc(value.startLocation)
        let current = transform.doc(value.location)
        switch drag {
        case .none:
            if editor.tool == .edge {
                // 连线工具：按下先记住起点图形；移动 = 拖拽连线预览，原地松开 = 点击-点击流程
                if edgePressNode == nil { edgePressNode = editor.doc.node(at: start)?.id }
                if let from = edgePressNode {
                    editor.pendingEdge = (from: from, anchor: .auto, point: current)
                }
            } else {
                beginDrag(at: start, current: current)
            }

        case .pan(let startOffset, let startPoint):
            editor.offset = CGSize(width: startOffset.width + (value.location.x - startPoint.x),
                                   height: startOffset.height + (value.location.y - startPoint.y))

        case .move(let s, let origins, let ids):
            var dx = current.x - s.x
            var dy = current.y - s.y
            if editor.doc.snap {
                let snapped = snapTranslation(ids: ids, origins: origins, dx: dx, dy: dy)
                dx = snapped.dx
                dy = snapped.dy
            }
            editor.preview { doc in
                for (id, origin) in origins {
                    if let i = doc.nodes.firstIndex(where: { $0.id == id }) {
                        doc.nodes[i].x = origin.minX + dx
                        doc.nodes[i].y = origin.minY + dy
                    } else if let i = doc.texts.firstIndex(where: { $0.id == id }) {
                        doc.texts[i].x = origin.minX + dx
                        doc.texts[i].y = origin.minY + dy
                    } else if let i = doc.groups.firstIndex(where: { $0.id == id }) {
                        doc.groups[i].x = origin.minX + dx
                        doc.groups[i].y = origin.minY + dy
                    }
                }
                // 手动断点跟着图形一起走（否则移动后线会歪掉）
                for i in doc.edges.indices {
                    let e = doc.edges[i]
                    guard !e.waypoints.isEmpty else { continue }
                    guard ids.contains(e.fromNode) || ids.contains(e.toNode) else { continue }
                    for j in doc.edges[i].waypoints.indices {
                        doc.edges[i].waypoints[j].x += dx
                        doc.edges[i].waypoints[j].y += dy
                    }
                }
            }

        case .resize(let id, let handle, let original):
            var dx = current.x - start.x
            var dy = current.y - start.y
            if editor.doc.snap {
                dx = (dx / 5).rounded() * 5
                dy = (dy / 5).rounded() * 5
            }
            let rect = handle.apply(original, dx: dx, dy: dy)
            editor.preview { doc in doc.setRect(id, rect) }

        case .create(let id, let start):
            let rect = CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                              width: abs(current.x - start.x), height: abs(current.y - start.y))
            editor.preview { doc in
                doc.setRect(id, rect.width < 20 || rect.height < 20
                                ? CGRect(origin: start, size: doc.rect(of: id)?.size ?? CGSize(width: 140, height: 64))
                                : rect)
            }

        case .maybeEdge(let node, let anchor, let start):
            // 拖够距离 → 正式起线（此后和边缘拉线完全一样）
            guard FCDrawGate.shouldStartEdge(from: start, to: current, zoom: editor.zoom) else { break }
            drag = .edge(from: node, anchor: anchor)
            editor.pendingWaypoints = []
            edgeStartNode = node
            edgeStartAnchor = anchor
            editor.pendingEdge = (from: node, anchor: anchor, point: current)
            let hovered = editor.doc.node(at: current)?.id
                ?? nearestNode(to: current, within: 26 / max(editor.zoom, 0.2))?.id
            edgeTargetID = hovered

        case .edge(let from, let anchor):
            editor.pendingEdge = (from: from, anchor: anchor, point: current)
            // draw.io 式目标高亮：光标进入/贴近某个图形时整框变亮
            let hovered = editor.doc.node(at: current)?.id
                ?? nearestNode(to: current, within: 26 / max(editor.zoom, 0.2))?.id
            edgeTargetID = hovered      // 悬停到自己 = 自环（写循环）

        case .reconnect(let id, let isFrom):
            // 预览：固定端 → 光标（复用 pendingEdge 的虚线 + 箭头绘制）
            if let edge = editor.doc.edges.first(where: { $0.id == id }) {
                let fixedNode = isFrom ? edge.toNode : edge.fromNode
                editor.pendingEdge = (from: fixedNode, anchor: .auto, point: current)
            }
            let hovered = editor.doc.node(at: current)?.id
                ?? nearestNode(to: current, within: 26 / max(editor.zoom, 0.2))?.id
            edgeTargetID = hovered

        case .marquee(let start):
            marquee = CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                             width: abs(current.x - start.x), height: abs(current.y - start.y))
        }
    }

    private func dragEnded(_ value: DragGesture.Value) {
        let current = transform.doc(value.location)
        let screenMovedAll = hypot(value.location.x - value.startLocation.x,
                                   value.location.y - value.startLocation.y)

        // ── 拉线中（任何工具：选择工具从边缘拖、或「连线」工具点-点）──
        // · 点节点 = 收尾连接
        // · 双击空白 = 取消整条拉线（含断点）
        // · 单击空白 = 不取消，线继续挂在光标上
        let drawing = editor.pendingEdge != nil || edgeStartNode != nil
            || !editor.pendingWaypoints.isEmpty
        if drawing, screenMovedAll < 3 {
            let hitNode = editor.doc.node(at: current)
            switch FCDrawGate.action(drawing: drawing, moved: false, onNode: hitNode != nil,
                                     lastBlankClick: lastBlankClickAt, now: Date()) {
            case .finish:
                // 点自己收尾 = 误操作（想要自环请从边缘拖出去再拖回来）：这里直接取消
                if let target = hitNode, target.id == edgeStartNode {
                    cancelDrawing()
                } else if let target = hitNode {
                    finishDrawing(at: current, target: target)
                }
            case .cancel:
                lastBlankClickAt = .distantPast
                cancelDrawing()
            case .keep:
                lastBlankClickAt = Date()
                if let from = edgeStartNode {
                    editor.pendingEdge = (from: from, anchor: edgeStartAnchor, point: current)
                }
            case .idle:
                break
            }
            drag = .none
            return
        }

        // 连线工具（drag == .none 分支接管）：
        // · 移动超过阈值 = 拖拽连线（起点图形 → 落点图形）
        // · 原地松开 = 点击-点击连线（第一次点 = 起点；点目标 = 连线）
        // · 拉线中「双击空白」= 取消整条线；单击空白只让线继续挂在光标上
        if editor.tool == .edge, case .none = drag {
            let moved = hypot(value.location.x - value.startLocation.x,
                              value.location.y - value.startLocation.y) >= 3
            let hitNode = editor.doc.node(at: current)
            if moved {
                if let from = edgePressNode, let target = hitNode {
                    edgeStartNode = from
                    if let src = editor.doc.nodes.first(where: { $0.id == from }) {
                        edgeStartAnchor = nearestAnchor(to: transform.doc(value.startLocation), node: src)
                    }
                    finishDrawing(at: current, target: target)
                }
                editor.pendingWaypoints = []
                edgeStartNode = nil
                editor.pendingEdge = nil
            } else if let sid = edgeStartNode {
                // 点节点已在上面统一收尾；这里只处理「起点已定 + 点空白」= 继续拉
                editor.pendingEdge = (from: sid, anchor: edgeStartAnchor, point: current)
            } else if let node = hitNode {
                edgeStartNode = node.id
                edgeStartAnchor = nearestAnchor(to: current, node: node)   // 点在哪条边就从哪条边出
                editor.pendingWaypoints = []      // 新的一条线
                editor.pendingEdge = (from: node.id, anchor: edgeStartAnchor, point: current)
            }
            edgePressNode = nil
            lastClickAt = .distantPast
            return
        }

        // 双击节点 → 进入文字编辑。
        // 画布的 DragGesture(minimumDistance: 0) 会在第一次 mousedown 就参与手势竞争，
        // SwiftUI 的 .onTapGesture(count: 2) 永远收不到事件 —— 这里自判「无位移的两次点击」。
        let screenMoved = hypot(value.location.x - value.startLocation.x,
                                value.location.y - value.startLocation.y)
        let p = transform.doc(value.location)
        let hitID = editor.doc.hit(p, tolerance: 11 / max(editor.zoom, 0.2))
        let clickLike: Bool = {
            switch drag {
            case .move, .maybeEdge: return hitID != nil   // 点中元素（边缘按下没拖动 = 普通点击）
            case .marquee: return hitID == nil       // 点空白
            default: return false
            }
        }()
        if screenMoved < 3, clickLike {
            let now = Date()
            if now.timeIntervalSince(lastClickAt) < 0.45 {
                lastClickAt = .distantPast
                if case .move = drag { editor.endInteraction() }
                drag = .none
                marquee = nil
                guideX = nil
                guideY = nil
                if hitID != nil {
                    beginTextEditing(at: p)          // 双击图形 → 改文字
                } else {
                    // 双击空白 → 新建矩形（draw.io 习惯）
                    let node = FCNode(kind: .rect, origin: p)
                    editor.commit { $0.nodes.append(node) }
                    editor.selection = [node.id]
                }
                return
            }
            lastClickAt = now
        }

        switch drag {
        case .none, .pan:
            break
        case .move, .resize, .create:
            // 画完一个图形自动回「选择」工具（Figma 惯例）：否则继续点击画布会不断叠新图形
            if case .create = drag { editor.tool = .select }
            editor.endInteraction()
        case .maybeEdge(let node, _, _):
            // 没拖动就松手 = 普通点击：选中这个图形（双击则由上面的自判逻辑进入改文字）
            if let id = editor.doc.hit(current, tolerance: 11 / max(editor.zoom, 0.2)) {
                editor.selection = [id]
            } else if editor.doc.nodes.contains(where: { $0.id == node }) {
                editor.selection = [node]
            }
        case .edge(let from, let anchor):
            edgeTargetID = nil
            // 落点吸附：精确命中优先，其次贴近图形 26pt 内也接住（draw.io 手感）
            let tol = 26 / max(editor.zoom, 0.2)
            if let target = editor.doc.node(at: current)
                ?? nearestNode(to: current, within: tol)
                ?? editor.doc.node(at: transform.doc(value.startLocation)) {
                var edge = FCEdge(fromNode: from, toNode: target.id,
                                  fromAnchor: anchor,
                                  toAnchor: nearestAnchor(to: current, node: target))
                edge.waypoints = editor.pendingWaypoints
                editor.commit { $0.edges.append(edge) }
                editor.selection = [edge.id]
                editor.pendingWaypoints = []
                edgeStartNode = nil
                editor.pendingEdge = nil
            } else {
                // 空白处松手：不取消，转成「点击-点击」继续拉
                // （已落的断点保留；点目标框收尾，双击空白 / Esc 取消）
                edgeStartNode = from
                editor.pendingEdge = (from: from, anchor: anchor, point: current)
            }
        case .reconnect(let id, let isFrom):
            defer { editor.pendingEdge = nil }
            defer { edgeTargetID = nil }
            let tol = 26 / max(editor.zoom, 0.2)
            if let target = editor.doc.node(at: current) ?? nearestNode(to: current, within: tol),
               let idx = editor.doc.edges.firstIndex(where: { $0.id == id }),
               editor.doc.nodes.contains(where: { $0.id == target.id }) {
                let side = nearestAnchor(to: current, node: target)
                editor.commit { doc in
                    if isFrom {
                        doc.edges[idx].fromNode = target.id
                        doc.edges[idx].fromAnchor = side
                    } else {
                        doc.edges[idx].toNode = target.id
                        doc.edges[idx].toAnchor = side
                    }
                }
            }
        case .marquee(let start):
            if let m = marquee {
                editor.selection = editor.doc.ids(in: m)
            }
            marquee = nil
            if abs(current.x - start.x) < 3, abs(current.y - start.y) < 3 {
                editor.selection = []
            }
        }
        drag = .none
        guideX = nil
        guideY = nil
        _ = value
    }

    private func beginDrag(at start: CGPoint, current: CGPoint) {
        let mods = NSEvent.modifierFlags
        let panRequested = mods.contains(.option)

        if panRequested {
            drag = .pan(startOffset: editor.offset, start: start)
            return
        }

        // 1) 已选中单个元素 → 角手柄缩放（draw.io：角 = 缩放，最高优先）
        if editor.selection.count == 1, let id = editor.selection.first,
           let rect = editor.doc.rect(of: id), !editor.doc.edges.contains(where: { $0.id == id }) {
            for h in FCHandle.corners {
                let c = h.point(in: rect)
                if hypot(c.x - start.x, c.y - start.y) <= 7 / max(editor.zoom, 0.2) {
                    editor.beginInteraction()
                    drag = .resize(id: id, handle: h, original: rect)
                    return
                }
            }
        }

        // 2) 选中单条连线 → 拖端点改接（draw.io：端点手柄 ±8pt）。
        //    必须先于浮动锚点：端点手柄天然落在图形边缘的锚点带内，锚点优先会把它永远抢走。
        if editor.selection.count == 1, let id = editor.selection.first,
           let edge = editor.doc.edges.first(where: { $0.id == id }),
           let path = editor.doc.edgePath(edge),
           let s = path.polyline.first, let e = path.polyline.last {
            let tol = 13 / max(editor.zoom, 0.2)
            if hypot(s.x - start.x, s.y - start.y) <= tol {
                drag = .reconnect(id: id, isFrom: true)
                editor.pendingEdge = nil
                return
            }
            if hypot(e.x - start.x, e.y - start.y) <= tol {
                drag = .reconnect(id: id, isFrom: false)
                editor.pendingEdge = nil
                return
            }
        }

        // 3) 图形边缘 → 拉连线（draw.io 浮动连接：边缘 14pt 带内任意位置，
        //    自动吸附最近边；角已被上一分支占用，互不冲突）
        if let anchorHit = anchorHit(at: start) {
            // 先不急着起线：真正拖动超过阈值才起线，否则这次按下只是「点选 / 拖动图形」
            // （以前只要按在边缘 14pt 内就起线，点一下也会留一条挂着的线，最后误连成自环）
            drag = .maybeEdge(node: anchorHit.node, anchor: anchorHit.anchor, start: start)
            return
        }

        // 3) 工具：新建元素
        if let kind = editor.tool.shape {
            let node = FCNode(kind: kind, origin: start)   // 形状不带默认文字
            editor.beginInteraction()
            editor.preview { $0.nodes.append(node) }
            editor.selection = [node.id]
            drag = .create(id: node.id, start: start)
            return
        }
        if editor.tool == .text {
            let item = FCTextItem(origin: start)
            editor.commit { $0.texts.append(item) }
            editor.selection = [item.id]
            editor.editingID = item.id
            editor.beginInteraction()
            editor.tool = .select      // 即用即销：放一个就回选择工具，避免连点连建
            drag = .none
            return
        }
        if editor.tool == .group {
            let group = FCGroup(origin: start)
            editor.beginInteraction()
            editor.preview { $0.groups.insert(group, at: 0) }
            editor.selection = [group.id]
            drag = .create(id: group.id, start: start)
            return
        }
        // 4) 选择工具：点中元素 → 选择 / 移动（群组连带子元素）
        if let id = editor.doc.hit(start, tolerance: 11 / max(editor.zoom, 0.2)) {
            let shift = mods.contains(.shift)
            if shift {
                if editor.selection.contains(id) { editor.selection.remove(id) } else { editor.selection.insert(id) }
            } else if !editor.selection.contains(id) {
                editor.selection = [id]
            }
            let ids = expandGroups(editor.selection)
            var origins: [String: CGRect] = [:]
            for i in ids {
                if let r = editor.doc.rect(of: i), !editor.doc.edges.contains(where: { $0.id == i }) {
                    origins[i] = r
                }
            }
            if !origins.isEmpty {
                editor.beginInteraction()
                drag = .move(start: start, origins: origins, ids: Set(origins.keys))
            }
            return
        }

        // 5) 空白 → 框选
        drag = .marquee(start: start)
    }

    /// 分组被选中时，框内的图形 / 文本一起移动
    private func expandGroups(_ ids: Set<String>) -> Set<String> {
        var out = ids
        for g in editor.doc.groups where ids.contains(g.id) {
            let box = g.rect
            for n in editor.doc.nodes where box.contains(n.center) { out.insert(n.id) }
            for t in editor.doc.texts where box.contains(CGPoint(x: t.rect.midX, y: t.rect.midY)) {
                out.insert(t.id)
            }
        }
        return out
    }

    /// 对齐吸附（同时给出红色参考线）
    private func snapTranslation(ids: Set<String>, origins: [String: CGRect],
                                 dx: CGFloat, dy: CGFloat) -> (dx: CGFloat, dy: CGFloat) {
        let threshold: CGFloat = 6
        var box: CGRect?
        for (_, r) in origins { box = box.map { $0.union(r) } ?? r }
        guard let moving = box else { return (dx, dy) }
        let moved = moving.offsetBy(dx: dx, dy: dy)
        var bestX: (delta: CGFloat, guide: CGFloat)?
        var bestY: (delta: CGFloat, guide: CGFloat)?
        let others = editor.doc.nodes.filter { !ids.contains($0.id) }.map(\.rect)
            + editor.doc.texts.filter { !ids.contains($0.id) }.map(\.rect)
            + editor.doc.groups.filter { !ids.contains($0.id) }.map(\.rect)
        for r in others {
            for (a, b) in [(moved.minX, r.minX), (moved.midX, r.midX), (moved.maxX, r.maxX)] {
                let d = b - a
                if abs(d) <= threshold, bestX == nil || abs(d) < abs(bestX!.delta) {
                    bestX = (d, b)
                }
            }
            for (a, b) in [(moved.minY, r.minY), (moved.midY, r.midY), (moved.maxY, r.maxY)] {
                let d = b - a
                if abs(d) <= threshold, bestY == nil || abs(d) < abs(bestY!.delta) {
                    bestY = (d, b)
                }
            }
        }
        guideX = bestX?.guide
        guideY = bestY?.guide
        var outX = dx + (bestX?.delta ?? 0)
        var outY = dy + (bestY?.delta ?? 0)
        // 没有对齐参考时退化为 5pt 网格吸附
        if bestX == nil { outX = (outX / 5).rounded() * 5 }
        if bestY == nil { outY = (outY / 5).rounded() * 5 }
        return (outX, outY)
    }

    private func nearestAnchor(to p: CGPoint, node: FCNode) -> FCAnchor {
        FCEdgePath.nearestAnchor(to: p, in: node.rect)
    }

    /// 光标是否贴近某个图形的锚点（用于显示锚点 + 直接拉线）
    private func anchorHit(at p: CGPoint) -> (node: String, anchor: FCAnchor)? {
        // draw.io 式浮动连接：图形边缘 14pt 带内任意位置都能起线，
        // 自动吸附到最近的那条边（角手柄在 beginDrag 里优先处理，不受这里影响）。
        let tolerance = 14 / max(editor.zoom, 0.2)
        var best: (node: String, anchor: FCAnchor, dist: CGFloat)?
        for node in editor.doc.nodes.reversed() {
            let r = node.rect
            let edges: [(FCAnchor, CGFloat)] = [
                (.top, Self.distToSegment(p, CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY))),
                (.bottom, Self.distToSegment(p, CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY))),
                (.left, Self.distToSegment(p, CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.minX, y: r.maxY))),
                (.right, Self.distToSegment(p, CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY))),
            ]
            for (a, d) in edges where d <= tolerance {
                if best == nil || d < best!.dist {
                    best = (node.id, a, d)
                }
            }
        }
        return best.map { ($0.node, $0.anchor) }
    }

    /// 点到线段距离（浮动连接命中用）
    private static func distToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0.0001 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// 距离某点最近的图形（落点吸附；tol 为图形外容许距离）
    private func nearestNode(to p: CGPoint, within tol: CGFloat) -> FCNode? {
        var best: (FCNode, CGFloat)?
        for n in editor.doc.nodes {
            let dx = max(max(n.rect.minX - p.x, 0), p.x - n.rect.maxX)
            let dy = max(max(n.rect.minY - p.y, 0), p.y - n.rect.maxY)
            let d = hypot(dx, dy)
            if d <= tol, best == nil || d < best!.1 { best = (n, d) }
        }
        return best?.0
    }

    private func updateHover(_ p: CGPoint) {
        // 连线工具已选起点：预览线跟随鼠标 + 目标图形高亮（点击-点击连线的中间态）
        if let sid = edgeStartNode {
            editor.pendingEdge = (from: sid, anchor: .auto, point: p)
            edgeTargetID = editor.doc.node(at: p)?.id   // 点回自己 = 自环
            return
        }
        if let hit = anchorHit(at: p) {
            hoverAnchor = hit
            hoverPoint = p
            hoverEdgeID = nil
        } else if let e = editor.doc.edge(at: p, tolerance: 11 / max(editor.zoom, 0.2)) {
            // 连线悬停：整条线加粗变亮（draw.io 手感——细线也不再"点不中看不见"）
            hoverEdgeID = e.id
            hoverAnchor = nil
            hoverPoint = nil
        } else if let node = editor.doc.node(at: p) {
            hoverAnchor = (node.id, .auto)
            hoverPoint = nil
            hoverEdgeID = nil
        } else {
            hoverAnchor = nil
            hoverPoint = nil
            hoverEdgeID = nil
        }
    }

    private func beginTextEditing(at p: CGPoint) {
        guard let id = editor.doc.hit(p, tolerance: 11 / max(editor.zoom, 0.2)) else { return }
        if editor.doc.edges.contains(where: { $0.id == id }) {
            guard let edge = editor.doc.edges.first(where: { $0.id == id }), edge.label.isEmpty else {
                editor.selection = [id]
                editor.editingID = id
                editor.beginInteraction()
                return
            }
        }
        editor.selection = [id]
        if editor.doc.nodes.contains(where: { $0.id == id }) {
            editor.editingID = id
            editor.beginInteraction()
            return
        }
        editor.editingID = id
        editor.beginInteraction()
    }

    private func finishTextEditing() {
        editor.editingID = nil
        editor.endInteraction()
    }

    // MARK: 滚轮 / 触控板（⌘+滚轮缩放 · 双指滚动平移 · 捏合缩放）

    private func installScrollMonitors() {
        guard scrollMonitor == nil else { return }
        let target = scrollTarget
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
            guard let win = event.window, win.isKeyWindow,
                  let frame = target.view?.frameInWindow, frame.width > 1,
                  frame.contains(event.locationInWindow) else {
                return event
            }
            let local = CGPoint(x: event.locationInWindow.x - frame.minX,
                                y: frame.maxY - event.locationInWindow.y)
            if event.modifierFlags.contains(.command) {
                let factor = 1 + event.scrollingDeltaY * 0.006
                zoom(around: local, factor: factor)
            } else {
                editor.offset.width += event.scrollingDeltaX
                editor.offset.height += event.scrollingDeltaY
            }
            return nil
        }
        magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify]) { event in
            guard let win = event.window, win.isKeyWindow,
                  let frame = target.view?.frameInWindow, frame.width > 1,
                  frame.contains(event.locationInWindow) else {
                return event
            }
            let local = CGPoint(x: event.locationInWindow.x - frame.minX,
                                y: frame.maxY - event.locationInWindow.y)
            zoom(around: local, factor: 1 + event.magnification)
            return nil
        }
    }

    private func removeScrollMonitors() {
        if let m = scrollMonitor { NSEvent.removeMonitor(m) }
        if let m = magnifyMonitor { NSEvent.removeMonitor(m) }
        scrollMonitor = nil
        magnifyMonitor = nil
    }

    private func zoom(around local: CGPoint, factor: CGFloat) {
        let old = editor.zoom
        let next = min(max(old * factor, 0.2), 4)
        guard abs(next - old) > 0.0001 else { return }
        let docPoint = CGPoint(x: (local.x - editor.offset.width) / old,
                               y: (local.y - editor.offset.height) / old)
        editor.zoom = next
        editor.offset = CGSize(width: local.x - docPoint.x * next,
                               height: local.y - docPoint.y * next)
    }
}

// MARK: - 内联文字编辑（AppKit NSTextView：打开即全选，直接输入就替换旧文字）

private struct FCTextEditor: NSViewRepresentable {
    let text: String
    let theme: FlowchartTheme
    let align: FCTextAlign
    let bold: Bool
    let onChange: (String) -> Void
    let onEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = FCTextScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 6
        scroll.layer?.borderWidth = 1.5
        scroll.layer?.borderColor = theme.accent.cgColor
        scroll.layer?.backgroundColor = theme.surface.cgColor

        let tv = NSTextView()
        tv.delegate = context.coordinator
        tv.drawsBackground = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.textContainerInset = CGSize(width: 4, height: 4)
        tv.font = theme.nsFont(size: 13, bold: bold)
        tv.textColor = theme.text
        tv.insertionPointColor = theme.accent
        tv.alignment = align.nsAlignment
        tv.string = text
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        scroll.documentView = tv
        context.coordinator.textView = tv
        scroll.onAttach = { [weak coordinator = context.coordinator] in
            coordinator?.focus(selectAll: true)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView else { return }
        // 只在「没有正在编辑、也没有输入法组合」时才回填文本：
        // 组合中替换字符串会让中文输入重复上屏（候选串被取消后重新提交）
        if tv.string != text, !context.coordinator.editing, !tv.hasMarkedText() { tv.string = text }
        tv.font = theme.nsFont(size: 13, bold: bold)
        tv.textColor = theme.text
        tv.alignment = align.nsAlignment
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FCTextEditor
        weak var textView: NSTextView?
        /// 正在编辑时不回写 string，避免打断输入 / 光标跳动
        var editing = false
        private var focusedOnce = false

        init(_ parent: FCTextEditor) { self.parent = parent }

        func textDidBeginEditing(_ notification: Notification) {
            editing = true
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.onChange(tv.string)
        }

        func textDidEndEditing(_ notification: Notification) {
            editing = false
            parent.onEnd()
        }

        /// Esc = 结束编辑（Enter 保留为换行）
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEnd()
                return true
            }
            return false
        }

        /// 挂进窗口后自己抢焦点并**全选已有文字**：
        /// 双击改字时直接输入就是替换，不用先手动选中。
        func focus(selectAll: Bool) {
            guard let tv = textView, let win = tv.window else { return }
            win.makeFirstResponder(tv)
            if selectAll, !tv.string.isEmpty {
                tv.selectAll(nil)
            } else {
                tv.setSelectedRange(NSRange(location: tv.string.count, length: 0))
            }
            focusedOnce = true
        }

        var hasFocused: Bool { focusedOnce }
    }
}

// MARK: - 右键支持（左键完全放行给 SwiftUI 手势）

/// 菜单项包装：NSMenuItem 的 target 是弱引用，靠 representedObject 保活
final class FCMenuTarget: NSObject {
    private let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire() { run() }
}

/// 只在**右键**时参与命中测试的透明视图：
/// 左键返回 nil，SwiftUI 的拖拽/点选手势不受影响。
final class FCRightClickView: NSView {
    /// (窗口坐标, 屏幕坐标)
    var onContextMenu: ((CGPoint, NSPoint) -> Void)?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        switch NSApp.currentEvent?.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return super.hitTest(point)
        default:
            return nil
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        // 注意：toScreen 要的是**窗口坐标**（event.locationInWindow），
        // 不能先把点转成视图坐标再当窗口坐标用（菜单会飘到别处）
        let screen = window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
        onContextMenu?(event.locationInWindow, screen)
    }
}

struct FCRightClickCatcher: NSViewRepresentable {
    let onMenu: (CGPoint, NSPoint) -> Void

    func makeNSView(context: Context) -> FCRightClickView {
        let v = FCRightClickView()
        v.onContextMenu = onMenu
        return v
    }

    func updateNSView(_ nsView: FCRightClickView, context: Context) {
        nsView.onContextMenu = onMenu
    }
}

/// 挂进窗口后回调（延后一拍抢焦点，避免布局期改状态）
private final class FCTextScrollView: NSScrollView {
    var onAttach: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in self?.onAttach?() }
    }
}


// MARK: - 画布在窗口中的位置（滚轮命中判断用）
//
// 这一层只负责「记住自己在窗口里的位置」，**不回写任何 SwiftUI 状态**：
// 在 NSView.layout() 里改 @State/@Published 会让 AppKit 在布局过程中
// 收到约束更新请求，然后抛异常直接崩（`_postWindowNeedsUpdateConstraints`）。

final class FCScrollTargetBox {
    weak var view: FCScrollTargetView?
}

final class FCScrollTargetView: NSView {
    private(set) var frameInWindow: CGRect = .zero

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refresh()
    }

    override func layout() {
        super.layout()
        refresh()
    }

    func refresh() {
        guard window != nil else { return }
        frameInWindow = convert(bounds, to: nil)
    }
}

private struct FCScrollTargetReporter: NSViewRepresentable {
    let box: FCScrollTargetBox

    func makeNSView(context: Context) -> FCScrollTargetView {
        let view = FCScrollTargetView()
        box.view = view
        return view
    }

    func updateNSView(_ nsView: FCScrollTargetView, context: Context) {
        box.view = nsView
        nsView.refresh()
    }
}

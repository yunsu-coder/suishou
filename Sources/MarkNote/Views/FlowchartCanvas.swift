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

enum FCRenderer {

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
                        ctx: inout GraphicsContext) {
        let index = doc.nodesByID()
        for g in doc.groups { group(g, theme: theme, transform: transform, ctx: &ctx) }
        for e in doc.edges { edge(e, nodes: index, theme: theme, transform: transform, ctx: &ctx) }
        for n in doc.nodes { node(n, theme: theme, transform: transform, ctx: &ctx) }
        for t in doc.texts { textItem(t, theme: theme, transform: transform, ctx: &ctx) }
    }

    static func node(_ n: FCNode, theme: FlowchartTheme, transform: FCViewTransform,
                     ctx: inout GraphicsContext) {
        let rect = transform.r(n.rect)
        let path = FCShape.path(kind: n.kind, rect: rect, corner: transform.len(n.style.corner))
        let fill = NSColor.fcHex(n.style.fill) ?? theme.defaultFill()
        let stroke = NSColor.fcHex(n.style.stroke) ?? theme.defaultStroke()
        let lineWidth = max(0.5, transform.len(n.style.strokeWidth))
        let dash: [CGFloat] = n.style.dashed ? [max(2, lineWidth * 4), max(2, lineWidth * 3)] : []

        if n.style.shadow {
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: Color.black.opacity(0.18), radius: transform.len(5),
                                        x: 0, y: transform.len(2)))
                layer.fill(path, with: .color(Color(nsColor: fill)))
            }
        } else {
            ctx.fill(path, with: .color(Color(nsColor: fill)))
        }
        ctx.stroke(path, with: .color(Color(nsColor: stroke)),
                   style: StrokeStyle(lineWidth: lineWidth, dash: dash))
        if let detail = FCShape.detail(kind: n.kind, rect: rect) {
            ctx.stroke(detail, with: .color(Color(nsColor: stroke)), lineWidth: lineWidth)
        }
        textBlock(n.text, in: rect, style: n.style, theme: theme,
                  transform: transform, ctx: &ctx,
                  verticalInset: n.kind == .cylinder ? transform.len(10) : transform.len(6))
    }

    static func textItem(_ t: FCTextItem, theme: FlowchartTheme, transform: FCViewTransform,
                         ctx: inout GraphicsContext) {
        let rect = transform.r(t.rect)
        textBlock(t.text, in: rect, style: t.style, theme: theme, transform: transform, ctx: &ctx)
    }

    static func group(_ g: FCGroup, theme: FlowchartTheme, transform: FCViewTransform,
                      ctx: inout GraphicsContext) {
        let rect = transform.r(g.rect)
        let path = Path(roundedRect: rect, cornerRadius: transform.len(max(4, g.style.corner)))
        let stroke = NSColor.fcHex(g.style.stroke) ?? theme.secondary
        let fill = NSColor.fcHex(g.style.fill)
        if let fill {
            ctx.fill(path, with: .color(Color(nsColor: fill)))
        }
        let lineWidth = max(0.5, transform.len(g.style.strokeWidth))
        let dash: [CGFloat] = g.style.dashed ? [max(3, lineWidth * 4), max(3, lineWidth * 3)] : []
        ctx.stroke(path, with: .color(Color(nsColor: stroke)),
                   style: StrokeStyle(lineWidth: lineWidth, dash: dash))
        guard !g.title.isEmpty else { return }
        let font = theme.nsFont(size: g.style.fontSize, bold: g.style.bold || true, display: true)
        let lines = FCTextLayout.lines(g.title, width: max(20, rect.width - transform.len(16)), font: font)
        let lh = FCTextLayout.lineHeight(font)
        let color = NSColor.fcHex(g.style.text) ?? theme.text
        for (i, line) in lines.enumerated() {
            ctx.draw(Text(line).font(theme.font(size: g.style.fontSize, bold: true, display: true))
                        .foregroundStyle(Color(nsColor: color)),
                     at: CGPoint(x: rect.minX + transform.len(8),
                                 y: rect.minY + transform.len(6) + CGFloat(i) * lh + lh / 2),
                     anchor: .leading)
        }
    }

    static func edge(_ e: FCEdge, nodes: [String: FCNode], theme: FlowchartTheme,
                     transform: FCViewTransform, ctx: inout GraphicsContext) {
        guard let docPath = FCEdgePath(edge: e, nodes: nodes) else { return }
        let stroke = NSColor.fcHex(e.style.stroke) ?? theme.secondary
        let lineWidth = max(0.5, transform.len(e.style.strokeWidth))
        let dash: [CGFloat] = e.style.dashed ? [max(2, lineWidth * 4), max(2, lineWidth * 3)] : []
        var path = Path()
        path.move(to: transform.p(docPath.start))
        for seg in docPath.segments {
            switch seg {
            case .line(let p): path.addLine(to: transform.p(p))
            case .cubic(let c0, let c1, let p):
                path.addCurve(to: transform.p(p), control1: transform.p(c0), control2: transform.p(c1))
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
        let font = theme.nsFont(size: max(9, e.style.fontSize - 1), bold: e.style.bold)
        let lines = FCTextLayout.lines(e.label, width: transform.len(160), font: font)
        let lh = FCTextLayout.lineHeight(font)
        let widest = lines.map { FCTextLayout.measure($0, font: font) }.max() ?? 10
        let mid = transform.p(docPath.midpoint)
        let boxW = widest + transform.len(10)
        let boxH = CGFloat(lines.count) * lh + transform.len(4)
        let box = CGRect(x: mid.x - boxW / 2, y: mid.y - boxH / 2, width: boxW, height: boxH)
        ctx.fill(Path(roundedRect: box, cornerRadius: transform.len(4)),
                 with: .color(Color(nsColor: theme.surface)))
        let color = NSColor.fcHex(e.style.text) ?? theme.text
        for (i, line) in lines.enumerated() {
            ctx.draw(Text(line).font(theme.font(size: max(9, e.style.fontSize - 1), bold: e.style.bold))
                        .foregroundStyle(Color(nsColor: color)),
                     at: CGPoint(x: box.midX,
                                 y: box.minY + transform.len(2) + CGFloat(i) * lh + lh / 2),
                     anchor: .center)
        }
    }

    /// 图形内文字（自动换行 + 垂直居中 + 对齐）
    static func textBlock(_ text: String, in rect: CGRect, style: FCStyle, theme: FlowchartTheme,
                          transform: FCViewTransform, ctx: inout GraphicsContext,
                          verticalInset: CGFloat = 6) {
        guard !text.isEmpty else { return }
        let size = max(8, transform.len(style.fontSize))
        let font = theme.nsFont(size: size, bold: style.bold)
        let lines = FCTextLayout.lines(text, width: max(10, rect.width - transform.len(16)), font: font)
        let lh = FCTextLayout.lineHeight(font)
        let total = CGFloat(lines.count) * lh
        let top = rect.midY - total / 2
        let color = NSColor.fcHex(style.text) ?? theme.text
        let anchor: UnitPoint = style.align == .leading ? .leading : (style.align == .trailing ? .trailing : .center)
        let x: CGFloat = style.align == .leading ? rect.minX + transform.len(8)
            : (style.align == .trailing ? rect.maxX - transform.len(8) : rect.midX)
        for (i, line) in lines.enumerated() {
            ctx.draw(Text(line).font(theme.font(size: size, bold: style.bold))
                        .foregroundStyle(Color(nsColor: color)),
                     at: CGPoint(x: x, y: top + CGFloat(i) * lh + lh / 2),
                     anchor: anchor)
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
                FCRenderer.content(doc, theme: theme, transform: transform, ctx: &ctx)
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
    /// 连线工具本次按下的起始图形（决定「拖拽连线」还是「点击-点击连线」）
    @State private var edgePressNode: String?
    @State private var guideX: CGFloat?
    @State private var guideY: CGFloat?
    /// 画布在窗口中的位置：由 NSView 自己记录，供滚轮命中判断读取。
    /// 注意：不能在 NSView.layout() 里回写 SwiftUI 状态 —— AppKit 会在布局期抛异常（实测崩溃）。
    @State private var scrollTarget = FCScrollTargetBox()
    @State private var scrollMonitor: Any?
    @State private var magnifyMonitor: Any?
    @FocusState private var textFieldFocused: Bool
    /// 自判双击用（DragGesture(0) 吞掉了 SwiftUI 的双击手势）
    @State private var lastClickAt: Date = .distantPast
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
                    FCRenderer.content(editor.doc, theme: theme, transform: transform, ctx: &ctx)
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
                let node = FCNode(kind: shape, origin: p)
                editor.commit { $0.nodes.append(node) }
                editor.selection = [node.id]
                return true
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): updateHover(transform.doc(p))
                case .ended: hoverAnchor = nil
                }
            }
            .onAppear {
                updateCanvasSize(geo.size)
                installScrollMonitors()
            }
            .onDisappear { removeScrollMonitors() }
            .onChange(of: geo.size) { _, size in updateCanvasSize(size) }
            .onChange(of: editor.tool) { _, _ in
                // 切换工具时清掉「点击-点击连线」的半途状态
                if edgeStartNode != nil {
                    edgeStartNode = nil
                    editor.pendingEdge = nil
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
        if let pending = editor.pendingEdge,
           let node = editor.doc.nodes.first(where: { $0.id == pending.from }) {
            let a = transform.p(FCEdgePath.point(pending.anchor, in: node.rect))
            let b = transform.p(pending.point)
            var p = Path()
            p.move(to: a)
            p.addLine(to: b)
            ctx.stroke(p, with: .color(accent), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            ctx.fill(FCShape.arrow(tip: b, direction: CGVector(dx: b.x - a.x, dy: b.y - a.y),
                                   size: 9),
                     with: .color(accent))
        }
        // 拉线目标高亮（draw.io 式：光标贴到哪个图形，哪个整框变亮）
        if let tid = edgeTargetID, let node = editor.doc.nodes.first(where: { $0.id == tid }) {
            let r = transform.r(node.rect).insetBy(dx: -3, dy: -3)
            ctx.stroke(Path(roundedRect: r, cornerRadius: 6),
                       with: .color(accent), style: StrokeStyle(lineWidth: 2.5))
        }
        // 悬停连线：整条线加粗高亮（可点提示）
        if let hid = hoverEdgeID, let e = editor.doc.edges.first(where: { $0.id == hid }),
           let path = FCEdgePath(edge: e, nodes: editor.doc.nodesByID()) {
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
           let path = FCEdgePath(edge: edge, nodes: editor.doc.nodesByID()),
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
            FCTextEditor(text: Binding(
                get: { editor.doc.text(of: id) },
                set: { value in editor.preview { $0.setText(id, value) } }
            ), theme: theme, align: editor.doc.style(of: id)?.align ?? .center, focused: $textFieldFocused)
            .frame(width: max(90, r.width), height: max(30, r.height))
            .position(x: r.midX, y: r.midY)
            .onAppear {
                // 延后一拍再聚焦：overlay 尚未挂进窗口层级时设置 FocusState 会被系统丢弃
                // （表现为编辑框出现但不接收键盘输入，得再点一下才能打字）
                DispatchQueue.main.async { textFieldFocused = true }
            }
            .onExitCommand { finishTextEditing() }
            .onChange(of: textFieldFocused) { _, focused in
                if !focused { finishTextEditing() }
            }
        }
    }

    // MARK: 手势

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in dragChanged(value) }
            .onEnded { value in dragEnded(value) }
    }

    private func dragChanged(_ value: DragGesture.Value) {
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

        case .edge(let from, let anchor):
            editor.pendingEdge = (from: from, anchor: anchor, point: current)
            // draw.io 式目标高亮：光标进入/贴近某个图形时整框变亮
            let hovered = editor.doc.node(at: current)?.id
                ?? nearestNode(to: current, within: 26 / max(editor.zoom, 0.2))?.id
            if hovered != from { edgeTargetID = hovered } else { edgeTargetID = nil }

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

        // 连线工具（drag == .none 分支接管）：
        // · 移动超过阈值 = 拖拽连线（起点图形 → 落点图形）
        // · 原地松开 = 点击-点击连线（第一次点 = 起点；第二次点目标 = 连线；点空白 = 取消）
        if editor.tool == .edge, case .none = drag {
            let moved = hypot(value.location.x - value.startLocation.x,
                              value.location.y - value.startLocation.y) >= 3
            let hitNode = editor.doc.node(at: current)
            if moved {
                if let from = edgePressNode, let target = hitNode, target.id != from {
                    let edge = FCEdge(fromNode: from, toNode: target.id,
                                      fromAnchor: .auto, toAnchor: .auto)
                    editor.commit { $0.edges.append(edge) }
                    editor.selection = [edge.id]
                }
                edgeStartNode = nil
                editor.pendingEdge = nil
            } else if let sid = edgeStartNode {
                if let target = hitNode, target.id != sid {
                    let edge = FCEdge(fromNode: sid, toNode: target.id,
                                      fromAnchor: .auto, toAnchor: .auto)
                    editor.commit { $0.edges.append(edge) }
                    editor.selection = [edge.id]
                    edgeStartNode = nil
                    editor.pendingEdge = nil
                } else {
                    edgeStartNode = nil      // 点到空白/同一图形 = 取消
                    editor.pendingEdge = nil
                }
            } else if let node = hitNode {
                edgeStartNode = node.id
                editor.pendingEdge = (from: node.id, anchor: .auto, point: current)
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
            case .move: return hitID != nil          // 点中元素
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
        case .edge(let from, let anchor):
            defer { editor.pendingEdge = nil }
            defer { edgeTargetID = nil }
            // 落点吸附：精确命中优先，其次贴近图形 26pt 内也接住（draw.io 手感）
            let tol = 26 / max(editor.zoom, 0.2)
            if let target = editor.doc.node(at: current)
                ?? nearestNode(to: current, within: tol)
                ?? editor.doc.node(at: transform.doc(value.startLocation)) {
                if target.id != from {
                    let edge = FCEdge(fromNode: from, toNode: target.id,
                                      fromAnchor: anchor, toAnchor: .auto)
                    editor.commit { $0.edges.append(edge) }
                    editor.selection = [edge.id]
                }
            }
        case .reconnect(let id, let isFrom):
            defer { editor.pendingEdge = nil }
            defer { edgeTargetID = nil }
            let tol = 26 / max(editor.zoom, 0.2)
            if let target = editor.doc.node(at: current) ?? nearestNode(to: current, within: tol),
               let idx = editor.doc.edges.firstIndex(where: { $0.id == id }) {
                editor.commit { doc in
                    if isFrom {
                        doc.edges[idx].fromNode = target.id
                        doc.edges[idx].fromAnchor = .auto
                    } else {
                        doc.edges[idx].toNode = target.id
                        doc.edges[idx].toAnchor = .auto
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
           let path = FCEdgePath(edge: edge, nodes: editor.doc.nodesByID()),
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
            drag = .edge(from: anchorHit.node, anchor: anchorHit.anchor)
            editor.pendingEdge = (from: anchorHit.node, anchor: anchorHit.anchor, point: start)
            return
        }

        // 3) 工具：新建元素
        if let kind = editor.tool.shape {
            let node = FCNode(kind: kind, origin: start)
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
        let candidates: [FCAnchor] = [.top, .right, .bottom, .left]
        var best = FCAnchor.auto
        var bestDist = CGFloat.greatestFiniteMagnitude
        for a in candidates {
            let q = FCEdgePath.point(a, in: node.rect)
            let d = hypot(q.x - p.x, q.y - p.y)
            if d < bestDist { bestDist = d; best = a }
        }
        return best
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
            edgeTargetID = editor.doc.node(at: p).map { $0.id } == sid
                ? nil : editor.doc.node(at: p)?.id
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

// MARK: - 内联文字编辑

private struct FCTextEditor: View {
    @Binding var text: String
    let theme: FlowchartTheme
    let align: FCTextAlign
    var focused: FocusState<Bool>.Binding

    var body: some View {
        TextEditor(text: $text)
            .font(theme.font(size: 13))
            .multilineTextAlignment(align.alignment)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: theme.accent), lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .focused(focused)
            .shadow(color: Color.black.opacity(0.18), radius: 6, y: 2)
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

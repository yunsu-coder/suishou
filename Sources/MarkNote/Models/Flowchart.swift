import AppKit
import Foundation
import SwiftUI

// MARK: - 流程图数据模型（视图插件 `flowchart`）
//
// 规则（见 docs/05-内置插件库.md）：
// · 作用域：只读写**当前工作台**的 `source/flowchart/`；不碰别的工作台；
// · 图形/连线的颜色可自由取色（流程图专属例外，2026-09 规范修订）；
// · 界面外壳（工具栏 / 检查器 / 面板）仍取主题变量，不写死色值；
// · 卸载即干净：删掉 `source/flowchart/` 即可，不留私有格式。

/// 基础图形
enum FCShapeKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case rect, roundedRect, ellipse, diamond, parallelogram, cylinder, capsule, note

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rect: return _L("矩形", "Rectangle")
        case .roundedRect: return _L("圆角矩形", "Rounded")
        case .ellipse: return _L("椭圆", "Ellipse")
        case .diamond: return _L("菱形", "Diamond")
        case .parallelogram: return _L("平行四边形", "Parallelogram")
        case .cylinder: return _L("圆柱", "Cylinder")
        case .capsule: return _L("胶囊", "Capsule")
        case .note: return _L("便签", "Note")
        }
    }

    var symbol: String {
        switch self {
        case .rect: return "rectangle"
        case .roundedRect: return "rectangle.roundedtop"
        case .ellipse: return "circle"
        case .diamond: return "diamond"
        case .parallelogram: return "rhombus"
        case .cylinder: return "cylinder"
        case .capsule: return "capsule"
        case .note: return "note.text"
        }
    }

    var defaultSize: CGSize {
        switch self {
        case .diamond: return CGSize(width: 140, height: 80)
        case .cylinder: return CGSize(width: 120, height: 90)
        case .capsule: return CGSize(width: 130, height: 48)
        case .note: return CGSize(width: 130, height: 76)
        case .parallelogram: return CGSize(width: 150, height: 60)
        default: return CGSize(width: 140, height: 64)
        }
    }
}

/// 连线锚点（auto = 按两个图形的相对位置自动选边）
enum FCAnchor: String, Codable, CaseIterable, Hashable {
    case top, right, bottom, left, auto

    var label: String {
        switch self {
        case .top: return _L("上", "Top")
        case .right: return _L("右", "Right")
        case .bottom: return _L("下", "Bottom")
        case .left: return _L("左", "Left")
        case .auto: return _L("自动", "Auto")
        }
    }

    /// 出边方向单位向量（auto 由调用方先解析）
    var vector: CGVector {
        switch self {
        case .top: return CGVector(dx: 0, dy: -1)
        case .right: return CGVector(dx: 1, dy: 0)
        case .bottom: return CGVector(dx: 0, dy: 1)
        case .left: return CGVector(dx: -1, dy: 0)
        case .auto: return CGVector(dx: 0, dy: 0)
        }
    }
}

enum FCRoute: String, Codable, CaseIterable, Hashable {
    case straight, orthogonal, curve

    var label: String {
        switch self {
        case .straight: return _L("直线", "Straight")
        case .orthogonal: return _L("折线", "Elbow")
        case .curve: return _L("曲线", "Curve")
        }
    }

    var symbol: String {
        switch self {
        case .straight: return "line.diagonal"
        case .orthogonal: return "arrow.turn.down.right"
        case .curve: return "arrow.up.right"
        }
    }
}

enum FCArrow: String, Codable, CaseIterable, Hashable {
    case end, both, none

    var label: String {
        switch self {
        case .end: return _L("单向", "Single")
        case .both: return _L("双向", "Double")
        case .none: return _L("无", "None")
        }
    }
}

enum FCTextAlign: String, Codable, CaseIterable, Hashable {
    case leading, center, trailing

    var symbol: String {
        switch self {
        case .leading: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .trailing: return "text.alignright"
        }
    }

    var alignment: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var unitPoint: UnitPoint {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var nsAlignment: NSTextAlignment {
        switch self {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        }
    }
}

/// 对齐方式（多选时生效）
enum FCAlignMode: String, CaseIterable, Hashable {
    case left, centerX, right, top, centerY, bottom

    var symbol: String {
        switch self {
        case .left: return "align.horizontal.left"
        case .centerX: return "align.horizontal.center"
        case .right: return "align.horizontal.right"
        case .top: return "align.vertical.top"
        case .centerY: return "align.vertical.center"
        case .bottom: return "align.vertical.bottom"
        }
    }

    var label: String {
        switch self {
        case .left: return _L("左对齐", "Align left")
        case .centerX: return _L("水平居中", "Align center")
        case .right: return _L("右对齐", "Align right")
        case .top: return _L("顶对齐", "Align top")
        case .centerY: return _L("垂直居中", "Align middle")
        case .bottom: return _L("底对齐", "Align bottom")
        }
    }
}

/// 元素样式。颜色为 nil 时跟随主题（"跟随主题"就是清空对应色值）。
struct FCStyle: Codable, Equatable, Hashable {
    var fill: String?
    var stroke: String?
    var text: String?
    var strokeWidth: Double = 1.5
    var dashed: Bool = false
    var corner: Double = 8
    var shadow: Bool = false
    var fontSize: Double = 13
    var bold: Bool = false
    var align: FCTextAlign = .center

    static let `default` = FCStyle()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fill = c.vOpt(String.self, .fill)
        stroke = c.vOpt(String.self, .stroke)
        text = c.vOpt(String.self, .text)
        strokeWidth = c.v(Double.self, .strokeWidth, 1.5)
        dashed = c.v(Bool.self, .dashed, false)
        corner = c.v(Double.self, .corner, 8)
        shadow = c.v(Bool.self, .shadow, false)
        fontSize = c.v(Double.self, .fontSize, 13)
        bold = c.v(Bool.self, .bold, false)
        align = c.v(FCTextAlign.self, .align, .center)
    }
}

/// 图形节点
struct FCNode: Identifiable, Codable, Equatable, Hashable {
    var id: String = UUID().uuidString
    var kind: FCShapeKind = .roundedRect
    var x: Double = 0
    var y: Double = 0
    var w: Double = 140
    var h: Double = 64
    var text: String = ""
    var style: FCStyle = .default

    var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
    var center: CGPoint { CGPoint(x: x + w / 2, y: y + h / 2) }

    init(kind: FCShapeKind = .roundedRect, origin: CGPoint = .zero, text: String = "") {
        self.kind = kind
        let size = kind.defaultSize
        self.w = size.width
        self.h = size.height
        self.x = origin.x
        self.y = origin.y
        self.text = text
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(String.self, .id, UUID().uuidString)
        kind = c.v(FCShapeKind.self, .kind, .roundedRect)
        x = c.v(Double.self, .x, 0)
        y = c.v(Double.self, .y, 0)
        w = c.v(Double.self, .w, 140)
        h = c.v(Double.self, .h, 64)
        text = c.v(String.self, .text, "")
        style = c.v(FCStyle.self, .style, .default)
    }

    func moved(dx: Double, dy: Double) -> FCNode {
        var n = self
        n.x += dx
        n.y += dy
        return n
    }

    /// 命中 + 吸附辅助：把点夹到矩形边界的最近点
    func clamped(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, rect.minX), rect.maxX),
                y: min(max(p.y, rect.minY), rect.maxY))
    }
}

/// 连线
struct FCEdge: Identifiable, Codable, Equatable, Hashable {
    var id: String = UUID().uuidString
    var fromNode: String = ""
    var fromAnchor: FCAnchor = .auto
    var toNode: String = ""
    var toAnchor: FCAnchor = .auto
    var label: String = ""
    var route: FCRoute = .orthogonal
    var arrow: FCArrow = .end
    var style: FCStyle = .default

    init(fromNode: String, toNode: String, fromAnchor: FCAnchor = .auto,
         toAnchor: FCAnchor = .auto, label: String = "") {
        self.fromNode = fromNode
        self.fromAnchor = fromAnchor
        self.toNode = toNode
        self.toAnchor = toAnchor
        self.label = label
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(String.self, .id, UUID().uuidString)
        fromNode = c.v(String.self, .fromNode, "")
        fromAnchor = c.v(FCAnchor.self, .fromAnchor, .auto)
        toNode = c.v(String.self, .toNode, "")
        toAnchor = c.v(FCAnchor.self, .toAnchor, .auto)
        label = c.v(String.self, .label, "")
        route = c.v(FCRoute.self, .route, .orthogonal)
        arrow = c.v(FCArrow.self, .arrow, .end)
        style = c.v(FCStyle.self, .style, .default)
    }
}

/// 独立文本框
struct FCTextItem: Identifiable, Codable, Equatable, Hashable {
    var id: String = UUID().uuidString
    var x: Double = 0
    var y: Double = 0
    var w: Double = 160
    var h: Double = 30
    var text: String = _L("文本", "Text")
    var style: FCStyle = .default

    var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }

    init(origin: CGPoint = .zero, text: String = _L("文本", "Text")) {
        self.x = origin.x
        self.y = origin.y
        self.text = text
        var s = FCStyle.default
        s.align = .leading
        self.style = s
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(String.self, .id, UUID().uuidString)
        x = c.v(Double.self, .x, 0)
        y = c.v(Double.self, .y, 0)
        w = c.v(Double.self, .w, 160)
        h = c.v(Double.self, .h, 30)
        text = c.v(String.self, .text, "")
        style = c.v(FCStyle.self, .style, .default)
    }
}

/// 分组容器（虚线框 + 左上角名字）
struct FCGroup: Identifiable, Codable, Equatable, Hashable {
    var id: String = UUID().uuidString
    var x: Double = 0
    var y: Double = 0
    var w: Double = 280
    var h: Double = 180
    var title: String = ""
    var style: FCStyle = .default

    var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }

    init(origin: CGPoint = .zero, title: String = "") {
        self.x = origin.x
        self.y = origin.y
        self.title = title
        var s = FCStyle.default
        s.dashed = true
        s.fill = nil
        self.style = s
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(String.self, .id, UUID().uuidString)
        x = c.v(Double.self, .x, 0)
        y = c.v(Double.self, .y, 0)
        w = c.v(Double.self, .w, 280)
        h = c.v(Double.self, .h, 180)
        title = c.v(String.self, .title, "")
        style = c.v(FCStyle.self, .style, .default)
    }
}

/// 一张流程图（= `source/flowchart/<名字>.json`）
struct FCDocument: Codable, Equatable {
    var version: Int = 1
    var name: String = _L("未命名流程图", "Untitled")
    var nodes: [FCNode] = []
    var edges: [FCEdge] = []
    var texts: [FCTextItem] = []
    var groups: [FCGroup] = []
    var showGrid: Bool = true
    var snap: Bool = true
    var updatedAt: Date = Date()

    init(name: String = _L("未命名流程图", "Untitled")) {
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = c.v(Int.self, .version, 1)
        name = c.v(String.self, .name, _L("未命名流程图", "Untitled"))
        nodes = c.v([FCNode].self, .nodes, [])
        edges = c.v([FCEdge].self, .edges, [])
        texts = c.v([FCTextItem].self, .texts, [])
        groups = c.v([FCGroup].self, .groups, [])
        showGrid = c.v(Bool.self, .showGrid, true)
        snap = c.v(Bool.self, .snap, true)
        updatedAt = c.v(Date.self, .updatedAt, Date())
    }

    /// 内容包围盒（导出 / 缩放适配用）
    var contentBounds: CGRect {
        var box: CGRect?
        for n in nodes { box = box.map { $0.union(n.rect) } ?? n.rect }
        for t in texts { box = box.map { $0.union(t.rect) } ?? t.rect }
        for g in groups { box = box.map { $0.union(g.rect) } ?? g.rect }
        // 连线的绕行路径可能超出图形包围盒（BFS 避障会绕远）——
        // 不把它们计入，导出 PNG / 适应窗口会把绕行线段裁掉。
        let index = nodesByID()
        for e in edges {
            guard let path = FCEdgePath(edge: e, nodes: index) else { continue }
            for p in path.polyline {
                let dot = CGRect(x: p.x, y: p.y, width: 0, height: 0)
                box = box.map { $0.union(dot) } ?? dot
            }
        }
        guard let b = box, b.width > 1, b.height > 1 else {
            return CGRect(x: 0, y: 0, width: 320, height: 200)
        }
        return b
    }

    var isEmpty: Bool { nodes.isEmpty && texts.isEmpty && groups.isEmpty }

    func nodesByID() -> [String: FCNode] {
        // uniquingKeysWith：损坏/手工编辑的数据若出现重复 id，取第一个而不是崩溃
        Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: 命中测试

    func node(at p: CGPoint) -> FCNode? {
        nodes.reversed().first { $0.rect.contains(p) }
    }

    func text(at p: CGPoint) -> FCTextItem? {
        texts.reversed().first { $0.rect.contains(p) }
    }

    func group(at p: CGPoint) -> FCGroup? {
        groups.reversed().first { $0.rect.contains(p) }
    }

    func edge(at p: CGPoint, tolerance: CGFloat) -> FCEdge? {
        let index = nodesByID()
        for e in edges.reversed() {
            guard let path = FCEdgePath(edge: e, nodes: index) else { continue }
            if path.distance(to: p) <= tolerance { return e }
        }
        return nil
    }

    /// 命中优先级（上 → 下）：连线 → 文本 → 图形 → 分组
    func hit(_ p: CGPoint, tolerance: CGFloat = 6) -> String? {
        if let e = edge(at: p, tolerance: tolerance) { return e.id }
        if let t = text(at: p) { return t.id }
        if let n = node(at: p) { return n.id }
        if let g = group(at: p) { return g.id }
        return nil
    }

    func rect(of id: String) -> CGRect? {
        if let n = nodes.first(where: { $0.id == id }) { return n.rect }
        if let t = texts.first(where: { $0.id == id }) { return t.rect }
        if let g = groups.first(where: { $0.id == id }) { return g.rect }
        if let e = edges.first(where: { $0.id == id }) {
            let index = nodesByID()
            guard let path = FCEdgePath(edge: e, nodes: index) else { return nil }
            return path.boundingBox
        }
        return nil
    }

    // MARK: 编辑操作

    mutating func translate(_ ids: Set<String>, dx: Double, dy: Double) {
        for i in nodes.indices where ids.contains(nodes[i].id) {
            nodes[i].x += dx
            nodes[i].y += dy
        }
        for i in texts.indices where ids.contains(texts[i].id) {
            texts[i].x += dx
            texts[i].y += dy
        }
        for i in groups.indices where ids.contains(groups[i].id) {
            groups[i].x += dx
            groups[i].y += dy
        }
    }

    mutating func remove(_ ids: Set<String>) {
        nodes.removeAll { ids.contains($0.id) }
        texts.removeAll { ids.contains($0.id) }
        groups.removeAll { ids.contains($0.id) }
        // 被删掉的图形，其连线一并消失（不留悬空边）
        edges.removeAll { ids.contains($0.id) || ids.contains($0.fromNode) || ids.contains($0.toNode) }
    }

    mutating func applyStyle(_ ids: Set<String>, _ change: (inout FCStyle) -> Void) {
        for i in nodes.indices where ids.contains(nodes[i].id) { change(&nodes[i].style) }
        for i in texts.indices where ids.contains(texts[i].id) { change(&texts[i].style) }
        for i in groups.indices where ids.contains(groups[i].id) { change(&groups[i].style) }
        for i in edges.indices where ids.contains(edges[i].id) { change(&edges[i].style) }
    }

    mutating func setText(_ id: String, _ text: String) {
        if let i = nodes.firstIndex(where: { $0.id == id }) { nodes[i].text = text; return }
        if let i = texts.firstIndex(where: { $0.id == id }) { texts[i].text = text; return }
        if let i = groups.firstIndex(where: { $0.id == id }) { groups[i].title = text; return }
        if let i = edges.firstIndex(where: { $0.id == id }) { edges[i].label = text }
    }

    func text(of id: String) -> String {
        if let n = nodes.first(where: { $0.id == id }) { return n.text }
        if let t = texts.first(where: { $0.id == id }) { return t.text }
        if let g = groups.first(where: { $0.id == id }) { return g.title }
        if let e = edges.first(where: { $0.id == id }) { return e.label }
        return ""
    }

    func style(of id: String) -> FCStyle? {
        if let n = nodes.first(where: { $0.id == id }) { return n.style }
        if let t = texts.first(where: { $0.id == id }) { return t.style }
        if let g = groups.first(where: { $0.id == id }) { return g.style }
        if let e = edges.first(where: { $0.id == id }) { return e.style }
        return nil
    }

    /// 缩放 / 拖动后写回矩形（图形 / 文本 / 分组）
    mutating func setRect(_ id: String, _ rect: CGRect) {
        if let i = nodes.firstIndex(where: { $0.id == id }) {
            nodes[i].x = rect.minX
            nodes[i].y = rect.minY
            nodes[i].w = rect.width
            nodes[i].h = rect.height
            return
        }
        if let i = texts.firstIndex(where: { $0.id == id }) {
            texts[i].x = rect.minX
            texts[i].y = rect.minY
            texts[i].w = rect.width
            texts[i].h = rect.height
            return
        }
        if let i = groups.firstIndex(where: { $0.id == id }) {
            groups[i].x = rect.minX
            groups[i].y = rect.minY
            groups[i].w = rect.width
            groups[i].h = rect.height
        }
    }

    /// 框选：图形 / 文本 / 分组与框相交即选中；连线两端都在选区内也选中
    func ids(in rect: CGRect) -> Set<String> {
        var out: Set<String> = []
        for n in nodes where rect.intersects(n.rect) { out.insert(n.id) }
        for t in texts where rect.intersects(t.rect) { out.insert(t.id) }
        for g in groups where rect.intersects(g.rect) { out.insert(g.id) }
        for e in edges where out.contains(e.fromNode) && out.contains(e.toNode) { out.insert(e.id) }
        return out
    }

    /// 参与对齐的可移动矩形（图形 / 文本 / 分组）
    func movableRects(_ ids: Set<String>) -> [(String, CGRect)] {
        var out: [(String, CGRect)] = []
        for n in nodes where ids.contains(n.id) { out.append((n.id, n.rect)) }
        for t in texts where ids.contains(t.id) { out.append((t.id, t.rect)) }
        for g in groups where ids.contains(g.id) { out.append((g.id, g.rect)) }
        return out
    }

    /// 对齐（以选区整体包围盒为基准）
    mutating func align(_ ids: Set<String>, _ mode: FCAlignMode) {
        let items = movableRects(ids)
        guard items.count >= 2 else { return }
        var box = items[0].1
        for (_, r) in items.dropFirst() { box = box.union(r) }
        for (id, r) in items {
            var target = r
            switch mode {
            case .left: target.origin.x = box.minX
            case .centerX: target.origin.x = box.midX - r.width / 2
            case .right: target.origin.x = box.maxX - r.width
            case .top: target.origin.y = box.minY
            case .centerY: target.origin.y = box.midY - r.height / 2
            case .bottom: target.origin.y = box.maxY - r.height
            }
            setRect(id, target)
        }
    }

    /// 均匀分布（首尾不动，中间等距）
    mutating func distribute(_ ids: Set<String>, horizontal: Bool) {
        var items = movableRects(ids)
        guard items.count >= 3 else { return }
        items.sort { a, b in
            horizontal ? a.1.midX < b.1.midX : a.1.midY < b.1.midY
        }
        let first = items.first!.1, last = items.last!.1
        let total = horizontal ? (last.maxX - first.minX) : (last.maxY - first.minY)
        let used = items.reduce(CGFloat(0)) { $0 + (horizontal ? $1.1.width : $1.1.height) }
        let gap = (total - used) / CGFloat(items.count - 1)
        var cursor = horizontal ? first.minX : first.minY
        for (id, r) in items {
            var target = r
            if horizontal {
                target.origin.x = cursor
                cursor += r.width + gap
            } else {
                target.origin.y = cursor
                cursor += r.height + gap
            }
            setRect(id, target)
        }
    }

    /// 置顶 / 置底（数组顺序即层级）
    mutating func bringToFront(_ ids: Set<String>) {
        let picked = nodes.filter { ids.contains($0.id) }
        guard !picked.isEmpty else { return }
        nodes.removeAll { ids.contains($0.id) }
        nodes.append(contentsOf: picked)
    }

    mutating func sendToBack(_ ids: Set<String>) {
        let picked = nodes.filter { ids.contains($0.id) }
        guard !picked.isEmpty else { return }
        nodes.removeAll { ids.contains($0.id) }
        nodes.insert(contentsOf: picked, at: 0)
    }

    /// 复制选中元素（含内部连线），返回新 id 集合
    mutating func duplicate(_ ids: Set<String>, offset: Double = 20) -> Set<String> {
        var fresh: Set<String> = []
        var idMap: [String: String] = [:]
        for n in nodes where ids.contains(n.id) {
            var copy = n
            copy.id = UUID().uuidString
            copy.x += offset
            copy.y += offset
            idMap[n.id] = copy.id
            fresh.insert(copy.id)
            nodes.append(copy)
        }
        for t in texts where ids.contains(t.id) {
            var copy = t
            copy.id = UUID().uuidString
            copy.x += offset
            copy.y += offset
            fresh.insert(copy.id)
            texts.append(copy)
        }
        for g in groups where ids.contains(g.id) {
            var copy = g
            copy.id = UUID().uuidString
            copy.x += offset
            copy.y += offset
            fresh.insert(copy.id)
            groups.append(copy)
        }
        for e in edges where ids.contains(e.id) || (idMap[e.fromNode] != nil && idMap[e.toNode] != nil) {
            var copy = e
            copy.id = UUID().uuidString
            copy.fromNode = idMap[e.fromNode] ?? e.fromNode
            copy.toNode = idMap[e.toNode] ?? e.toNode
            fresh.insert(copy.id)
            edges.append(copy)
        }
        return fresh
    }

    /// 自动编号：按连线拓扑序（环回退到「上→下、左→右」），前缀 `1. ` 形式
    mutating func autoNumberNodes() {
        let order = topologicalNodeOrder()
        for (i, id) in order.enumerated() {
            guard let idx = nodes.firstIndex(where: { $0.id == id }) else { continue }
            let prefix = "\(i + 1). "
            let body = FCDocument.stripNumberPrefix(nodes[idx].text)
            nodes[idx].text = prefix + body
        }
    }

    func topologicalNodeOrder() -> [String] {
        var indegree: [String: Int] = [:]
        var out: [String: [String]] = [:]
        for n in nodes { indegree[n.id] = 0 }
        for e in edges where indegree[e.fromNode] != nil && indegree[e.toNode] != nil {
            out[e.fromNode, default: []].append(e.toNode)
            indegree[e.toNode, default: 0] += 1
        }
        let position: (String) -> CGPoint = { id in
            self.nodes.first(where: { $0.id == id })?.center ?? .zero
        }
        var ready = nodes.map(\.id).filter { (indegree[$0] ?? 0) == 0 }
        var result: [String] = []
        while !ready.isEmpty {
            ready.sort { a, b in
                let pa = position(a), pb = position(b)
                if abs(pa.y - pb.y) > 12 { return pa.y < pb.y }
                return pa.x < pb.x
            }
            let next = ready.removeFirst()
            result.append(next)
            for child in out[next] ?? [] {
                indegree[child, default: 0] -= 1
                if (indegree[child] ?? 0) == 0 { ready.append(child) }
            }
        }
        // 有环 → 剩余节点按位置补在末尾
        if result.count < nodes.count {
            let rest = nodes.map(\.id).filter { !result.contains($0) }
                .sorted { a, b in
                    let pa = position(a), pb = position(b)
                    if abs(pa.y - pb.y) > 12 { return pa.y < pb.y }
                    return pa.x < pb.x
                }
            result.append(contentsOf: rest)
        }
        return result
    }

    static func stripNumberPrefix(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespaces)
        while let dot = s.firstIndex(of: "."), dot > s.startIndex {
            let head = s[s.startIndex..<dot]
            if !head.isEmpty, head.allSatisfy({ $0.isNumber }) {
                s = String(s[s.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
            } else {
                break
            }
        }
        return s
    }
}

// MARK: - 连线路由

enum FCSegment: Equatable, Hashable {
    case line(CGPoint)
    case cubic(CGPoint, CGPoint, CGPoint)

    var end: CGPoint {
        switch self {
        case .line(let p): return p
        case .cubic(_, _, let p): return p
        }
    }
}

struct FCEdgePath: Equatable {
    var start: CGPoint
    var segments: [FCSegment]

    init?(edge: FCEdge, nodes: [String: FCNode]) {
        guard let a = nodes[edge.fromNode], let b = nodes[edge.toNode] else { return nil }
        let fromAnchor = edge.fromAnchor == .auto ? FCEdgePath.autoAnchor(from: a.rect, toward: b.rect) : edge.fromAnchor
        let toAnchor = edge.toAnchor == .auto ? FCEdgePath.autoAnchor(from: b.rect, toward: a.rect) : edge.toAnchor
        let p0 = FCEdgePath.point(fromAnchor, in: a.rect)
        let p1 = FCEdgePath.point(toAnchor, in: b.rect)
        let n0 = fromAnchor.vector
        let n1 = toAnchor.vector
        start = p0

        switch edge.route {
        case .straight:
            segments = [.line(p1)]

        case .orthogonal:
            // 智能正交路由（draw.io/GoJS 风格）：简单候选（L/Z）优先，全部碰撞时
            // BFS 网格绕行障碍 + 视线拉直 —— 路径不再穿越图形、不再绕远。
            let obstacles = nodes.values
                .filter { $0.id != edge.fromNode && $0.id != edge.toNode }
                .map(\.rect)
            // avoid：源 / 目标图形本体（防"线钻进自己的图形/贴边框走"）
            let routed = FCRouter.route(p0: p0, n0: n0, p1: p1, n1: n1,
                                        obstacles: obstacles, avoid: [a.rect, b.rect])
            segments = zip(routed, routed.dropFirst()).map { .line($1) }

        case .curve:
            let span = max(40, hypot(Double(p1.x - p0.x), Double(p1.y - p0.y)) * 0.45)
            let c0 = CGPoint(x: p0.x + n0.dx * span, y: p0.y + n0.dy * span)
            let c1 = CGPoint(x: p1.x + n1.dx * span, y: p1.y + n1.dy * span)
            segments = [.cubic(c0, c1, p1)]
        }
    }

    static func dedupe(_ pts: [CGPoint]) -> [CGPoint] {
        var out: [CGPoint] = []
        for p in pts {
            if let last = out.last, abs(last.x - p.x) < 0.5, abs(last.y - p.y) < 0.5 { continue }
            out.append(p)
        }
        return out
    }

    static func autoAnchor(from rect: CGRect, toward other: CGRect) -> FCAnchor {
        let dx = other.midX - rect.midX
        let dy = other.midY - rect.midY
        let w = max(rect.width, other.width) / 2 + 1
        let h = max(rect.height, other.height) / 2 + 1
        // 归一化后比较：宽扁的图形优先左右出线，高瘦的优先上下出线
        if abs(dx) / w >= abs(dy) / h {
            return dx >= 0 ? .right : .left
        }
        return dy >= 0 ? .bottom : .top
    }

    static func point(_ anchor: FCAnchor, in rect: CGRect) -> CGPoint {
        switch anchor {
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .auto: return CGPoint(x: rect.midX, y: rect.midY)
        }
    }

    /// 折线化采样（命中测试 / 标签定位用）
    var polyline: [CGPoint] {
        var pts: [CGPoint] = [start]
        for seg in segments {
            switch seg {
            case .line(let p):
                pts.append(p)
            case .cubic(let c0, let c1, let p):
                let a = pts[pts.count - 1]
                for i in 1...10 {
                    let t = CGFloat(i) / 10
                    pts.append(FCEdgePath.cubicPoint(a, c0, c1, p, t))
                }
            }
        }
        return pts
    }

    static func cubicPoint(_ p0: CGPoint, _ c0: CGPoint, _ c1: CGPoint, _ p1: CGPoint, _ t: CGFloat) -> CGPoint {
        let mt = 1 - t
        let a = mt * mt * mt
        let b = 3 * mt * mt * t
        let c = 3 * mt * t * t
        let d = t * t * t
        return CGPoint(x: a * p0.x + b * c0.x + c * c1.x + d * p1.x,
                       y: a * p0.y + b * c0.y + c * c1.y + d * p1.y)
    }

    var polylineLength: CGFloat {
        let pts = polyline
        var total: CGFloat = 0
        for i in 1..<max(1, pts.count) {
            total += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
        }
        return total
    }

    /// 折线中点（连线标签落点）
    var midpoint: CGPoint {
        let pts = polyline
        guard pts.count >= 2 else { return start }
        let half = polylineLength / 2
        var walked: CGFloat = 0
        for i in 1..<pts.count {
            let seg = hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
            if walked + seg >= half, seg > 0.0001 {
                let t = (half - walked) / seg
                return CGPoint(x: pts[i - 1].x + (pts[i].x - pts[i - 1].x) * t,
                               y: pts[i - 1].y + (pts[i].y - pts[i - 1].y) * t)
            }
            walked += seg
        }
        return pts[pts.count / 2]
    }

    /// 终点处的切线方向（箭头朝向）
    var endDirection: CGVector {
        let pts = polyline
        guard pts.count >= 2 else { return CGVector(dx: 1, dy: 0) }
        let a = pts[pts.count - 2], b = pts[pts.count - 1]
        let len = max(0.0001, hypot(b.x - a.x, b.y - a.y))
        return CGVector(dx: (b.x - a.x) / len, dy: (b.y - a.y) / len)
    }

    var startDirection: CGVector {
        let pts = polyline
        guard pts.count >= 2 else { return CGVector(dx: -1, dy: 0) }
        let a = pts[0], b = pts[1]
        let len = max(0.0001, hypot(b.x - a.x, b.y - a.y))
        return CGVector(dx: (a.x - b.x) / len, dy: (a.y - b.y) / len)
    }

    var boundingBox: CGRect {
        let pts = polyline
        guard let first = pts.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in pts {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func distance(to p: CGPoint) -> CGFloat {
        let pts = polyline
        var best = CGFloat.greatestFiniteMagnitude
        for i in 1..<max(1, pts.count) {
            best = min(best, FCEdgePath.distance(p, pts[i - 1], pts[i]))
        }
        return best
    }

    static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0.0001 else { return hypot(p.x - a.x, p.y - a.y) }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2
        t = min(max(t, 0), 1)
        return hypot(p.x - (a.x + dx * t), p.y - (a.y + dy * t))
    }
}

// MARK: - 图形路径（画布与导出共用）

enum FCShape {
    static func path(kind: FCShapeKind, rect: CGRect, corner: CGFloat) -> Path {
        switch kind {
        case .rect:
            return Path(rect)
        case .roundedRect:
            let r = min(corner, min(rect.width, rect.height) / 2)
            return Path(roundedRect: rect, cornerRadius: max(0, r))
        case .capsule:
            let r = min(rect.width, rect.height) / 2
            return Path(roundedRect: rect, cornerRadius: r)
        case .ellipse:
            return Path(ellipseIn: rect)
        case .diamond:
            var p = Path()
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            p.closeSubpath()
            return p
        case .parallelogram:
            let slant = min(rect.width * 0.22, 28)
            var p = Path()
            p.move(to: CGPoint(x: rect.minX + slant, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - slant, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
            return p
        case .cylinder:
            let ry = min(rect.height * 0.18, 16)
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY + ry))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + ry),
                           control: CGPoint(x: rect.midX, y: rect.minY - ry))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - ry))
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - ry),
                           control: CGPoint(x: rect.midX, y: rect.maxY + ry))
            p.closeSubpath()
            return p
        case .note:
            let fold = min(16, min(rect.width, rect.height) * 0.25)
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
            return p
        }
    }

    /// 圆柱的顶盖弧线（描边细节）
    static func detail(kind: FCShapeKind, rect: CGRect) -> Path? {
        guard kind == .cylinder else { return nil }
        let ry = min(rect.height * 0.18, 16)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + ry))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + ry),
                       control: CGPoint(x: rect.midX, y: rect.minY + ry * 3))
        return p
    }

    /// 箭头三角
    static func arrow(tip: CGPoint, direction: CGVector, size: CGFloat) -> Path {
        // direction 必须归一化再乘 size：调用方传的是「两端点差向量」，
        // 距离一远（例如 2000pt）箭头会膨胀成覆盖半个画布的巨型三角（已复现）。
        let len = hypot(direction.dx, direction.dy)
        let dx = len > 0.0001 ? direction.dx / len : 1
        let dy = len > 0.0001 ? direction.dy / len : 0
        let back = CGPoint(x: tip.x - dx * size, y: tip.y - dy * size)
        let nx = -dy, ny = dx
        let half = size * 0.42
        var p = Path()
        p.move(to: tip)
        p.addLine(to: CGPoint(x: back.x + nx * half, y: back.y + ny * half))
        p.addLine(to: CGPoint(x: back.x - nx * half, y: back.y - ny * half))
        p.closeSubpath()
        return p
    }
}

// MARK: - 主题（插件界面外壳取主题变量；画布内容颜色由用户决定）

struct FlowchartTheme {
    let background: NSColor
    let surface: NSColor
    let text: NSColor
    let secondary: NSColor
    let border: NSColor
    let accent: NSColor
    let palette: [NSColor]
    let uiFont: String?
    let displayFont: String?
    let motionMs: Double

    static var current: FlowchartTheme {
        let a = appAppearance
        let bg = a.editorBackground
        let fg = a.editorForeground
        let dark = a.dark
        let surface = a.surface ?? (dark ? bg.blended(withFraction: 0.06, of: .white) ?? bg
                                         : bg.blended(withFraction: 0.05, of: .black) ?? bg)
        let border = fg.withAlphaComponent(dark ? 0.22 : 0.16)
        // 色板：主题强调色 + 主题语法色 + 语义色（都是"主题派生"，但画布内容允许用户再自选）
        var swatches: [NSColor] = [a.accentNS]
        for key in ["--md-h1", "--md-h2", "--md-h3", "--md-strong", "--md-em", "--md-math"] {
            if let c = a.mdColor(key) { swatches.append(c) }
        }
        swatches.append(contentsOf: [
            NSColor.systemGreen, NSColor.systemOrange, NSColor.systemRed,
            NSColor.systemBlue, NSColor.systemPurple, NSColor.systemGray,
        ])
        // 去重（同一个色只留一次）
        var seen: Set<String> = []
        let palette = swatches.filter { c in
            let k = c.hexString
            if seen.contains(k) { return false }
            seen.insert(k)
            return true
        }
        return FlowchartTheme(background: bg,
                              surface: surface,
                              text: fg,
                              secondary: fg.withAlphaComponent(0.62),
                              border: border,
                              accent: a.accentNS,
                              palette: palette,
                              uiFont: a.uiFontFamily,
                              displayFont: a.displayFontFamily,
                              motionMs: Double((a.motion?.duration ?? 0.22) * 1000))
    }

    /// 未指定颜色时的默认填充：主题强调色 12% 叠在纸底上
    func defaultFill() -> NSColor {
        accent.withAlphaComponent(0.14).blended(withFraction: 0.0, of: background) ?? background
    }

    func defaultStroke() -> NSColor { accent }

    func font(size: Double, bold: Bool = false, display: Bool = false) -> Font {
        let family = display ? (displayFont ?? uiFont) : uiFont
        if let family, let ns = NSFont(name: family, size: size) {
            let name = bold ? NSFontManager.shared.convert(ns, toHaveTrait: .boldFontMask).fontName : ns.fontName
            return .custom(name, size: size)
        }
        return .system(size: size, weight: bold ? .semibold : .regular)
    }

    func nsFont(size: Double, bold: Bool = false, display: Bool = false) -> NSFont {
        let family = display ? (displayFont ?? uiFont) : uiFont
        let base = family.flatMap { NSFont(name: $0, size: size) } ?? NSFont.systemFont(ofSize: size)
        return bold ? NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask) : base
    }
}

extension NSColor {
    /// 存盘用：sRGB 十六进制
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((min(max(c.redComponent, 0), 1) * 255).rounded())
        let g = Int((min(max(c.greenComponent, 0), 1) * 255).rounded())
        let b = Int((min(max(c.blueComponent, 0), 1) * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    static func fcHex(_ hex: String?) -> NSColor? {
        guard let hex, !hex.isEmpty else { return nil }
        return PluginCSS.color(from: hex)
    }
}

// MARK: - 文档存储（当前工作台 source/flowchart/）

struct FCDocRef: Identifiable, Equatable {
    var id: String { url.path }
    let url: URL
    let name: String
    let mtime: Date
}

enum FlowchartStore {
    static func dir(root: URL) -> URL {
        root.appendingPathComponent("source/flowchart", isDirectory: true)
    }

    static func list(root: URL) -> [FCDocRef] {
        let d = dir(root: root)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: d, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        return files
            .filter { $0.pathExtension.lowercased() == "json" }
            .map { url in
                let m = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return FCDocRef(url: url, name: url.deletingPathExtension().lastPathComponent, mtime: m)
            }
            .sorted { $0.mtime > $1.mtime }
    }

    static func load(url: URL) -> FCDocument? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard var doc = try? dec.decode(FCDocument.self, from: data) else { return nil }
        doc.name = url.deletingPathExtension().lastPathComponent
        return doc
    }

    @discardableResult
    static func save(_ doc: FCDocument, url: URL) -> Bool {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(doc) else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    static func url(root: URL, name: String) -> URL {
        dir(root: root).appendingPathComponent(sanitize(name) + ".json")
    }

    /// 同名自动加序号（不覆盖任何已有文件）
    static func uniqueURL(root: URL, name: String) -> URL {
        let base = sanitize(name)
        var candidate = dir(root: root).appendingPathComponent(base + ".json")
        var i = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir(root: root).appendingPathComponent("\(base) \(i).json")
            i += 1
        }
        return candidate
    }

    static func sanitize(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let fallback = _L("未命名流程图", "Untitled")
        return cleaned.isEmpty ? fallback : String(cleaned.prefix(60))
    }
}

// MARK: - 编辑器状态（工具 / 选择 / 撤销栈 / 缩放）

enum FCTool: String, CaseIterable, Identifiable {
    case select
    case rect, roundedRect, ellipse, diamond, parallelogram, cylinder, capsule, note
    case text, group, edge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .select: return _L("选择", "Select")
        case .text: return _L("文本框", "Text")
        case .group: return _L("分组", "Group")
        case .edge: return _L("连线", "Connect")
        default: return FCShapeKind(rawValue: rawValue)?.label ?? rawValue
        }
    }

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .text: return "textformat"
        case .group: return "rectangle.dashed"
        case .edge: return "arrow.triangle.branch"
        default: return FCShapeKind(rawValue: rawValue)?.symbol ?? "square"
        }
    }

    var shape: FCShapeKind? { FCShapeKind(rawValue: rawValue) }
}

@MainActor
final class FlowchartEditor: ObservableObject {
    @Published var doc: FCDocument
    @Published var selection: Set<String> = []
    @Published var tool: FCTool = .select
    @Published var zoom: CGFloat = 1
    @Published var offset: CGSize = .zero
    @Published var editingID: String?
    @Published var dirty = false
    /// 画布可视尺寸（画布回填，供「适应窗口」用）
    @Published var canvasSize: CGSize = .zero
    /// 连线拖拽中的临时预览（起点 + 当前点，doc 坐标）
    @Published var pendingEdge: (from: String, anchor: FCAnchor, point: CGPoint)?

    let url: URL
    private var undoStack: [FCDocument] = []
    private var redoStack: [FCDocument] = []
    private var interactionSnapshot: FCDocument?
    private let undoLimit = 60

    init(doc: FCDocument, url: URL) {
        self.doc = doc
        self.url = url
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var hasSelection: Bool { !selection.isEmpty }

    /// 选中项的样式（检查器显示用：取第一个选中元素）
    var primaryStyle: FCStyle? {
        selection.first.flatMap { doc.style(of: $0) }
    }

    var allIDs: Set<String> {
        Set(doc.nodes.map(\.id)).union(doc.texts.map(\.id))
            .union(doc.groups.map(\.id)).union(doc.edges.map(\.id))
    }

    var selectedEdges: [FCEdge] { doc.edges.filter { selection.contains($0.id) } }

    var hasEdgeSelection: Bool { !selectedEdges.isEmpty }

    var hasShapeSelection: Bool {
        doc.nodes.contains { selection.contains($0.id) } || doc.texts.contains { selection.contains($0.id) }
            || doc.groups.contains { selection.contains($0.id) }
    }

    /// 检查器改样式（进撤销栈）
    func applyStyle(_ change: @escaping (inout FCStyle) -> Void) {
        let ids = selection
        guard !ids.isEmpty else { return }
        commit { $0.applyStyle(ids, change) }
    }

    /// 滑杆拖动中：预览（不进撤销栈）
    func previewStyle(_ change: @escaping (inout FCStyle) -> Void) {
        let ids = selection
        guard !ids.isEmpty else { return }
        preview { $0.applyStyle(ids, change) }
    }

    func applyEdges(_ change: @escaping (inout FCEdge) -> Void) {
        let ids = selection
        guard !ids.isEmpty else { return }
        commit { doc in
            for i in doc.edges.indices where ids.contains(doc.edges[i].id) { change(&doc.edges[i]) }
        }
    }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        let ids = selection
        commit { $0.remove(ids) }
        selection = []
    }

    func duplicateSelection() {
        guard !selection.isEmpty else { return }
        let ids = selection
        var fresh: Set<String> = []
        commit { fresh = $0.duplicate(ids) }
        selection = fresh
    }

    func autoNumber() {
        commit { $0.autoNumberNodes() }
    }

    func nudge(dx: Double, dy: Double) {
        let ids = selection
        guard !ids.isEmpty else { return }
        commit { $0.translate(ids, dx: dx, dy: dy) }
    }

    /// 一次性提交（先把旧状态压入撤销栈）
    func commit(_ change: (inout FCDocument) -> Void) {
        let before = doc
        var next = doc
        change(&next)
        guard next != before else { return }
        undoStack.append(before)
        if undoStack.count > undoLimit { undoStack.removeFirst(undoStack.count - undoLimit) }
        redoStack.removeAll()
        doc = next
        doc.updatedAt = Date()
        dirty = true
    }

    /// 拖拽过程中的高频更新（不压栈、不置脏；结束时用 commitEnd 落一次）
    func preview(_ change: (inout FCDocument) -> Void) {
        var next = doc
        change(&next)
        doc = next
    }

    /// 拖拽开始：记录快照（结束时若真有变化才进撤销栈）
    func beginInteraction() {
        interactionSnapshot = doc
    }

    func endInteraction() {
        guard let before = interactionSnapshot else { return }
        interactionSnapshot = nil
        guard doc != before else { return }
        undoStack.append(before)
        if undoStack.count > undoLimit { undoStack.removeFirst(undoStack.count - undoLimit) }
        redoStack.removeAll()
        dirty = true
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(doc)
        doc = last
        selection = selection.filter { id in
            doc.nodes.contains { $0.id == id } || doc.texts.contains { $0.id == id }
                || doc.groups.contains { $0.id == id } || doc.edges.contains { $0.id == id }
        }
        dirty = true
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(doc)
        doc = next
        dirty = true
    }

    func save() {
        var copy = doc
        copy.name = url.deletingPathExtension().lastPathComponent
        if FlowchartStore.save(copy, url: url) {
            doc.name = copy.name
            dirty = false
        }
    }

    /// 100% 缩放并把内容摆到视图中央
    func resetZoom() {
        zoom = 1
        let size = canvasSize
        let bounds = doc.contentBounds
        // 居中：doc 点 bounds.mid 变换后应落在画布正中（zoom = 1）
        offset = CGSize(width: size.width / 2 - bounds.midX,
                        height: size.height / 2 - bounds.midY)
    }

    /// 缩放适配：把内容完整放进给定尺寸
    func fit(in size: CGSize, padding: CGFloat = 32) {
        let bounds = doc.contentBounds.insetBy(dx: -padding, dy: -padding)
        guard bounds.width > 1, bounds.height > 1, size.width > 1, size.height > 1 else { return }
        let scale = min(size.width / bounds.width, size.height / bounds.height)
        zoom = min(max(scale, 0.2), 2.4)
        offset = CGSize(width: (size.width - bounds.width * zoom) / 2 - bounds.minX * zoom,
                        height: (size.height - bounds.height * zoom) / 2 - bounds.minY * zoom)
    }
}

// MARK: - 解码容错小工具（JSON 允许手工编辑，缺字段回落默认值）

private extension KeyedDecodingContainer {
    func v<T: Decodable>(_ type: T.Type, _ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(type, forKey: key)) .flatMap { $0 } ?? fallback
    }

    func vOpt<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}

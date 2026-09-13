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

    /// 自环默认配对边：上↔右、下↔左（避免同一条边出又回，线会叠在一起）
    var selfLoopPartner: FCAnchor {
        switch self {
        case .top, .auto: return .right
        case .right: return .bottom
        case .bottom: return .left
        case .left: return .top
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

// MARK: - 全局样式（整套图一个样式）

/// 全局样式预设：不做「逐个元素选填充色」，整张图统一一种画风。
enum FCGlobalPreset: String, Codable, CaseIterable, Hashable {
    /// 柔和填充（默认）：强调色淡底 + 描边
    case soft
    /// 线框：纸底 + 强调色描边
    case outline
    /// 实心：强调色填充 + 反白文字
    case flat
    /// 极简：只描边不填充
    case plain

    var label: String {
        switch self {
        case .soft: return _L("柔和", "Soft")
        case .outline: return _L("线框", "Outline")
        case .flat: return _L("实心", "Solid")
        case .plain: return _L("极简", "Plain")
        }
    }

    var symbol: String {
        switch self {
        case .soft: return "square.fill"
        case .outline: return "square"
        case .flat: return "square.inset.filled"
        case .plain: return "square.dashed"
        }
    }
}

/// 全局样式：整张图共用（图形、连线、文字一起变），改一处全图统一。
struct FCGlobalStyle: Codable, Equatable, Hashable {
    var preset: FCGlobalPreset = .soft
    /// 强调色（nil = 跟随主题强调色）
    var accent: String?
    /// 描边粗细（图形与连线共用）
    var lineWidth: Double = 1.8
    /// 图形圆角
    var corner: Double = 10
    /// 字号
    var fontSize: Double = 13
    /// 填充浓度（柔和 / 实心预设用）
    var fillOpacity: Double = 0.16
    /// 连线虚线
    var dashed: Bool = false

    static let `default` = FCGlobalStyle()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preset = c.v(FCGlobalPreset.self, .preset, .soft)
        accent = c.vOpt(String.self, .accent)
        lineWidth = c.v(Double.self, .lineWidth, 1.8)
        corner = c.v(Double.self, .corner, 10)
        fontSize = c.v(Double.self, .fontSize, 13)
        fillOpacity = c.v(Double.self, .fillOpacity, 0.16)
        dashed = c.v(Bool.self, .dashed, false)
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
    /// 手动断点（拉线时右键落下的拐点，按顺序经过；空 = 自动路由）
    var waypoints: [CGPoint] = []

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
        waypoints = c.v([CGPoint].self, .waypoints, [])
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
/// 剪切板片段：跨图粘贴用（id 会重排，连线两端一起重映射；粘贴多次不会撞 id）
struct FCPasteboardPayload: Codable, Equatable {
    var nodes: [FCNode] = []
    var edges: [FCEdge] = []
    var texts: [FCTextItem] = []
    var groups: [FCGroup] = []

    static let pasteboardType = NSPasteboard.PasteboardType("com.gzhysu.marknote.flowchart")

    init() {}

    init(doc: FCDocument, ids: Set<String>) {
        nodes = doc.nodes.filter { ids.contains($0.id) }
        texts = doc.texts.filter { ids.contains($0.id) }
        groups = doc.groups.filter { ids.contains($0.id) }
        // 连线：显式选中的 + 两端都在选区里的（和「复制」语义一致）
        let nodeIDs = Set(nodes.map(\.id))
        edges = doc.edges.filter {
            ids.contains($0.id) || (nodeIDs.contains($0.fromNode) && nodeIDs.contains($0.toNode))
        }
    }

    var allIDs: Set<String> {
        Set(nodes.map(\.id)).union(edges.map(\.id))
            .union(texts.map(\.id)).union(groups.map(\.id))
    }

    var isEmpty: Bool { nodes.isEmpty && edges.isEmpty && texts.isEmpty && groups.isEmpty }

    var bounds: CGRect {
        var box: CGRect?
        for n in nodes { box = box.map { $0.union(n.rect) } ?? n.rect }
        for t in texts { box = box.map { $0.union(t.rect) } ?? t.rect }
        for g in groups { box = box.map { $0.union(g.rect) } ?? g.rect }
        return box ?? CGRect(x: 0, y: 0, width: 0, height: 0)
    }

    /// 全新 id + 可选平移（粘贴用）
    func freshCopy(dx: Double = 0, dy: Double = 0) -> FCPasteboardPayload {
        var out = FCPasteboardPayload()
        var map: [String: String] = [:]
        for n in nodes {
            var copy = n
            copy.id = UUID().uuidString
            copy.x += dx; copy.y += dy
            map[n.id] = copy.id
            out.nodes.append(copy)
        }
        for t in texts {
            var copy = t
            copy.id = UUID().uuidString
            copy.x += dx; copy.y += dy
            out.texts.append(copy)
        }
        for g in groups {
            var copy = g
            copy.id = UUID().uuidString
            copy.x += dx; copy.y += dy
            out.groups.append(copy)
        }
        for e in edges {
            var copy = e
            copy.id = UUID().uuidString
            // 只保留两端都在这批里的连线，避免粘出悬空边
            guard let from = map[e.fromNode], let to = map[e.toNode] else { continue }
            copy.fromNode = from
            copy.toNode = to
            out.edges.append(copy)
        }
        return out
    }
}

/// 一张流程图（= `source/flowchart/<名字>.json`）
// MARK: - 右键菜单（纯描述，视图层只负责转成 NSMenuItem；便于单测）

enum FCMenuAction: Equatable {
    case editText
    case duplicate
    case bringToFront
    case sendToBack
    case startEdge
    case delete
    case editLabel
    case route(FCRoute)
    case arrow(FCArrow)
    case newProcess
    case paste
    case toggleGrid
    case selectAll
    case fit
}

indirect enum FCMenuEntry: Equatable {
    case item(title: String, checked: Bool, action: FCMenuAction)
    case submenu(title: String, entries: [FCMenuEntry])
    case separator
}

enum FCContextMenu {
    /// 按命中对象给出菜单：图形 / 文本 / 分组 → 编辑与层级；连线 → 标签与走法；空白 → 新建与视图
    static func entries(doc: FCDocument, selection: Set<String>, hitID: String?,
                        at p: CGPoint) -> [FCMenuEntry] {
        var out: [FCMenuEntry] = []
        let node = hitID.flatMap { id in doc.nodes.first { $0.id == id } }
        let edge = hitID.flatMap { id in doc.edges.first { $0.id == id } }
        let text = hitID.flatMap { id in doc.texts.first { $0.id == id } }
        let group = hitID.flatMap { id in doc.groups.first { $0.id == id } }

        if node != nil || text != nil || group != nil {
            out.append(.item(title: _L("编辑文字", "Edit Text"), checked: false, action: .editText))
            out.append(.separator)
            out.append(.item(title: _L("复制", "Duplicate"), checked: false, action: .duplicate))
            out.append(.item(title: _L("置顶", "Bring to Front"), checked: false, action: .bringToFront))
            out.append(.item(title: _L("置底", "Send to Back"), checked: false, action: .sendToBack))
            out.append(.separator)
            out.append(.item(title: _L("从这里连线", "Draw Connection"), checked: false, action: .startEdge))
            out.append(.separator)
            out.append(.item(title: _L("删除", "Delete"), checked: false, action: .delete))
        } else if let e = edge {
            out.append(.item(title: _L("编辑标签", "Edit Label"), checked: false, action: .editLabel))
            out.append(.separator)
            out.append(.submenu(title: _L("线的走法", "Line Route"), entries: FCRoute.allCases.map {
                .item(title: $0.label, checked: e.route == $0, action: .route($0))
            }))
            out.append(.submenu(title: _L("箭头", "Arrow"), entries: FCArrow.allCases.map {
                .item(title: $0.label, checked: e.arrow == $0, action: .arrow($0))
            }))
            out.append(.separator)
            out.append(.item(title: _L("删除连线", "Delete Connection"), checked: false, action: .delete))
        } else {
            out.append(.item(title: _L("新建执行框", "New Process Box"), checked: false, action: .newProcess))
            out.append(.item(title: _L("粘贴到此处", "Paste Here"), checked: false, action: .paste))
            out.append(.separator)
            out.append(.item(title: doc.showGrid ? _L("隐藏网格", "Hide Grid") : _L("显示网格", "Show Grid"),
                             checked: doc.showGrid, action: .toggleGrid))
            out.append(.separator)
            out.append(.item(title: _L("全选", "Select All"), checked: false, action: .selectAll))
            out.append(.item(title: _L("适应窗口", "Fit"), checked: false, action: .fit))
        }
        return out
    }
}

/// 右键坐标换算：窗口坐标（左下原点）→ 画布内坐标（左上原点）
enum FCContextGeometry {
    static func canvasPoint(windowPoint: CGPoint, canvasFrameInWindow: CGRect?) -> CGPoint {
        guard let frame = canvasFrameInWindow, frame.width > 1 else { return windowPoint }
        return CGPoint(x: windowPoint.x - frame.minX, y: frame.maxY - windowPoint.y)
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
    /// 全局样式：整张图共用（不逐个元素调填充/描边）
    var style: FCGlobalStyle = .default
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
        style = c.v(FCGlobalStyle.self, .style, .default)
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
        for e in edges {
            guard let path = edgePath(e) else { continue }
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

    // MARK: 连线路由（带平行边错开）

    /// 端点键：连线 id + 是哪一端（f=起点 / t=终点）
    func endpointKey(_ edgeID: String, isFrom: Bool) -> String { "\(edgeID)|\(isFrom ? "f" : "t")" }

    /// 自环走哪两条边：用户显式指定过就照做，否则自动挑「已有连线最少」的一对相邻边
    /// （默认 上/右）—— 避免自环和别的分支挤在同一条边上。
    func selfLoopSides(for edge: FCEdge) -> (from: FCAnchor, to: FCAnchor) {
        if edge.fromAnchor != .auto || edge.toAnchor != .auto {
            let f = edge.fromAnchor == .auto ? FCAnchor.top : edge.fromAnchor
            var t = edge.toAnchor == .auto ? FCAnchor.right : edge.toAnchor
            if t == f { t = f.selfLoopPartner }
            return (f, t)
        }
        let index = nodesByID()
        var used: [FCAnchor: Int] = [:]
        for e in edges where e.id != edge.id && e.fromNode != e.toNode {
            guard let a = index[e.fromNode], let b = index[e.toNode] else { continue }
            let fs = e.fromAnchor == .auto ? FCEdgePath.autoAnchor(from: a.rect, toward: b.rect) : e.fromAnchor
            let ts = e.toAnchor == .auto ? FCEdgePath.autoAnchor(from: b.rect, toward: a.rect) : e.toAnchor
            if a.id == edge.fromNode { used[fs, default: 0] += 1 }
            if b.id == edge.fromNode { used[ts, default: 0] += 1 }
        }
        let pairs: [(FCAnchor, FCAnchor)] = [(.top, .right), (.right, .bottom),
                                             (.bottom, .left), (.left, .top)]
        return pairs.min {
            (used[$0.0, default: 0] + used[$0.1, default: 0])
                < (used[$1.0, default: 0] + used[$1.1, default: 0])
        } ?? (.top, .right)
    }

    /// **统一分配锚点**：挂在同一个图形同一条边上的所有线（含自环两端、往返双线）
    /// 沿边均分错开 —— 否则它们全挤在边中点上，线就叠成一条（写循环时最明显）。
    /// 返回值：端点键 → 沿边方向的偏移量。
    func anchorOffsets() -> [String: CGFloat] {
        let index = nodesByID()
        var groups: [String: [(key: String, angle: CGFloat)]] = [:]
        func add(_ edgeID: String, _ isFrom: Bool, _ node: FCNode, _ side: FCAnchor, _ toward: CGPoint) {
            let p = FCEdgePath.point(side, in: node.rect)
            let angle = atan2(toward.y - p.y, toward.x - p.x)
            groups["\(node.id)|\(side.rawValue)", default: []].append((endpointKey(edgeID, isFrom: isFrom), angle))
        }
        for e in edges {
            guard let a = index[e.fromNode], let b = index[e.toNode] else { continue }
            let centerB = CGPoint(x: b.rect.midX, y: b.rect.midY)
            let centerA = CGPoint(x: a.rect.midX, y: a.rect.midY)
            if a.id == b.id {
                // 自环：走最空的两条边，两端各占一条
                let sides = selfLoopSides(for: e)
                add(e.id, true, a, sides.from, centerA)
                add(e.id, false, b, sides.to, centerB)
            } else {
                let fs = e.fromAnchor == .auto ? FCEdgePath.autoAnchor(from: a.rect, toward: b.rect) : e.fromAnchor
                let ts = e.toAnchor == .auto ? FCEdgePath.autoAnchor(from: b.rect, toward: a.rect) : e.toAnchor
                add(e.id, true, a, fs, centerB)
                add(e.id, false, b, ts, centerA)
            }
        }
        var out: [String: CGFloat] = [:]
        let step: CGFloat = 30
        for (_, list) in groups {
            let sorted = list.sorted { $0.angle == $1.angle ? $0.key < $1.key : $0.angle < $1.angle }
            let n = sorted.count
            for (i, item) in sorted.enumerated() {
                out[item.key] = (CGFloat(i) - CGFloat(n - 1) / 2) * step
            }
        }
        return out
    }

    /// 再加一条线时它会落在哪（拉线预览用，避免预览和已有线重叠）
    func nextAnchorOffset(nodeID: String, side: FCAnchor) -> CGFloat {
        let offsets = anchorOffsets()
        let prefix = "|\(side.rawValue)"
        _ = prefix
        var used: [CGFloat] = []
        let index = nodesByID()
        for e in edges {
            guard let a = index[e.fromNode], let b = index[e.toNode] else { continue }
            func resolvedSide(of node: FCNode, other: FCNode, anchor: FCAnchor, isFrom: Bool) -> FCAnchor {
                if a.id == b.id {
                    if isFrom { return anchor == .auto ? .top : anchor }
                    let t = anchor == .auto ? FCAnchor.right : anchor
                    let f = e.fromAnchor == .auto ? FCAnchor.top : e.fromAnchor
                    return t == f ? f.selfLoopPartner : t
                }
                return anchor == .auto ? FCEdgePath.autoAnchor(from: node.rect, toward: other.rect) : anchor
            }
            if a.id == nodeID,
               resolvedSide(of: a, other: b, anchor: e.fromAnchor, isFrom: true) == side {
                used.append(offsets[endpointKey(e.id, isFrom: true)] ?? 0)
            }
            if b.id == nodeID,
               resolvedSide(of: b, other: a, anchor: e.toAnchor, isFrom: false) == side {
                used.append(offsets[endpointKey(e.id, isFrom: false)] ?? 0)
            }
        }
        let step: CGFloat = 30
        guard let minOffset = used.min(), let maxOffset = used.max() else { return 0 }
        return maxOffset + step / 2 > -minOffset + step / 2 ? maxOffset + step : minOffset - step
    }

    /// 计算连线的实际路径（渲染 / 命中 / 导出统一走这里，避免各处锚点不一致）
    func edgePath(_ edge: FCEdge) -> FCEdgePath? {
        let offsets = anchorOffsets()
        return FCEdgePath(edge: edge, nodes: nodesByID(),
                          fromOffset: offsets[endpointKey(edge.id, isFrom: true)] ?? 0,
                          toOffset: offsets[endpointKey(edge.id, isFrom: false)] ?? 0,
                          selfLoopSides: edge.fromNode == edge.toNode ? selfLoopSides(for: edge) : nil)
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
        for e in edges.reversed() {
            guard let path = edgePath(e) else { continue }
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
            guard let path = edgePath(e) else { return nil }
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

    /// 置顶 / 置底（数组顺序即层级；图形 / 文本 / 分组各自成栈）
    mutating func bringToFront(_ ids: Set<String>) { reorder(ids, toFront: true) }

    mutating func sendToBack(_ ids: Set<String>) { reorder(ids, toFront: false) }

    private mutating func reorder(_ ids: Set<String>, toFront: Bool) {
        func move<T>(_ list: inout [T], key: (T) -> String) {
            let picked = list.filter { ids.contains(key($0)) }
            guard !picked.isEmpty else { return }
            list.removeAll { ids.contains(key($0)) }
            if toFront {
                list.append(contentsOf: picked)
            } else {
                list.insert(contentsOf: picked, at: 0)
            }
        }
        move(&nodes, key: \.id)
        move(&texts, key: \.id)
        move(&groups, key: \.id)
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

    init?(edge: FCEdge, nodes: [String: FCNode], fromOffset: CGFloat = 0, toOffset: CGFloat = 0,
          selfLoopSides: (from: FCAnchor, to: FCAnchor)? = nil) {
        guard let a = nodes[edge.fromNode], let b = nodes[edge.toNode] else { return nil }
        // 自环（A → A）：绕出去再折回来（写循环用），默认走「上边出、右边回」
        if edge.fromNode == edge.toNode {
            let out: CGFloat = 22
            let fromAnchor = selfLoopSides?.from
                ?? (edge.fromAnchor == .auto ? FCAnchor.top : edge.fromAnchor)
            var toAnchor = selfLoopSides?.to
                ?? (edge.toAnchor == .auto ? FCAnchor.right : edge.toAnchor)
            if toAnchor == fromAnchor { toAnchor = fromAnchor.selfLoopPartner }
            let pts = FCEdgePath.selfLoop(rect: a.rect, from: fromAnchor, to: toAnchor, out: out,
                                          fromOffset: fromOffset, toOffset: toOffset)
            start = pts[0]
            segments = zip(pts, pts.dropFirst()).map { .line($1) }
            return
        }
        let fromAnchor = edge.fromAnchor == .auto ? FCEdgePath.autoAnchor(from: a.rect, toward: b.rect) : edge.fromAnchor
        let toAnchor = edge.toAnchor == .auto ? FCEdgePath.autoAnchor(from: b.rect, toward: a.rect) : edge.toAnchor
        // 锚点沿着图形边缘错开（同一侧挂多条线时由 FCDocument.anchorOffsets 统一分配）
        let p0 = FCEdgePath.point(fromAnchor, in: a.rect, along: fromOffset)
        let p1 = FCEdgePath.point(toAnchor, in: b.rect, along: toOffset)
        let n0 = fromAnchor.vector
        let n1 = toAnchor.vector
        start = p0

        switch edge.route {
        case .straight:
            segments = [.line(p1)]

        case .orthogonal:
            // 手动断点：线按用户右键落下的拐点依次经过（每两站之间用一段折线正交连起来）
            if !edge.waypoints.isEmpty {
                let pts = FCEdgePath.throughWaypoints(p0: p0, p1: p1, waypoints: edge.waypoints)
                segments = zip(pts, pts.dropFirst()).map { .line($1) }
                break
            }
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

    /// 依次经过手动断点的正交折线：相邻两站之间若不对齐，就插一个拐点
    /// （拐点方向跟随上一段的走向，画出来像「手动折的线」）。
    static func throughWaypoints(p0: CGPoint, p1: CGPoint, waypoints: [CGPoint]) -> [CGPoint] {
        let stops = [p0] + waypoints + [p1]
        var out: [CGPoint] = [stops[0]]
        for i in 1..<stops.count {
            guard let a = out.last else { break }
            let b = stops[i]
            let dx = abs(b.x - a.x), dy = abs(b.y - a.y)
            if dx < 0.5 || dy < 0.5 { out.append(b); continue }
            // 上一段是竖的 → 先竖后横；否则先横后竖（更贴近手动画线的手感）
            let previous = out.count >= 2 ? out[out.count - 2] : nil
            let cameVertical = previous.map { abs($0.x - a.x) < abs($0.y - a.y) } ?? true
            out.append(cameVertical ? CGPoint(x: a.x, y: b.y) : CGPoint(x: b.x, y: a.y))
            out.append(b)
        }
        return FCRouter.mergeCollinear(out)
    }

    /// 自环路径：从 `from` 边探出去，绕到 `to` 边回来（全程正交，拐角由渲染层做圆角）
    static func selfLoop(rect: CGRect, from: FCAnchor, to: FCAnchor, out: CGFloat,
                         fromOffset: CGFloat = 0, toOffset: CGFloat = 0) -> [CGPoint] {
        let p0 = point(from, in: rect, along: fromOffset)
        let p1 = point(to, in: rect, along: toOffset)
        let n0 = from.vector
        let n1 = to.vector
        let s0 = CGPoint(x: p0.x + n0.dx * out, y: p0.y + n0.dy * out)
        let s1 = CGPoint(x: p1.x + n1.dx * out, y: p1.y + n1.dy * out)
        let vertical0 = abs(n0.dy) > 0.5, vertical1 = abs(n1.dy) > 0.5
        var mid: [CGPoint] = []
        if vertical0 != vertical1 {
            // 相邻两边 → 一个拐角绕过去
            mid = [CGPoint(x: vertical0 ? s1.x : s0.x, y: vertical0 ? s0.y : s1.y)]
        } else if vertical0 {
            // 同在上/下两边 → 走右侧走廊（或左侧，取更近的一侧）
            let corridorX = rect.maxX + out
            mid = [CGPoint(x: corridorX, y: s0.y), CGPoint(x: corridorX, y: s1.y)]
        } else {
            let corridorY = rect.maxY + out
            mid = [CGPoint(x: s0.x, y: corridorY), CGPoint(x: s1.x, y: corridorY)]
        }
        return FCRouter.mergeCollinear([p0, s0] + mid + [s1, p1])
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

    /// 锚点坐标；`along` = 沿该边方向偏移（平行边错开用，自动夹在边缘内）
    static func point(_ anchor: FCAnchor, in rect: CGRect, along: CGFloat = 0) -> CGPoint {
        let margin: CGFloat = 8
        switch anchor {
        case .top, .bottom:
            let limit = max(0, rect.width / 2 - margin)
            let x = rect.midX + min(max(along, -limit), limit)
            return CGPoint(x: x, y: anchor == .top ? rect.minY : rect.maxY)
        case .left, .right:
            let limit = max(0, rect.height / 2 - margin)
            let y = rect.midY + min(max(along, -limit), limit)
            return CGPoint(x: anchor == .left ? rect.minX : rect.maxX, y: y)
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
    /// 语义化起点 / 终点（都是圆角胶囊，只是默认文字与图标不同）
    case start, end
    case text, group, edge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .select: return _L("选择", "Select")
        case .start: return _L("开始", "Start")
        case .end: return _L("结束", "End")
        // 流程图语境下这两个就是「执行框」「判断框」（通用矩形在「更多形状」里）
        case .rect: return _L("执行", "Process")
        case .diamond: return _L("判断", "Decision")
        case .text: return _L("文本框", "Text")
        case .group: return _L("分组", "Group")
        case .edge: return _L("连线", "Connect")
        default: return FCShapeKind(rawValue: rawValue)?.label ?? rawValue
        }
    }

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .start: return "play.circle"
        case .end: return "stop.circle"
        case .text: return "textformat"
        case .group: return "rectangle.dashed"
        case .edge: return "arrow.triangle.branch"
        default: return FCShapeKind(rawValue: rawValue)?.symbol ?? "square"
        }
    }

    var shape: FCShapeKind? {
        switch self {
        case .start: return .capsule     // 开始：圆角胶囊
        case .end: return .ellipse       // 结束：椭圆（和开始明显区分）
        default: return FCShapeKind(rawValue: rawValue)
        }
    }
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
    /// 拉线过程中右键落下的手动断点（doc 坐标，按顺序）
    @Published var pendingWaypoints: [CGPoint] = []

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

    /// 复制到系统剪切板（自研类型，跨图也能粘）
    @discardableResult
    func copySelection() -> Bool {
        guard !selection.isEmpty else { return false }
        let payload = FCPasteboardPayload(doc: doc, ids: selection)
        guard !payload.isEmpty, let data = try? JSONEncoder().encode(payload) else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: FCPasteboardPayload.pasteboardType)
        return true
    }

    func cutSelection() {
        guard copySelection() else { return }
        deleteSelection()
    }

    /// 粘贴：`at` 给了就贴到那个点（右键菜单），否则原位偏移 24pt（⌘V）
    @discardableResult
    func pasteFromClipboard(at point: CGPoint? = nil) -> Bool {
        guard let data = NSPasteboard.general.data(forType: FCPasteboardPayload.pasteboardType),
              let payload = try? JSONDecoder().decode(FCPasteboardPayload.self, from: data),
              !payload.isEmpty else { return false }
        let b = payload.bounds
        let dx: Double, dy: Double
        if let point {
            dx = Double(point.x - b.minX)
            dy = Double(point.y - b.minY)
        } else {
            dx = 24; dy = 24
        }
        let fresh = payload.freshCopy(dx: dx, dy: dy)
        commit { doc in
            doc.nodes.append(contentsOf: fresh.nodes)
            doc.edges.append(contentsOf: fresh.edges)
            doc.texts.append(contentsOf: fresh.texts)
            doc.groups.append(contentsOf: fresh.groups)
        }
        selection = fresh.allIDs
        return true
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

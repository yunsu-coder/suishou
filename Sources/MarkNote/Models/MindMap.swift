import AppKit
import Foundation

// MARK: - 思维导图数据模型（视图插件 `mindmap`）
//
// 规则（见 docs/05-内置插件库.md）：
// · 作用域：只读写**当前工作台**的 `source/mindmap/`；不碰别的工作台；
// · 界面外壳与画布**都用主题变量**（与流程图不同：思维导图没有「自由取色」的例外，
//   分支颜色由主题 accent 派生，保证任何主题下都协调）；
// · 不预设默认文字（根节点就叫「中心主题」）；卸载即干净：删掉 `source/mindmap/` 即可。

/// 一个节点（树结构；子节点顺序 = 展示顺序）
struct MindMapNode: Codable, Identifiable, Equatable {
    var id: String
    var text: String
    /// 备注（不画在图上，悬停看；导出 Markdown 时作为缩进说明）
    var note: String?
    /// 折叠：不显示子节点（节点上显示「+N」）
    var collapsed: Bool
    /// 分支配色档位（0…5；只有根的一级分支有意义，子节点继承）
    var accent: Int
    /// 手动左右：0 = 自动，1 = 强制右侧，-1 = 强制左侧（只对根的一级分支有效）
    var side: Int
    /// 手动微调（自动布局之上的偏移，拖拽节点时写入）
    var offsetX: Double
    var offsetY: Double
    var children: [MindMapNode]

    init(id: String = MindMapNode.newID(), text: String = "", note: String? = nil,
         collapsed: Bool = false, accent: Int = 0, side: Int = 0,
         offsetX: Double = 0, offsetY: Double = 0, children: [MindMapNode] = []) {
        self.id = id
        self.text = text
        self.note = note
        self.collapsed = collapsed
        self.accent = accent
        self.side = side
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.children = children
    }

    static func newID() -> String { "n" + UUID().uuidString.prefix(8).lowercased() }

    /// 宽容解码：老文件缺字段时给默认值，而不是整份打不开
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? nil ?? MindMapNode.newID()
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? nil ?? ""
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? nil
        collapsed = (try? c.decodeIfPresent(Bool.self, forKey: .collapsed)) ?? nil ?? false
        accent = (try? c.decodeIfPresent(Int.self, forKey: .accent)) ?? nil ?? 0
        side = (try? c.decodeIfPresent(Int.self, forKey: .side)) ?? nil ?? 0
        offsetX = (try? c.decodeIfPresent(Double.self, forKey: .offsetX)) ?? nil ?? 0
        offsetY = (try? c.decodeIfPresent(Double.self, forKey: .offsetY)) ?? nil ?? 0
        children = (try? c.decodeIfPresent([MindMapNode].self, forKey: .children)) ?? nil ?? []
    }
}

/// 布局模式：左右平衡（默认，像 XMind 思维导图）或全部靠右（像逻辑图）
enum MindMapLayoutMode: String, Codable, CaseIterable {
    case balanced
    case right

    var label: String {
        switch self {
        case .balanced: return _L("左右平衡", "Balanced")
        case .right: return _L("全在右侧", "Right only")
        }
    }
}

/// 一份导图（= `source/mindmap/<名字>.json`）
struct MindMapDocument: Codable, Equatable {
    var title: String
    var root: MindMapNode
    var layoutMode: MindMapLayoutMode
    var created: String
    var updated: String

    init(title: String = _L("未命名导图", "Untitled Map"),
         root: MindMapNode = MindMapNode(text: _L("中心主题", "Central topic")),
         layoutMode: MindMapLayoutMode = .balanced,
         created: String = MindMapDocument.now(), updated: String = MindMapDocument.now()) {
        self.title = title
        self.root = root
        self.layoutMode = layoutMode
        self.created = created
        self.updated = updated
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? nil ?? _L("未命名导图", "Untitled Map")
        root = (try? c.decodeIfPresent(MindMapNode.self, forKey: .root)) ?? nil
            ?? MindMapNode(text: _L("中心主题", "Central topic"))
        layoutMode = (try? c.decodeIfPresent(MindMapLayoutMode.self, forKey: .layoutMode)) ?? nil ?? .balanced
        created = (try? c.decodeIfPresent(String.self, forKey: .created)) ?? nil ?? MindMapDocument.now()
        updated = (try? c.decodeIfPresent(String.self, forKey: .updated)) ?? nil ?? MindMapDocument.now()
    }

    static func now() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }
}

// MARK: - 树操作（纯函数，便于测试与撤销）

extension MindMapNode {
    /// 可见节点数（折叠的子树不算）
    var visibleCount: Int {
        guard !collapsed else { return 1 }
        return 1 + children.reduce(0) { $0 + $1.visibleCount }
    }

    /// 全部节点数（含折叠）
    var totalCount: Int { 1 + children.reduce(0) { $0 + $1.totalCount } }

    var maxDepth: Int {
        guard !children.isEmpty, !collapsed else { return 0 }
        return 1 + (children.map(\.maxDepth).max() ?? 0)
    }

    func node(id: String) -> MindMapNode? {
        if self.id == id { return self }
        for child in children {
            if let found = child.node(id: id) { return found }
        }
        return nil
    }

    /// 父节点 id（根返回 nil）
    func parentID(of id: String) -> String? {
        for child in children {
            if child.id == id { return self.id }
            if let found = child.parentID(of: id) { return found }
        }
        return nil
    }

    /// 从根到该节点的 id 路径
    func path(to id: String) -> [String]? {
        if self.id == id { return [id] }
        for child in children {
            if let sub = child.path(to: id) { return [self.id] + sub }
        }
        return nil
    }

    /// 某节点的直接子节点（按顺序）
    func children(of id: String) -> [MindMapNode] {
        node(id: id)?.children ?? []
    }

    mutating func update(id: String, _ transform: (inout MindMapNode) -> Void) {
        if self.id == id {
            transform(&self)
            return
        }
        for i in children.indices {
            children[i].update(id: id, transform)
        }
    }

    /// 插入节点：parentID 不存在时忽略
    mutating func insert(_ node: MindMapNode, parentID: String, at index: Int? = nil) {
        if self.id == parentID {
            // 新插入的子节点默认展开父节点（否则用户看不到刚建的东西）
            collapsed = false
            let i = min(max(index ?? children.count, 0), children.count)
            children.insert(node, at: i)
            return
        }
        for i in children.indices {
            children[i].insert(node, parentID: parentID, at: index)
        }
    }

    /// 摘除子树（返回被摘除的节点，供撤销）
    @discardableResult
    mutating func remove(id: String) -> MindMapNode? {
        if let i = children.firstIndex(where: { $0.id == id }) {
            return children.remove(at: i)
        }
        for i in children.indices {
            if let removed = children[i].remove(id: id) { return removed }
        }
        return nil
    }

    /// 同级下移 / 上移（在父节点里换位）
    mutating func moveSibling(id: String, delta: Int) -> Bool {
        if let i = children.firstIndex(where: { $0.id == id }) {
            let j = i + delta
            guard children.indices.contains(j) else { return false }
            children.swapAt(i, j)
            return true
        }
        for i in children.indices {
            if children[i].moveSibling(id: id, delta: delta) { return true }
        }
        return false
    }

    /// 换父节点（拖拽重排）。返回 false = 非法（拖到自己或自己的子孙下面）
    mutating func move(id: String, toParent parentID: String, at index: Int? = nil) -> Bool {
        guard id != parentID, let target = self.node(id: id), target.node(id: parentID) == nil else {
            return false                                   // 防环
        }
        guard let moved = remove(id: id) else { return false }
        var copy = moved
        copy.offsetX = 0                                   // 换爹后不再带旧偏移
        copy.offsetY = 0
        insert(copy, parentID: parentID, at: index)
        return true
    }

    /// 前序遍历（父在前），带深度与父 id
    func flatten(parent: String? = nil, depth: Int = 0) -> [(node: MindMapNode, parent: String?, depth: Int)] {
        var out: [(MindMapNode, String?, Int)] = [(self, parent, depth)]
        if !collapsed {
            for child in children { out += child.flatten(parent: id, depth: depth + 1) }
        }
        return out
    }
}

// MARK: - 自动布局

/// 一个节点的画布矩形（含自动布局 + 手动偏移）
struct MindMapBox: Identifiable, Equatable {
    var id: String
    var rect: CGRect
    var depth: Int
    var accent: Int
    var collapsed: Bool
    var childCount: Int
    var text: String
    var side: Int            // -1 左 / 1 右（根为 0）
}

/// 一条父子连线（贝塞尔控制点已算好，画的时候直接用）
struct MindMapEdge: Equatable {
    var from: CGPoint
    var to: CGPoint
    var control1: CGPoint
    var control2: CGPoint
    var depth: Int
    var accent: Int
}

enum MindMapLayout {
    /// 文本量尺：折行到 maxWidth 以内（与画布用同一套字体，保证不裁字）
    static func measure(_ text: String, font: NSFont, maxWidth: CGFloat = 240) -> CGSize {
        let t = text.isEmpty ? " " : text
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        let attr = NSAttributedString(string: t, attributes: [.font: font, .paragraphStyle: para])
        let rect = attr.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                                     options: [.usesLineFragmentOrigin, .usesFontLeading])
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    /// 节点在画布上的尺寸（文字 + 内边距；根节点大一号）
    static func nodeSize(text: String, depth: Int, font: NSFont) -> CGSize {
        let padX: CGFloat = depth == 0 ? 20 : 14
        let padY: CGFloat = depth == 0 ? 14 : 9
        let size = measure(text, font: font)
        return CGSize(width: max(size.width + padX * 2, depth == 0 ? 96 : 64),
                      height: max(size.height + padY * 2, depth == 0 ? 46 : 34))
    }

    /// 布局：返回所有可见节点矩形 + 连线
    /// - Parameters:
    ///   - gapX: 相邻层级横向间距
    ///   - gapY: 同级子树之间的纵向间距
    static func layout(_ root: MindMapNode, font: NSFont,
                       mode: MindMapLayoutMode = .balanced,
                       gapX: CGFloat = 56, gapY: CGFloat = 14)
        -> (boxes: [MindMapBox], edges: [MindMapEdge]) {
        var boxes: [MindMapBox] = []
        // 连线先只记「谁连谁」，等所有坐标定下来再算点（避免平移时到处补丁）
        var pending: [(parent: String, child: String, depth: Int, accent: Int, side: Int)] = []

        let rootSize = nodeSize(text: root.text, depth: 0, font: font)
        let rootRect = CGRect(x: -rootSize.width / 2, y: -rootSize.height / 2,
                              width: rootSize.width, height: rootSize.height)
        boxes.append(MindMapBox(id: root.id, rect: rootRect, depth: 0, accent: 0,
                                collapsed: root.collapsed, childCount: root.children.count,
                                text: root.text, side: 0))
        guard !root.collapsed else { return (boxes, []) }

        // 一级分支分左右：balanced = 交替；right = 全在右；节点手动指定优先
        let sides = branchSides(count: root.children.count, mode: mode,
                                forced: root.children.map(\.side))
        var cursorY: [Int: CGFloat] = [:]      // 每侧各排各的（否则左右分支会叠在一起）
        for (i, child) in root.children.enumerated() {
            let side = sides[i]
            let accent = (child.accent % branchColorCount + branchColorCount) % branchColorCount
            let band = layoutSubtree(child, depth: 1, side: side, accent: accent, font: font,
                                     gapX: gapX, gapY: gapY, boxes: &boxes, pending: &pending)
            // 子树整体挂到根节点旁边（同侧依次向下排）
            let x: CGFloat
            if side > 0 {
                x = rootRect.maxX + gapX
            } else {
                x = rootRect.minX - gapX - band.width
            }
            let y = cursorY[side] ?? 0
            shiftSubtree(band.ids, dx: x, dy: y, boxes: &boxes)
            cursorY[side] = y + band.height + gapY
            pending.append((root.id, child.id, 0, accent, side))
        }

        // 左右两侧各自垂直居中（围绕根节点）
        for side in [-1, 1] {
            let ids = boxes.filter { $0.depth > 0 && $0.side == side }.map(\.id)
            guard let top = ids.compactMap({ id in boxes.first { $0.id == id }?.rect.minY }).min(),
                  let bottom = ids.compactMap({ id in boxes.first { $0.id == id }?.rect.maxY }).max()
            else { continue }
            let dy = rootRect.midY - (top + bottom) / 2
            shiftSubtree(ids, dx: 0, dy: dy, boxes: &boxes)
        }

        // 手动偏移最后叠加
        for i in boxes.indices {
            guard let node = root.node(id: boxes[i].id) else { continue }
            guard node.offsetX != 0 || node.offsetY != 0 else { continue }
            boxes[i].rect = boxes[i].rect.offsetBy(dx: node.offsetX, dy: node.offsetY)
        }

        // 坐标定完了，再生成连线点
        var edges: [MindMapEdge] = []
        for p in pending {
            guard let from = boxes.first(where: { $0.id == p.parent })?.rect,
                  let to = boxes.first(where: { $0.id == p.child })?.rect else { continue }
            edges.append(edge(from: from, to: to, depth: p.depth, accent: p.accent, side: p.side))
        }
        return (boxes, edges)
    }

    /// 分支配色档数（主题 accent 派生出这么多色相）
    static let branchColorCount = 6

    /// 一级分支的左右分配
    static func branchSides(count: Int, mode: MindMapLayoutMode, forced: [Int]) -> [Int] {
        (0..<count).map { i in
            let f = forced.indices.contains(i) ? forced[i] : 0
            if f != 0 { return f > 0 ? 1 : -1 }
            switch mode {
            case .right: return 1
            case .balanced: return i % 2 == 0 ? 1 : -1      // 交替，视觉平衡
            }
        }
    }

    /// 布局一棵子树（返回它占的竖直带，坐标以 (0,0) 为左上起点）
    private static func layoutSubtree(_ node: MindMapNode, depth: Int, side: Int, accent: Int,
                                      font: NSFont, gapX: CGFloat, gapY: CGFloat,
                                      boxes: inout [MindMapBox],
                                      pending: inout [(parent: String, child: String, depth: Int, accent: Int, side: Int)])
        -> (ids: [String], width: CGFloat, height: CGFloat) {
        let size = nodeSize(text: node.text, depth: depth, font: font)
        boxes.append(MindMapBox(id: node.id, rect: CGRect(x: 0, y: 0, width: size.width, height: size.height),
                                depth: depth, accent: accent,
                                collapsed: node.collapsed, childCount: node.children.count,
                                text: node.text, side: side))
        guard !node.collapsed, !node.children.isEmpty else {
            return ([node.id], size.width, size.height)
        }

        // ① 先把每棵子树量出来（此时它们各自以 0 为顶）
        struct Band { var ids: [String]; var width: CGFloat; var height: CGFloat; var childID: String }
        var bands: [Band] = []
        for child in node.children {
            let b = layoutSubtree(child, depth: depth + 1, side: side, accent: accent,
                                  font: font, gapX: gapX, gapY: gapY,
                                  boxes: &boxes, pending: &pending)
            bands.append(Band(ids: b.ids, width: b.width, height: b.height, childID: child.id))
        }

        // ② 子节点沿竖直方向依次排开；父节点与子节点整体垂直居中
        let totalHeight = bands.map(\.height).reduce(0, +) + gapY * CGFloat(max(0, bands.count - 1))
        var cursor = (size.height - totalHeight) / 2
        var maxChildWidth: CGFloat = 0
        var allIDs: [String] = [node.id]
        for band in bands {
            let dx = side > 0 ? size.width + gapX : -(band.width + gapX)
            shiftSubtree(band.ids, dx: dx, dy: cursor, boxes: &boxes)
            pending.append((node.id, band.childID, depth, accent, side))
            allIDs += band.ids
            maxChildWidth = max(maxChildWidth, band.width)
            cursor += band.height + gapY
        }

        // ③ 归一化：整棵子树（含父）顶到 y = 0
        let minY = allIDs.compactMap { id in boxes.first { $0.id == id }?.rect.minY }.min() ?? 0
        shiftSubtree(allIDs, dx: 0, dy: -minY, boxes: &boxes)
        return (allIDs, size.width + gapX + maxChildWidth, max(size.height, totalHeight))
    }

    private static func shiftSubtree(_ ids: [String], dx: CGFloat, dy: CGFloat,
                                     boxes: inout [MindMapBox]) {
        guard dx != 0 || dy != 0 else { return }
        for i in boxes.indices where ids.contains(boxes[i].id) {
            boxes[i].rect = boxes[i].rect.offsetBy(dx: dx, dy: dy)
        }
    }

    /// 父子连线：横向的 S 形贝塞尔（思维导图常见手感）
    private static func edge(from parent: CGRect, to child: CGRect, depth: Int,
                             accent: Int, side: Int) -> MindMapEdge {
        let start = CGPoint(x: side > 0 ? parent.maxX : parent.minX, y: parent.midY)
        let end = CGPoint(x: side > 0 ? child.minX : child.maxX, y: child.midY)
        let midX = (start.x + end.x) / 2
        return MindMapEdge(from: start, to: end,
                           control1: CGPoint(x: midX, y: start.y),
                           control2: CGPoint(x: midX, y: end.y),
                           depth: depth, accent: accent)
    }

    /// 所有节点的包围盒（导出 / 适应窗口用）
    static func bounds(_ boxes: [MindMapBox]) -> CGRect {
        guard let first = boxes.first else { return .zero }
        return boxes.dropFirst().reduce(first.rect) { $0.union($1.rect) }
    }
}

// MARK: - Markdown 大纲互转（和笔记打通：大纲 ⇄ 导图）

enum MindMapOutline {
    /// Markdown 大纲 → 导图。
    /// 认 `#` 标题、`-` / `*` / `+` 列表、`1.` 有序列表；用缩进（2 空格或 1 个 Tab）判断层级。
    static func parse(markdown: String) -> MindMapNode? {
        struct Item { var depth: Int; var text: String }
        var items: [Item] = []
        var headingStack: [String] = []      // 最近一层的标题路径
        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix { $0 == "#" }.count
                let title = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty else { continue }
                if headingStack.count >= level { headingStack = Array(headingStack.prefix(level - 1)) }
                headingStack.append(title)
                items.append(Item(depth: level - 1, text: title))
                continue
            }
            // 列表项：算缩进层级（2 空格 = 1 级）
            let indent = line.prefix { $0 == " " || $0 == "\t" }
                .reduce(0) { $0 + ($1 == "\t" ? 2 : 1) }
            var body = trimmed
            for prefix in ["- ", "* ", "+ "] where body.hasPrefix(prefix) {
                body = String(body.dropFirst(prefix.count)); break
            }
            if let r = body.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                body = String(body[r.upperBound...])
            }
            guard !body.isEmpty, body != trimmed || trimmed.hasPrefix("-") || trimmed.hasPrefix("*") else { continue }
            let depth = headingStack.count + indent / 2
            items.append(Item(depth: max(0, depth), text: body.trimmingCharacters(in: .whitespaces)))
        }
        guard !items.isEmpty else { return nil }
        // 逐条挂到树上：深度优先，用栈维护「当前路径」
        var root = MindMapNode(text: items[0].text)
        var stack: [(id: String, depth: Int)] = [(root.id, items[0].depth)]
        for item in items.dropFirst() {
            while let last = stack.last, last.depth >= item.depth { stack.removeLast() }
            let parentID = stack.last?.id ?? root.id
            let node = MindMapNode(text: item.text)
            root.insert(node, parentID: parentID)
            stack.append((node.id, item.depth))
        }
        return root
    }

    /// 导图 → Markdown 大纲（供「写回笔记」用）
    static func markdown(_ root: MindMapNode, bullet: String = "- ") -> String {
        var lines: [String] = []
        func walk(_ node: MindMapNode, depth: Int) {
            let pad = String(repeating: "  ", count: max(0, depth - 1))
            if depth == 0 {
                lines.append("# \(node.text.isEmpty ? _L("中心主题", "Central topic") : node.text)")
            } else {
                lines.append(pad + bullet + (node.text.isEmpty ? " " : node.text))
            }
            if let note = node.note, !note.isEmpty {
                lines.append(String(repeating: "  ", count: depth) + "> " + note)
            }
            if !node.collapsed {
                for child in node.children { walk(child, depth: depth + 1) }
            }
        }
        walk(root, depth: 0)
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - 文档存储（当前工作台 source/mindmap/）

struct MindMapEntry: Identifiable, Equatable {
    var id: String { name }
    var name: String          // 文件名（不含 .json）
    var title: String
    var updated: String
    var nodeCount: Int
}

enum MindMapStore {
    static func dir(_ workspace: URL) -> URL {
        workspace.appendingPathComponent("source/mindmap", isDirectory: true)
    }

    /// 文件名清洗：汉字 / 字母 / 数字 / 常见标点保留，其余压成「-」
    static func sanitize(_ raw: String) -> String {
        NotesStore.noteStem(raw)
    }

    /// 工作台内唯一文件名
    static func uniqueName(_ workspace: URL, _ base: String) -> String {
        let dir = dir(workspace)
        let clean = sanitize(base)
        var name = clean
        var i = 2
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(name).json").path) {
            name = "\(clean)-\(i)"
            i += 1
        }
        return name
    }

    static func list(_ workspace: URL) -> [MindMapEntry] {
        let dir = dir(workspace)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        var out: [MindMapEntry] = []
        for f in files where f.pathExtension.lowercased() == "json" {
            guard let doc = load(workspace, name: f.deletingPathExtension().lastPathComponent) else { continue }
            out.append(MindMapEntry(name: f.deletingPathExtension().lastPathComponent,
                                    title: doc.title,
                                    updated: doc.updated,
                                    nodeCount: doc.root.totalCount))
        }
        return out.sorted { $0.updated > $1.updated }
    }

    static func load(_ workspace: URL, name: String) -> MindMapDocument? {
        let url = dir(workspace).appendingPathComponent("\(name).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MindMapDocument.self, from: data)
    }

    @discardableResult
    static func save(_ workspace: URL, name: String, doc: MindMapDocument) -> Bool {
        let dir = dir(workspace)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(doc)
            try data.write(to: dir.appendingPathComponent("\(sanitize(name)).json"), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func delete(_ workspace: URL, name: String) -> Bool {
        let url = dir(workspace).appendingPathComponent("\(name).json")
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)   // 走废纸篓，可恢复
            return true
        } catch {
            return false
        }
    }

    /// 新建一份空导图（带一个根节点）
    static func create(_ workspace: URL, title: String) -> String {
        let name = uniqueName(workspace, title)
        let doc = MindMapDocument(title: title, root: MindMapNode(text: title))
        save(workspace, name: name, doc: doc)
        return name
    }
}

// MARK: - 分支配色（主题 accent 派生，跟着主题走）

enum MindMapPalette {
    /// 第 index 档分支色（0…5）：把主题 accent 的色相按 40° 一档旋开，饱和度/明度沿用主题
    static func branch(_ index: Int, base: NSColor, dark: Bool) -> NSColor {
        let i = ((index % MindMapLayout.branchColorCount) + MindMapLayout.branchColorCount)
            % MindMapLayout.branchColorCount
        guard let hsb = base.usingColorSpace(.deviceRGB) else { return base }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        hsb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let hue = (Double(h) * 360 + Double(i) * 40).truncatingRemainder(dividingBy: 360) / 360
        // 深色主题下稍提亮、浅色主题下稍压暗，保证和底色有对比
        let sat = min(1, max(0.18, Double(s) * (dark ? 0.9 : 1.0)))
        let bri = min(1, max(0.25, Double(b) * (dark ? 1.12 : 0.96)))
        return NSColor(hue: hue, saturation: sat, brightness: bri, alpha: a == 0 ? 1 : a)
    }
}

import AppKit
import XCTest
@testable import MarkNote

/// 思维导图：树操作 / 自动布局 / Markdown 大纲互转 / 工作台存储 / 分支配色。
final class MindMapTests: XCTestCase {

    private func sampleTree() -> MindMapNode {
        var root = MindMapNode(text: "产品路线")
        let a = MindMapNode(text: "体验")
        let b = MindMapNode(text: "性能")
        root.insert(a, parentID: root.id)
        root.insert(b, parentID: root.id)
        root.insert(MindMapNode(text: "启动速度"), parentID: b.id)
        root.insert(MindMapNode(text: "内存占用"), parentID: b.id)
        return root
    }

    // MARK: - 树操作

    func testTreeBasics() {
        let root = sampleTree()
        XCTAssertEqual(root.totalCount, 5)
        XCTAssertEqual(root.maxDepth, 2)
        XCTAssertEqual(root.children.count, 2)
        let perf = root.children[1]
        XCTAssertEqual(root.parentID(of: perf.children[0].id), perf.id)
        XCTAssertEqual(root.path(to: perf.children[0].id)?.count, 3)
        XCTAssertNil(root.parentID(of: root.id), "根节点没有父")
    }

    func testRemoveReturnsSubtreeAndCollapseHidesChildren() {
        var root = sampleTree()
        let perf = root.children[1]
        let removed = root.remove(id: perf.id)
        XCTAssertEqual(removed?.totalCount, 3, "删掉的分支要整棵返回（撤销用）")
        XCTAssertEqual(root.totalCount, 2)

        var tree = sampleTree()
        let perfID = tree.children[1].id
        tree.update(id: perfID) { $0.collapsed = true }
        XCTAssertEqual(tree.visibleCount, 3, "折叠后子孙不参与布局")
        XCTAssertEqual(tree.totalCount, 5, "但数据还在")
        // 折叠时插子节点会自动展开（否则用户看不到刚建的东西）
        tree.insert(MindMapNode(text: "新子节点"), parentID: perfID)
        XCTAssertFalse(tree.node(id: perfID)?.collapsed ?? true)
    }

    func testMoveGuardsAgainstCycles() {
        var root = sampleTree()
        let experience = root.children[0]
        let perf = root.children[1]
        XCTAssertFalse(root.move(id: perf.id, toParent: perf.children[0].id),
                       "不能把节点拖到自己的子孙下面")
        XCTAssertFalse(root.move(id: root.id, toParent: experience.id), "根节点不能被搬走")
        XCTAssertTrue(root.move(id: perf.children[0].id, toParent: experience.id))
        XCTAssertEqual(root.children[0].children.count, 1)
        XCTAssertEqual(root.children[1].children.count, 1)
    }

    func testMoveSiblingReorders() {
        var root = sampleTree()
        let firstID = root.children[0].id
        XCTAssertTrue(root.moveSibling(id: firstID, delta: 1))
        XCTAssertEqual(root.children[1].id, firstID)
        XCTAssertFalse(root.moveSibling(id: firstID, delta: 1), "已经在最后一个位置")
    }

    // MARK: - 自动布局

    func testLayoutPlacesAllVisibleNodesAndEdges() {
        let root = sampleTree()
        let font = NSFont.systemFont(ofSize: 13)
        let (boxes, edges) = MindMapLayout.layout(root, font: font)
        XCTAssertEqual(boxes.count, root.visibleCount)
        XCTAssertEqual(edges.count, root.totalCount - 1, "除根之外每个节点一条连线")
        XCTAssertEqual(boxes.filter { $0.depth == 0 }.count, 1)
        XCTAssertEqual(boxes.filter { $0.depth == 1 }.count, 2)
    }

    func testCollapsedSubtreeIsNotLaidOut() {
        var root = sampleTree()
        let perfID = root.children[1].id
        root.update(id: perfID) { $0.collapsed = true }
        let (boxes, _) = MindMapLayout.layout(root, font: .systemFont(ofSize: 13))
        XCTAssertEqual(boxes.count, 3, "折叠分支的两个子节点不进布局")
        XCTAssertTrue(boxes.first { $0.id == perfID }?.collapsed == true)
    }

    func testSiblingsDoNotOverlapSameSide() {
        var root = MindMapNode(text: "根")
        for i in 0..<6 {
            root.insert(MindMapNode(text: "分支 \(i)"), parentID: root.id)
        }
        let (boxes, _) = MindMapLayout.layout(root, font: .systemFont(ofSize: 13))
        for side in [1, -1] {
            let rects = boxes.filter { $0.side == side }.map(\.rect).sorted { $0.minY < $1.minY }
            for (a, b) in zip(rects, rects.dropFirst()) {
                XCTAssertGreaterThanOrEqual(b.minY, a.maxY - 0.5, "同侧子树不能重叠：\(a) vs \(b)")
            }
        }
    }

    func testParentIsVerticallyCenteredOnChildren() {
        var root = MindMapNode(text: "根")
        let branch = MindMapNode(text: "分支")
        root.insert(branch, parentID: root.id)
        for i in 0..<3 {
            root.insert(MindMapNode(text: "子 \(i)"), parentID: branch.id)
        }
        let (boxes, _) = MindMapLayout.layout(root, font: .systemFont(ofSize: 13))
        let parent = try? XCTUnwrap(boxes.first { $0.id == branch.id })
        let kids = boxes.filter { $0.depth == 2 }
        let top = kids.map(\.rect.minY).min() ?? 0
        let bottom = kids.map(\.rect.maxY).max() ?? 0
        XCTAssertEqual(parent?.rect.midY ?? 0, (top + bottom) / 2, accuracy: 1.0,
                       "父节点应垂直居中于子节点之间")
    }

    func testLayoutModesAndManualSide() {
        var root = MindMapNode(text: "根")
        for i in 0..<4 { root.insert(MindMapNode(text: "b\(i)"), parentID: root.id) }
        let font = NSFont.systemFont(ofSize: 13)
        let rightOnly = MindMapLayout.layout(root, font: font, mode: .right).boxes
        XCTAssertEqual(rightOnly.filter { $0.depth == 1 }.map(\.side), [1, 1, 1, 1])
        let balanced = MindMapLayout.layout(root, font: font, mode: .balanced).boxes
        XCTAssertEqual(balanced.filter { $0.depth == 1 }.map(\.side), [1, -1, 1, -1])
        // 手动指定侧向优先于模式
        root.update(id: root.children[0].id) { $0.side = -1 }
        let forced = MindMapLayout.layout(root, font: font, mode: .right).boxes
        XCTAssertEqual(forced.first { $0.id == root.children[0].id }?.side, -1)
    }

    func testBoundsCoverAllBoxes() {
        let (boxes, _) = MindMapLayout.layout(sampleTree(), font: .systemFont(ofSize: 13))
        let bounds = MindMapLayout.bounds(boxes)
        for box in boxes {
            XCTAssertTrue(bounds.insetBy(dx: -1, dy: -1).contains(box.rect), "包围盒要覆盖 \(box.text)")
        }
    }

    // MARK: - Markdown 大纲互转

    func testOutlineParseAndRoundTrip() throws {
        let markdown = """
        # 读书笔记
        ## 第一章
        - 要点 A
          - 细节 A1
          - 细节 A2
        ## 第二章
        1. 要点 B
        """
        let root = try XCTUnwrap(MindMapOutline.parse(markdown: markdown))
        XCTAssertEqual(root.text, "读书笔记")
        XCTAssertEqual(root.children.map(\.text), ["第一章", "第二章"])
        XCTAssertEqual(root.children[0].children.map(\.text), ["要点 A"])
        XCTAssertEqual(root.children[0].children[0].children.map(\.text), ["细节 A1", "细节 A2"])
        let back = MindMapOutline.markdown(root)
        XCTAssertTrue(back.hasPrefix("# 读书笔记\n- 第一章\n  - 要点 A\n    - 细节 A1"))
        XCTAssertTrue(back.contains("- 第二章"))
        XCTAssertTrue(back.contains("  - 要点 B"))
    }

    func testOutlineParseRejectsPlainText() {
        XCTAssertNil(MindMapOutline.parse(markdown: "就是一句话，没有任何结构"))
    }

    // MARK: - 存储

    @MainActor
    func testStoreRoundTripListAndDelete() throws {
        let (_, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let name = MindMapStore.create(dir, title: "季度规划")
        XCTAssertEqual(name, "季度规划")
        var doc = try XCTUnwrap(MindMapStore.load(dir, name: name))
        doc.root.insert(MindMapNode(text: "目标一"), parentID: doc.root.id)
        doc.title = "季度规划（改）"
        XCTAssertTrue(MindMapStore.save(dir, name: name, doc: doc))
        let reloaded = try XCTUnwrap(MindMapStore.load(dir, name: name))
        XCTAssertEqual(reloaded.root.children.count, 1)
        XCTAssertEqual(reloaded.title, "季度规划（改）")
        let list = MindMapStore.list(dir)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].nodeCount, 2)
        // 同名再建 → 自动加序号，不覆盖
        let second = MindMapStore.create(dir, title: "季度规划")
        XCTAssertEqual(second, "季度规划-2")
        XCTAssertEqual(MindMapStore.list(dir).count, 2)
        XCTAssertTrue(MindMapStore.delete(dir, name: name))
        XCTAssertEqual(MindMapStore.list(dir).count, 1)
        // 文件名清洗：路径分隔符与冒号不能进文件名
        XCTAssertEqual(MindMapStore.sanitize("2026/Q3: 规划"), "2026-Q3 规划")
    }

    // MARK: - 分支配色（跟主题走）

    func testBranchColorsDeriveFromThemeAccent() {
        let accent = NSColor(srgbRed: 0.35, green: 0.55, blue: 0.95, alpha: 1)
        let colors = (0..<MindMapLayout.branchColorCount).map {
            MindMapPalette.branch($0, base: accent, dark: false)
        }
        // 六档色相各不相同（至少两两可见差异）
        for i in 0..<colors.count {
            for j in (i + 1)..<colors.count {
                let d = abs(colors[i].hueComponent - colors[j].hueComponent)
                XCTAssertGreaterThan(max(d, 1 - d), 0.02, "第 \(i)/\(j) 档颜色太接近")
            }
        }
        // 旋转 6 档会回到原色相附近
        let back = MindMapPalette.branch(MindMapLayout.branchColorCount, base: accent, dark: false)
        XCTAssertEqual(back.hueComponent, colors[0].hueComponent, accuracy: 0.001)
    }
}

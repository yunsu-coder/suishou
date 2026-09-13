import AppKit
import SwiftUI
import XCTest
@testable import MarkNote

/// 流程图（视图插件 `flowchart`）：注册门槛、数据落盘、几何与编辑操作。
final class FlowchartTests: XCTestCase {

    @MainActor
    private func makePackage(_ viewsJSON: String, manifestID: String) throws -> PluginManager {
        let (_, temp) = try TestEnv.makeStore()
        let dir = temp.appendingPathComponent(".plugins/\(manifestID)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try """
        { "id": "\(manifestID)", "name": "测试流程图", "version": "1.0.0", "kind": "views", "main": "views.json" }
        """.write(to: dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try viewsJSON.write(to: dir.appendingPathComponent("views.json"), atomically: true, encoding: .utf8)
        UserDefaults.standard.set(true, forKey: "pluginEnabled.\(manifestID)")
        let pm = PluginManager.shared
        pm.scan(workspaceDir: temp)
        return pm
    }

    private func tempRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("marknote-flow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: 插件注册

    @MainActor
    func testFlowchartViewRegistersAsMainArea() throws {
        let pm = try makePackage("""
        [ { "id": "flow", "name": "流程图", "type": "flowchart", "scope": "workspace", "placement": "main" } ]
        """, manifestID: "view-flowchart-ok")
        defer { UserDefaults.standard.removeObject(forKey: "pluginEnabled.view-flowchart-ok") }
        let views = pm.allViews().filter { $0.type == .flowchart }
        XCTAssertEqual(views.count, 1)
        XCTAssertEqual(views.first?.scope, .workspace)
        XCTAssertEqual(views.first?.placement, .main)
        XCTAssertNotNil(pm.mainAreaView(type: .flowchart))
        XCTAssertTrue(pm.viewIssues(for: "view-flowchart-ok").isEmpty)
    }

    /// 仓库里真正要交付的插件包（plugins-market/view-flowchart）本身要能过扫描
    @MainActor
    func testShippedFlowchartPackageScansClean() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // MarkNoteTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // 仓库根
        let src = repo.appendingPathComponent("plugins-market/view-flowchart", isDirectory: true)
        try XCTSkipUnless(FileManager.default.fileExists(atPath: src.appendingPathComponent("manifest.json").path),
                          "跳过：不在仓库里跑")
        let (_, temp) = try TestEnv.makeStore()
        let dst = temp.appendingPathComponent(".plugins/view-flowchart", isDirectory: true)
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        for name in ["manifest.json", "views.json"] {
            try FileManager.default.copyItem(at: src.appendingPathComponent(name),
                                             to: dst.appendingPathComponent(name))
        }
        UserDefaults.standard.set(true, forKey: "pluginEnabled.view-flowchart")
        defer { UserDefaults.standard.removeObject(forKey: "pluginEnabled.view-flowchart") }
        let pm = PluginManager.shared
        pm.scan(workspaceDir: temp)
        XCTAssertTrue(pm.viewIssues(for: "view-flowchart").isEmpty,
                      "插件包不该有扫描问题：\(pm.viewIssues(for: "view-flowchart"))")
        let view = try XCTUnwrap(pm.allViews().first { $0.type == .flowchart }, "流程图插件应注册")
        XCTAssertEqual(view.name, "流程图")
        XCTAssertEqual(view.scope, .workspace)
        XCTAssertEqual(view.placement, .sheet, "流程图是弹窗大窗口形态（sheet）")
    }

    @MainActor
    func testFlowchartRejectsGlobalScopeAndPanelPlacement() throws {
        let pm = try makePackage("""
        [ { "id": "flow", "name": "越权流程图", "type": "flowchart", "scope": "global", "placement": "main" },
          { "id": "flow2", "name": "面板流程图", "type": "flowchart", "scope": "workspace", "placement": "panel" } ]
        """, manifestID: "view-flowchart-bad")
        defer { UserDefaults.standard.removeObject(forKey: "pluginEnabled.view-flowchart-bad") }
        XCTAssertTrue(pm.allViews().filter { $0.type == .flowchart }.isEmpty)
        let issues = pm.viewIssues(for: "view-flowchart-bad")
        XCTAssertTrue(issues.contains { $0.contains("workspace") }, "global 作用域必须被拦截")
        XCTAssertTrue(issues.contains { $0.contains("placement") }, "面板形态必须被拦截")
    }

    // MARK: 落盘

    func testDocumentRoundTripAndDefaults() throws {
        let root = try tempRoot()
        var doc = FCDocument(name: "登录流程")
        var node = FCNode(kind: .diamond, origin: CGPoint(x: 40, y: 60), text: "已登录？")
        node.style.fill = "#FF0000"
        node.style.dashed = true
        doc.nodes = [node]
        doc.edges = [FCEdge(fromNode: node.id, toNode: node.id)]

        let url = FlowchartStore.uniqueURL(root: root, name: "登录流程")
        XCTAssertTrue(FlowchartStore.save(doc, url: url))
        let loaded = try XCTUnwrap(FlowchartStore.load(url: url))
        XCTAssertEqual(loaded.name, "登录流程", "文件名即图名")
        XCTAssertEqual(loaded.nodes.first?.style.fill, "#FF0000")
        XCTAssertTrue(loaded.nodes.first?.style.dashed ?? false)
        XCTAssertEqual(loaded.edges.count, 1)

        // 手工编辑过的 JSON（缺字段）也要能读：缺省值兜底
        let partial = root.appendingPathComponent("source/flowchart/半成品.json")
        try """
        { "nodes": [ { "id": "n1", "text": "只有文字" } ] }
        """.write(to: partial, atomically: true, encoding: .utf8)
        let loose = try XCTUnwrap(FlowchartStore.load(url: partial))
        XCTAssertEqual(loose.nodes.count, 1)
        XCTAssertEqual(loose.nodes[0].kind, .roundedRect, "缺 kind 回落圆角矩形")
        XCTAssertEqual(loose.nodes[0].w, 140, "缺尺寸回落默认尺寸")
        XCTAssertTrue(loose.showGrid, "缺开关回落为显示网格")
    }

    func testStoreListsAndNeverOverwrites() throws {
        let root = try tempRoot()
        let a = FlowchartStore.url(root: root, name: "同名")
        FlowchartStore.save(FCDocument(name: "同名"), url: a)
        let b = FlowchartStore.uniqueURL(root: root, name: "同名")
        XCTAssertNotEqual(a.path, b.path)
        XCTAssertEqual(b.lastPathComponent, "同名 2.json")
        XCTAssertEqual(FlowchartStore.list(root: root).count, 1, "未写入的候选不应出现在列表里")
        FlowchartStore.save(FCDocument(name: "同名"), url: b)
        XCTAssertEqual(FlowchartStore.list(root: root).count, 2)
        XCTAssertEqual(FlowchartStore.sanitize("a/b:c"), "a-b-c")
        XCTAssertEqual(FlowchartStore.sanitize("   "), "未命名流程图")
        XCTAssertEqual(FlowchartStore.dir(root: root).path,
                       root.appendingPathComponent("source/flowchart").path)
    }

    // MARK: 自动编号

    func testAutoNumberFollowsTopologyThenPosition() {
        var doc = FCDocument()
        var c = FCNode(kind: .roundedRect, origin: CGPoint(x: 400, y: 300), text: "结束")
        var b = FCNode(kind: .roundedRect, origin: CGPoint(x: 200, y: 200), text: "2. 中间")
        var a = FCNode(kind: .capsule, origin: CGPoint(x: 10, y: 10), text: "开始")
        c.id = "c"; b.id = "b"; a.id = "a"
        doc.nodes = [c, b, a]   // 数组顺序故意打乱
        doc.edges = [FCEdge(fromNode: "a", toNode: "b"), FCEdge(fromNode: "b", toNode: "c")]
        doc.autoNumberNodes()
        let text = { (id: String) in doc.nodes.first { $0.id == id }?.text ?? "" }
        XCTAssertEqual(text("a"), "1. 开始")
        XCTAssertEqual(text("b"), "2. 中间", "旧序号先剥掉再加，不出现「2. 2.」")
        XCTAssertEqual(text("c"), "3. 结束")
    }

    func testAutoNumberHandlesCycles() {
        var doc = FCDocument()
        var n1 = FCNode(kind: .rect, origin: CGPoint(x: 0, y: 0), text: "甲")
        var n2 = FCNode(kind: .rect, origin: CGPoint(x: 0, y: 120), text: "乙")
        n1.id = "1"; n2.id = "2"
        doc.nodes = [n1, n2]
        doc.edges = [FCEdge(fromNode: "1", toNode: "2"), FCEdge(fromNode: "2", toNode: "1")]
        doc.autoNumberNodes()
        XCTAssertEqual(Set(doc.nodes.map(\.text)), ["1. 甲", "2. 乙"], "有环也要每个图形都编到号")
    }

    // MARK: 几何

    func testAutoAnchorPicksFacingSides() {
        let left = CGRect(x: 0, y: 0, width: 100, height: 60)
        let right = CGRect(x: 300, y: 10, width: 100, height: 60)
        XCTAssertEqual(FCEdgePath.autoAnchor(from: left, toward: right), .right)
        XCTAssertEqual(FCEdgePath.autoAnchor(from: right, toward: left), .left)
        let below = CGRect(x: 10, y: 300, width: 100, height: 60)
        XCTAssertEqual(FCEdgePath.autoAnchor(from: left, toward: below), .bottom)
        XCTAssertEqual(FCEdgePath.point(.top, in: left), CGPoint(x: 50, y: 0))
        XCTAssertEqual(FCEdgePath.point(.right, in: left), CGPoint(x: 100, y: 30))
    }

    func testOrthogonalRouteStaysOutsideNodesAndHasMidpoint() throws {
        var a = FCNode(kind: .roundedRect, origin: CGPoint(x: 0, y: 0))
        var b = FCNode(kind: .roundedRect, origin: CGPoint(x: 300, y: 160))
        a.id = "a"; b.id = "b"
        var edge = FCEdge(fromNode: "a", toNode: "b")
        edge.route = .orthogonal
        let p = try XCTUnwrap(FCEdgePath(edge: edge, nodes: ["a": a, "b": b]), "路由应能算出来")
        XCTAssertGreaterThanOrEqual(p.polyline.count, 3, "折线至少三段点")
        let mid = p.midpoint
        XCTAssertTrue(p.boundingBox.insetBy(dx: -1, dy: -1).contains(mid))
        XCTAssertGreaterThan(p.polylineLength, 200)
        XCTAssertLessThan(p.distance(to: mid), 1.0, "中点应落在路径上")
    }

    func testEdgeFollowsNodeMove() throws {
        var a = FCNode(kind: .rect, origin: CGPoint(x: 0, y: 0))
        var b = FCNode(kind: .rect, origin: CGPoint(x: 300, y: 0))
        a.id = "a"; b.id = "b"
        let edge = FCEdge(fromNode: "a", toNode: "b")
        let before = FCEdgePath(edge: edge, nodes: ["a": a, "b": b])
        b.x += 200
        let after = FCEdgePath(edge: edge, nodes: ["a": a, "b": b])
        XCTAssertNotEqual(before?.polyline.last, after?.polyline.last, "图形移动后连线终点跟着走")
        let endX = try XCTUnwrap(after?.polyline.last?.x)
        XCTAssertEqual(endX, b.rect.minX, accuracy: 0.01)
    }

    // MARK: 编辑操作

    // MARK: 智能正交路由（draw.io 风格）

    /// 无障碍：面对面锚点应合并成一条直线
    func testRouterStraightWhenClear() {
        let p0 = CGPoint(x: 0, y: 0), p1 = CGPoint(x: 200, y: 0)
        let path = FCRouter.route(p0: p0, n0: CGVector(dx: 1, dy: 0),
                                  p1: p1, n1: CGVector(dx: -1, dy: 0),
                                  obstacles: [])
        XCTAssertEqual(path.first, p0)
        XCTAssertEqual(path.last, p1)
        XCTAssertEqual(path.count, 2, "无障碍的面对面应为一条直线")
    }

    /// 中间横着障碍：路径必须绕开（不穿越），且首尾锚点保持精确
    func testRouterAvoidsObstacle() {
        let p0 = CGPoint(x: 0, y: 0), p1 = CGPoint(x: 260, y: 0)
        let obstacle = CGRect(x: 100, y: -50, width: 60, height: 100)
        let path = FCRouter.route(p0: p0, n0: CGVector(dx: 1, dy: 0),
                                  p1: p1, n1: CGVector(dx: -1, dy: 0),
                                  obstacles: [obstacle])
        XCTAssertEqual(path.first, p0)
        XCTAssertEqual(path.last, p1)
        XCTAssertFalse(FCRouter.collides(path, [obstacle.insetBy(dx: -10, dy: -10)]),
                       "路径不得穿过障碍（含 padding）")
        XCTAssertGreaterThan(path.count, 2, "必须有绕行拐点")
    }

    /// 共线合并：多余共线点应被删除
    func testRouterMergesCollinear() {
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 20, y: 0), CGPoint(x: 20, y: 30)]
        let merged = FCRouter.mergeCollinear(pts)
        XCTAssertEqual(merged, [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0), CGPoint(x: 20, y: 30)])
    }

    /// contentBounds 必须把连线的绕行路径计入：
    /// 否则导出 PNG / 适应窗口会把绕到图形包围盒外的线段裁掉。
    func testContentBoundsIncludesEdgeDetour() {
        var doc = FCDocument()
        var a = FCNode(kind: .rect, origin: CGPoint(x: 0, y: 0)); a.w = 60; a.h = 40
        var b = FCNode(kind: .rect, origin: CGPoint(x: 400, y: 0)); b.w = 60; b.h = 40
        var blocker = FCNode(kind: .rect, origin: CGPoint(x: 150, y: -150)); blocker.w = 120; blocker.h = 400
        doc.nodes = [a, b, blocker]
        var e = FCEdge(fromNode: a.id, toNode: b.id)
        e.fromAnchor = .right
        e.toAnchor = .left
        doc.edges = [e]

        let bounds = doc.contentBounds
        XCTAssertTrue(bounds.minY <= -100 || bounds.maxY >= 200,
                      "绕行路径（blocker 上下绕）应计入 bounds，实际：\(bounds)")
    }

    /// 远距离 + 多障碍（复现用户画布）：路径必须全程正交、不穿障碍
    func testRouterLongDistanceStaysOrthogonal() {
        let obstacles = [
            CGRect(x: 430, y: 60, width: 120, height: 48),    // 开始
            CGRect(x: 214, y: 182, width: 140, height: 64),   // A
            CGRect(x: 628, y: 468, width: 160, height: 70),   // C
            CGRect(x: 617, y: 534, width: 140, height: 64),   // 椭圆
            CGRect(x: 2945, y: 172, width: 102, height: 42),  // 远处矩形
        ]
        let p0 = CGPoint(x: 278 + 80, y: 318 + 70)            // B 底中点
        let p1 = CGPoint(x: 2945, y: 333 + 32)                // 远处矩形左中点
        let path = FCRouter.route(p0: p0, n0: CGVector(dx: 0, dy: 1),
                                  p1: p1, n1: CGVector(dx: -1, dy: 0),
                                  obstacles: obstacles)
        for i in 1..<path.count {
            let a = path[i - 1], b = path[i]
            XCTAssertTrue(abs(a.x - b.x) < 0.6 || abs(a.y - b.y) < 0.6,
                          "正交路由出现斜段：\(a) → \(b)")
        }
        XCTAssertFalse(FCRouter.collides(path, obstacles.map { $0.insetBy(dx: -9, dy: -9) }),
                       "路径不得穿过障碍")
    }

    /// 箭头绘制：direction 是"两端点差向量"（未归一化）——无论距离多远，
    /// 箭头都必须保持 size 尺度（曾把 2000pt 距离的箭头画成盖住半个画布的巨型三角）。
    func testArrowStaysSmallForLongDistanceDirection() {
        let tip = CGPoint(x: 500, y: 500)
        let huge = FCShape.arrow(tip: tip, direction: CGVector(dx: 2000, dy: -1500), size: 9)
        let h = huge.boundingRect
        // 未归一化时 back 点会跑到 9×2000=18000pt 之外；归一化后必须保持在 size 量级（斜向边界盒略大属正常几何）
        XCTAssertLessThan(h.width, 30, "箭头边界必须保持在 size 量级（宽）")
        XCTAssertLessThan(h.height, 30, "箭头边界必须保持在 size 量级（高）")
    }

    func testRemoveNodeRemovesItsEdges() {
        var doc = FCDocument()
        var a = FCNode(kind: .rect, origin: .zero)
        var b = FCNode(kind: .rect, origin: CGPoint(x: 200, y: 0))
        var c = FCNode(kind: .rect, origin: CGPoint(x: 400, y: 0))
        a.id = "a"; b.id = "b"; c.id = "c"
        doc.nodes = [a, b, c]
        doc.edges = [FCEdge(fromNode: "a", toNode: "b"), FCEdge(fromNode: "b", toNode: "c")]
        doc.remove(["b"])
        XCTAssertEqual(doc.nodes.count, 2)
        XCTAssertTrue(doc.edges.isEmpty, "被删图形的连线不能留成悬空边")
    }

    func testDuplicateRemapsInternalEdges() throws {
        var doc = FCDocument()
        var a = FCNode(kind: .rect, origin: .zero)
        var b = FCNode(kind: .rect, origin: CGPoint(x: 200, y: 0))
        a.id = "a"; b.id = "b"
        doc.nodes = [a, b]
        doc.edges = [FCEdge(fromNode: "a", toNode: "b")]
        let fresh = doc.duplicate(["a", "b"])
        XCTAssertEqual(fresh.count, 3, "两个图形 + 一条内部连线")
        XCTAssertEqual(doc.nodes.count, 4)
        let copy = try XCTUnwrap(doc.edges.last)
        XCTAssertNotEqual(copy.fromNode, "a", "连线要指向副本")
        XCTAssertTrue(fresh.contains(copy.fromNode))
        XCTAssertTrue(fresh.contains(copy.toNode))
    }

    func testAlignAndDistribute() {
        var doc = FCDocument()
        var a = FCNode(kind: .rect, origin: CGPoint(x: 0, y: 0))
        var b = FCNode(kind: .rect, origin: CGPoint(x: 100, y: 40))
        var c = FCNode(kind: .rect, origin: CGPoint(x: 260, y: 90))
        a.id = "a"; b.id = "b"; c.id = "c"
        doc.nodes = [a, b, c]
        doc.align(["a", "b", "c"], .top)
        XCTAssertEqual(Set(doc.nodes.map { $0.y }), [0], "顶对齐后 y 一致")
        doc.distribute(["a", "b", "c"], horizontal: true)
        let sorted = doc.nodes.sorted { $0.x < $1.x }
        let gap1 = sorted[1].x - (sorted[0].x + sorted[0].w)
        let gap2 = sorted[2].x - (sorted[1].x + sorted[1].w)
        XCTAssertEqual(gap1, gap2, accuracy: 0.01, "水平均匀分布：两个间隙相等")
        XCTAssertEqual(sorted[0].x, 0, "首尾不动")
    }

    func testHitPriorityAndSelection() {
        var doc = FCDocument()
        var node = FCNode(kind: .rect, origin: CGPoint(x: 0, y: 0))
        node.id = "n"
        var text = FCTextItem(origin: CGPoint(x: 10, y: 10), text: "浮在上面")
        text.id = "t"
        doc.nodes = [node]
        doc.texts = [text]
        XCTAssertEqual(doc.hit(CGPoint(x: 20, y: 20)), "t", "文本框在图形上面")
        XCTAssertEqual(doc.hit(CGPoint(x: 100, y: 50)), "n")
        XCTAssertNil(doc.hit(CGPoint(x: 500, y: 500)))
        XCTAssertEqual(doc.ids(in: CGRect(x: -10, y: -10, width: 100, height: 100)), ["n", "t"])
    }

    func testLayerOrder() {
        var doc = FCDocument()
        var a = FCNode(kind: .rect, origin: .zero)
        var b = FCNode(kind: .rect, origin: CGPoint(x: 20, y: 20))
        a.id = "a"; b.id = "b"
        doc.nodes = [a, b]
        doc.sendToBack(["b"])
        XCTAssertEqual(doc.nodes.first?.id, "b")
        doc.bringToFront(["b"])
        XCTAssertEqual(doc.nodes.last?.id, "b")
    }

    /// 层级操作对文本框 / 分组同样生效（以前只动 nodes，选中文本点「置顶」没反应）
    func testLayerOrderCoversTextsAndGroups() {
        var doc = FCDocument()
        var t1 = FCTextItem(origin: .zero); t1.id = "t1"
        var t2 = FCTextItem(origin: .zero); t2.id = "t2"
        var g1 = FCGroup(origin: .zero); g1.id = "g1"
        var g2 = FCGroup(origin: .zero); g2.id = "g2"
        doc.texts = [t1, t2]
        doc.groups = [g1, g2]
        doc.bringToFront(["t1", "g1"])
        XCTAssertEqual(doc.texts.map(\.id), ["t2", "t1"])
        XCTAssertEqual(doc.groups.map(\.id), ["g2", "g1"])
        doc.sendToBack(["t1", "g1"])
        XCTAssertEqual(doc.texts.map(\.id), ["t1", "t2"])
        XCTAssertEqual(doc.groups.map(\.id), ["g1", "g2"])
    }

    // MARK: 文字与颜色

    func testTextWrappingKeepsContent() {
        let font = NSFont.systemFont(ofSize: 13)
        let lines = FCTextLayout.lines("这是一段需要在窄框里自动换行的中文说明文字", width: 60, font: font)
        XCTAssertGreaterThan(lines.count, 1, "窄框里应该换行")
        XCTAssertEqual(lines.joined(), "这是一段需要在窄框里自动换行的中文说明文字")
        XCTAssertTrue(lines.allSatisfy { FCTextLayout.measure($0, font: font) <= 62 },
                      "每行都不该超出给定宽度")
        XCTAssertEqual(FCTextLayout.lines("第一行\n第二行", width: 200, font: font).count, 2,
                       "手工换行要保留")
    }

    func testHexColorRoundTrip() {
        let color = NSColor(srgbRed: 0.2, green: 0.6, blue: 0.9, alpha: 1)
        let hex = color.hexString
        XCTAssertNotNil(NSColor.fcHex(hex))
        XCTAssertEqual(NSColor.fcHex(hex)?.hexString, hex)
        XCTAssertNil(NSColor.fcHex(nil))
        XCTAssertNil(NSColor.fcHex(""))
    }

    func testStylePatchKeepsTypedValues() {
        var style = FCStyle.default
        XCTAssertEqual(style.fontSize, 13)
        XCTAssertEqual(style.align, .center)
        style.fill = "#123456"
        style.strokeWidth = 3
        XCTAssertEqual(style.fill, "#123456")
        XCTAssertEqual(style.strokeWidth, 3)
    }

    // MARK: 渲染冒烟（导出 PNG 走的就是这条链路）

    @MainActor
    func testExportRenderProducesVisiblePixels() throws {
        let doc = FlowchartTests.sampleDocument()
        let content = FlowchartExportCanvas(doc: doc,
                                            theme: FlowchartTheme.current,
                                            background: NSColor.white,
                                            padding: 24)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage, "ImageRenderer 应该出图")
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 3000, "导出的 PNG 不该是空图")
        // 抽样：画面里必须有非背景色的像素（画出东西了）
        var colored = 0
        let w = rep.pixelsWide, h = rep.pixelsHigh
        for x in stride(from: 0, to: w, by: max(1, w / 60)) {
            for y in stride(from: 0, to: h, by: max(1, h / 60)) {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                if c.brightnessComponent < 0.9 { colored += 1 }
            }
        }
        XCTAssertGreaterThan(colored, 4, "画布上应该有图形/连线/文字")
        XCTAssertGreaterThan(rep.pixelsWide, 400, "宽度按内容撑开")
        try? png.write(to: URL(fileURLWithPath: "/tmp/marknote-flowchart-preview.png"))
    }

    /// 100% 缩放必须把内容摆到画布正中（曾经少算半宽/半高，内容偏右下）
    @MainActor
    func testResetZoomCentersContent() {
        var doc = FCDocument()
        var n = FCNode(kind: .rect, origin: CGPoint(x: 120, y: 80))
        n.w = 240; n.h = 120
        doc.nodes = [n]
        let editor = FlowchartEditor(doc: doc, url: URL(fileURLWithPath: "/tmp/zoom.json"))
        let size = CGSize(width: 800, height: 600)
        editor.canvasSize = size
        editor.zoom = 2.2          // 先弄乱，确认 resetZoom 会重置
        editor.resetZoom()
        XCTAssertEqual(editor.zoom, 1, accuracy: 0.001)
        let t = FCViewTransform(zoom: editor.zoom, offset: editor.offset)
        let onScreen = t.r(doc.contentBounds)
        XCTAssertEqual(onScreen.midX, size.width / 2, accuracy: 1, "内容应水平居中")
        XCTAssertEqual(onScreen.midY, size.height / 2, accuracy: 1, "内容应垂直居中")
    }

    /// 适应窗口同样要居中（顺带防回归）
    @MainActor
    func testFitCentersContent() {
        var doc = FCDocument()
        var n = FCNode(kind: .rect, origin: CGPoint(x: 500, y: 400))
        n.w = 200; n.h = 100
        doc.nodes = [n]
        let editor = FlowchartEditor(doc: doc, url: URL(fileURLWithPath: "/tmp/fit.json"))
        let size = CGSize(width: 900, height: 500)
        editor.canvasSize = size
        editor.fit(in: size)
        let t = FCViewTransform(zoom: editor.zoom, offset: editor.offset)
        let onScreen = t.r(doc.contentBounds)
        XCTAssertEqual(onScreen.midX, size.width / 2, accuracy: 1, "内容应水平居中")
        XCTAssertEqual(onScreen.midY, size.height / 2, accuracy: 1, "内容应垂直居中")
        XCTAssertLessThanOrEqual(onScreen.width, size.width + 0.5, "内容应放进窗口")
        XCTAssertLessThanOrEqual(onScreen.height, size.height + 0.5, "内容应放进窗口")
    }

    // MARK: 全局样式（一套样式管全图，不再逐元素选填充）

    private func plainTheme(accent: NSColor = .systemTeal) -> FlowchartTheme {
        FlowchartTheme(background: .white, surface: .white, text: .black, secondary: .gray,
                       border: .lightGray, accent: accent, palette: [accent],
                       uiFont: nil, displayFont: nil, motionMs: 0)
    }

    func testGlobalStylePresetsResolve() {
        let theme = plainTheme()
        let soft = FCGlobalStyle().resolved(theme: theme)
        XCTAssertNotNil(soft.fill, "柔和预设要有淡底")
        XCTAssertEqual(soft.stroke, theme.accent)

        var outline = FCGlobalStyle(); outline.preset = .outline
        XCTAssertEqual(outline.resolved(theme: theme).fill, theme.surface, "线框是纸底")

        var flat = FCGlobalStyle(); flat.preset = .flat
        let flatResolved = flat.resolved(theme: theme)
        XCTAssertEqual(flatResolved.fill, theme.accent, "实心 = 强调色填充")
        XCTAssertEqual(flatResolved.text, theme.background, "实心上的文字要反白")

        var plain = FCGlobalStyle(); plain.preset = .plain
        XCTAssertNil(plain.resolved(theme: theme).fill, "极简不填充")
    }

    func testGlobalStyleOverridesApplyEverywhere() {
        let theme = plainTheme()
        var style = FCGlobalStyle()
        style.accent = "#123456"
        style.lineWidth = 3.4
        style.corner = 18
        style.fontSize = 17
        style.dashed = true
        let rs = style.resolved(theme: theme)
        XCTAssertEqual(rs.stroke.hexString, "#123456", "自定义强调色应覆盖主题")
        XCTAssertEqual(rs.lineWidth, 3.4, accuracy: 0.001)
        XCTAssertEqual(rs.corner, 18, accuracy: 0.001)
        XCTAssertEqual(rs.fontSize, 17, accuracy: 0.001)
        XCTAssertTrue(rs.dashed)
    }

    /// 全局样式写进 JSON 能读回来（老文档没有 style 字段时回落默认值）
    func testGlobalStyleRoundTripAndLegacyDefault() throws {
        var doc = FCDocument()
        doc.style.preset = .flat
        doc.style.accent = "#ABCDEF"
        doc.style.dashed = true
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(doc)
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try dec.decode(FCDocument.self, from: data).style, doc.style)

        // 老存档：没有 style 字段
        let legacy = #"{"version":1,"name":"旧图","nodes":[],"edges":[],"texts":[],"groups":[]}"#
        let old = try dec.decode(FCDocument.self, from: Data(legacy.utf8))
        XCTAssertEqual(old.style.preset, .soft, "老文档回落柔和预设")
        XCTAssertNil(old.style.accent)
    }

    /// 形状库三个框：开始（大众认同的胶囊）/ 执行 / 判断；新建的框不带默认文字。
    /// 「结束」不再单独给形状（用开始框写「结束」即可）。
    func testBoxToolsSemantics() {
        XCTAssertEqual(FCTool.start.shape, .capsule)
        XCTAssertEqual(FCTool.rect.shape, .rect)
        XCTAssertEqual(FCTool.diamond.shape, .diamond)
        XCTAssertEqual(FCTool.rect.label, "执行")
        XCTAssertEqual(FCTool.diamond.label, "判断")
        XCTAssertEqual(FCTool.start.label, "开始")
        // 新建图形不带默认文字
        XCTAssertEqual(FCNode(kind: FCTool.start.shape ?? .capsule, origin: .zero).text, "")
        // 形状库不再有「结束」工具（保留的语义化工具只有 开始）
        XCTAssertFalse(FCTool.allCases.contains { $0.label == "结束" })
    }

    /// 剪切板片段：跨图粘贴要换新 id、重映射连线两端、不粘出悬空边
    func testPasteboardPayloadFreshCopy() {
        var doc = FCDocument()
        var a = FCNode(kind: .capsule, origin: CGPoint(x: 10, y: 20))
        var b = FCNode(kind: .rect, origin: CGPoint(x: 200, y: 20))
        var c = FCNode(kind: .rect, origin: CGPoint(x: 600, y: 20))
        a.id = "a"; b.id = "b"; c.id = "c"
        doc.nodes = [a, b, c]
        doc.edges = [FCEdge(fromNode: "a", toNode: "b"),
                     FCEdge(fromNode: "a", toNode: "c")]
        let payload = FCPasteboardPayload(doc: doc, ids: ["a", "b"])
        XCTAssertEqual(payload.nodes.count, 2)
        XCTAssertEqual(payload.edges.count, 1, "只复制两端都在选区里的连线")
        let fresh = payload.freshCopy(dx: 30, dy: 40)
        XCTAssertEqual(fresh.nodes.count, 2)
        XCTAssertEqual(fresh.edges.count, 1)
        XCTAssertTrue(Set(fresh.nodes.map(\.id)).isDisjoint(with: Set(["a", "b"])), "id 必须换新")
        let newIDs = Set(fresh.nodes.map(\.id))
        XCTAssertTrue(newIDs.contains(fresh.edges[0].fromNode))
        XCTAssertTrue(newIDs.contains(fresh.edges[0].toNode))
        XCTAssertEqual(fresh.bounds.minX, payload.bounds.minX + 30, accuracy: 0.001)
        XCTAssertEqual(fresh.bounds.minY, payload.bounds.minY + 40, accuracy: 0.001)
    }

    // MARK: 右键菜单

    // MARK: 循环（自环）/ 平行边 / 交叉跳线

    /// 拉线中的点击判定：双击空白取消、单击空白继续、点图形收尾（选择/连线工具都走这套）
    func testDrawGateActions() {
        let t0 = Date()
        // 没在拉线 → 交给常规逻辑（双击空白才会建框）
        XCTAssertEqual(FCDrawGate.action(drawing: false, moved: false, onNode: false,
                                         lastBlankClick: t0, now: t0.addingTimeInterval(0.1)), .idle)
        // 拉线中点图形 → 收尾
        XCTAssertEqual(FCDrawGate.action(drawing: true, moved: false, onNode: true,
                                         lastBlankClick: .distantPast, now: t0), .finish)
        // 拉线中第一次点空白 → 继续（不取消）
        XCTAssertEqual(FCDrawGate.action(drawing: true, moved: false, onNode: false,
                                         lastBlankClick: .distantPast, now: t0), .keep)
        // 拉线中 0.45 秒内第二次点空白 → 取消
        XCTAssertEqual(FCDrawGate.action(drawing: true, moved: false, onNode: false,
                                         lastBlankClick: t0, now: t0.addingTimeInterval(0.2)), .cancel)
        // 超过窗口的第二次点空白 → 又算新的一次单击（继续）
        XCTAssertEqual(FCDrawGate.action(drawing: true, moved: false, onNode: false,
                                         lastBlankClick: t0, now: t0.addingTimeInterval(0.8)), .keep)
        // 有位移（拖拽过程）不走这套
        XCTAssertEqual(FCDrawGate.action(drawing: true, moved: true, onNode: false,
                                         lastBlankClick: t0, now: t0.addingTimeInterval(0.1)), .idle)
    }

    /// 落点接边：鼠标丢在哪条边就接哪条边（不能用中点距离判断，否则会"掉到下面去"）
    func testNearestAnchorFollowsDropPosition() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        // 丢在右边（哪怕靠下）→ 接右边
        XCTAssertEqual(FCEdgePath.nearestAnchor(to: CGPoint(x: 205, y: 92), in: rect), .right)
        XCTAssertEqual(FCEdgePath.nearestAnchor(to: CGPoint(x: 198, y: 60), in: rect), .right)
        // 丢在下边靠左 → 接下边（旧的中点比较会误判成左边）
        XCTAssertEqual(FCEdgePath.nearestAnchor(to: CGPoint(x: 20, y: 95), in: rect), .bottom)
        XCTAssertEqual(FCEdgePath.nearestAnchor(to: CGPoint(x: 100, y: 103), in: rect), .bottom)
        // 上边 / 左边
        XCTAssertEqual(FCEdgePath.nearestAnchor(to: CGPoint(x: 150, y: -4), in: rect), .top)
        XCTAssertEqual(FCEdgePath.nearestAnchor(to: CGPoint(x: -6, y: 80), in: rect), .left)
    }

    /// 手动断点（拉线时右键落的拐点）：线必须依次经过，且全程正交
    func testWaypointsAreRespected() throws {
        var doc = FCDocument()
        var a = FCNode(kind: .rect, origin: CGPoint(x: 0, y: 0)); a.w = 100; a.h = 50
        var b = FCNode(kind: .rect, origin: CGPoint(x: 400, y: 300)); b.w = 100; b.h = 50
        a.id = "a"; b.id = "b"
        doc.nodes = [a, b]
        var e = FCEdge(fromNode: "a", toNode: "b")
        e.waypoints = [CGPoint(x: 60, y: 200), CGPoint(x: 300, y: 200)]
        doc.edges = [e]
        let path = try XCTUnwrap(doc.edgePath(e))
        let pts = path.polyline
        // 断点必须落在路径上（共线时会被合并成一段，所以按「到线的距离」判定）
        for w in e.waypoints {
            XCTAssertLessThanOrEqual(path.distance(to: w), 0.6, "路径没经过断点 \(w)：\(pts)")
        }
        for i in 1..<pts.count {
            let dx = abs(pts[i].x - pts[i - 1].x), dy = abs(pts[i].y - pts[i - 1].y)
            XCTAssertTrue(dx < 0.6 || dy < 0.6, "带断点的线出现斜段：\(pts)")
        }
        // JSON 往返保留断点
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(FCDocument.self, from: try enc.encode(doc))
        XCTAssertEqual(back.edges.first?.waypoints, e.waypoints)
    }

    /// 断点折线：斜的两站之间自动插拐点（先沿上一段方向走）
    func testWaypointOrthogonalization() {
        let pts = FCEdgePath.throughWaypoints(p0: CGPoint(x: 0, y: 0),
                                              p1: CGPoint(x: 100, y: 100),
                                              waypoints: [CGPoint(x: 0, y: 40), CGPoint(x: 100, y: 40)])
        for i in 1..<pts.count {
            let dx = abs(pts[i].x - pts[i - 1].x), dy = abs(pts[i].y - pts[i - 1].y)
            XCTAssertTrue(dx < 0.6 || dy < 0.6, "出现斜段：\(pts)")
        }
        XCTAssertEqual(pts.first, CGPoint(x: 0, y: 0))
        XCTAssertEqual(pts.last, CGPoint(x: 100, y: 100))
    }

    /// 自环自动挑「最空」的两条边：判断框右边已有「否」分支、上边已有入线时，
    /// 自环应该走左边/下边，而不是继续挤在右边
    func testSelfLoopAvoidsBusySides() {
        var doc = FCDocument()
        var input = FCNode(kind: .rect, origin: CGPoint(x: 100, y: 0), text: "输入")
        var decide = FCNode(kind: .diamond, origin: CGPoint(x: 100, y: 200), text: "判断")
        var fail = FCNode(kind: .rect, origin: CGPoint(x: 400, y: 210), text: "失败")
        input.id = "in"; decide.id = "d"; fail.id = "f"
        doc.nodes = [input, decide, fail]
        var e1 = FCEdge(fromNode: "in", toNode: "d")
        e1.fromAnchor = .bottom; e1.toAnchor = .top        // 上边被入线占用
        var e2 = FCEdge(fromNode: "d", toNode: "f", label: "否")
        e2.fromAnchor = .right; e2.toAnchor = .left        // 右边被分支占用
        let loop = FCEdge(fromNode: "d", toNode: "d")
        doc.edges = [e1, e2, loop]
        let sides = doc.selfLoopSides(for: loop)
        let chosen: Set<FCAnchor> = [sides.from, sides.to]
        XCTAssertEqual(chosen, [.left, .bottom], "自环该走左边+下边（最空的一对），实际：\(sides)")
        // 显式指定过就尊重用户
        var custom = loop
        custom.fromAnchor = .top
        custom.toAnchor = .top
        let customSides = doc.selfLoopSides(for: custom)
        XCTAssertEqual(customSides.from, .top)
        XCTAssertNotEqual(customSides.to, .top, "同一条边出又回会叠线，要换相邻边")
    }

    /// 自环（A → A）：要绕出去再折回来，全程正交、不缩成一点，且包住图形外圈
    func testSelfLoopRoutesAroundNode() throws {
        var doc = FCDocument()
        var n = FCNode(kind: .rect, origin: CGPoint(x: 100, y: 100))
        n.w = 120; n.h = 60
        n.id = "n"
        doc.nodes = [n]
        doc.edges = [FCEdge(fromNode: "n", toNode: "n")]
        let path = try XCTUnwrap(doc.edgePath(doc.edges[0]), "自环也要能算出路径")
        let pts = path.polyline
        XCTAssertGreaterThanOrEqual(pts.count, 4, "自环至少要有出/绕/回几段")
        XCTAssertGreaterThan(path.polylineLength, 120, "自环不能缩成一个点")
        for i in 1..<pts.count {
            let dx = abs(pts[i].x - pts[i - 1].x), dy = abs(pts[i].y - pts[i - 1].y)
            XCTAssertTrue(dx < 0.6 || dy < 0.6, "自环必须正交：\(pts)")
        }
        // 起点在图形边缘、终点也在边缘，且拐弯探出图形之外
        XCTAssertTrue(n.rect.insetBy(dx: -0.6, dy: -0.6).contains(pts[0]))
        XCTAssertTrue(n.rect.insetBy(dx: -0.6, dy: -0.6).contains(pts[pts.count - 1]))
        let outside = pts.contains { !n.rect.insetBy(dx: -4, dy: -4).contains($0) }
        XCTAssertTrue(outside, "自环要绕到图形外面：\(pts)")
    }

    /// A→B 与 B→A 是两条线，不能重叠成一条最短路径：车道错开，中段不重合
    func testParallelEdgesGetSeparateLanes() throws {
        var doc = FCDocument()
        var a = FCNode(kind: .capsule, origin: CGPoint(x: 0, y: 0)); a.w = 100; a.h = 50
        var b = FCNode(kind: .rect, origin: CGPoint(x: 400, y: 0)); b.w = 100; b.h = 50
        a.id = "a"; b.id = "b"
        doc.nodes = [a, b]
        let e1 = FCEdge(fromNode: "a", toNode: "b")
        let e2 = FCEdge(fromNode: "b", toNode: "a")
        doc.edges = [e1, e2]
        let offs = doc.anchorOffsets()
        XCTAssertNotEqual(offs[doc.endpointKey(e1.id, isFrom: true)] ?? 0,
                          offs[doc.endpointKey(e2.id, isFrom: true)] ?? 0,
                          "同一条边上挂两条线，锚点必须错开")
        let path1 = try XCTUnwrap(doc.edgePath(e1))
        let path2 = try XCTUnwrap(doc.edgePath(e2))
        // 两条线必须真正分开：锚点沿边缘错开，互相最近距离要有可见间隔
        let gap = (path1.polyline.map { path2.distance(to: $0) }
                   + path2.polyline.map { path1.distance(to: $0) }).min() ?? 0
        XCTAssertGreaterThan(gap, 8, "两条反向连线叠在一起了（最小间距 \(gap)）")
    }

    /// 交叉检测：横线穿竖线要给「跳线」位置
    func testCrossingsDetectPerpendicularIntersection() {
        let horizontal = [CGPoint(x: 0, y: 50), CGPoint(x: 200, y: 50)]
        let vertical = [CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)]
        let c = FCRenderer.crossings(horizontal, vertical)
        XCTAssertEqual(c.count, 1)
        XCTAssertEqual(c.first?.x ?? 0, 100, accuracy: 0.01)
        XCTAssertEqual(c.first?.y ?? 0, 50, accuracy: 0.01)
        // 端点相交不算交叉（避免线头出现跳线）
        let touchAtEnd = [CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 50)]
        XCTAssertTrue(FCRenderer.crossings(horizontal, touchAtEnd).isEmpty)
    }

    private func itemTitles(_ entries: [FCMenuEntry]) -> [String] {
        entries.compactMap { entry in
            switch entry {
            case .item(let title, _, _): return title
            case .submenu(let title, _): return title
            case .separator: return nil
            }
        }
    }

    private func submenu(_ entries: [FCMenuEntry], _ title: String) -> [FCMenuEntry] {
        for entry in entries {
            if case .submenu(let t, let children) = entry, t == title { return children }
        }
        return []
    }

    @MainActor
    func testContextMenuPerHitType() {
        let doc = FlowchartTests.sampleDocument()
        // 图形
        let onNode = FCContextMenu.entries(doc: doc, selection: [], hitID: doc.nodes[0].id, at: .zero)
        let nodeTitles = itemTitles(onNode)
        XCTAssertTrue(nodeTitles.contains("编辑文字"))
        XCTAssertTrue(nodeTitles.contains("复制"))
        XCTAssertTrue(nodeTitles.contains("置顶"))
        XCTAssertTrue(nodeTitles.contains("从这里连线"))
        XCTAssertTrue(nodeTitles.contains("删除"))
        XCTAssertTrue(onNode.contains(.separator))

        // 连线：标签 + 走法 / 箭头子菜单，且当前值打勾
        let edge = doc.edges[0]
        let onEdge = FCContextMenu.entries(doc: doc, selection: [], hitID: edge.id, at: .zero)
        XCTAssertTrue(itemTitles(onEdge).contains("编辑标签"))
        XCTAssertTrue(itemTitles(onEdge).contains("删除连线"))
        let routes = submenu(onEdge, "线的走法")
        XCTAssertEqual(routes.count, FCRoute.allCases.count)
        XCTAssertTrue(routes.contains(.item(title: edge.route.label, checked: true, action: .route(edge.route))))
        let arrows = submenu(onEdge, "箭头")
        XCTAssertEqual(arrows.count, FCArrow.allCases.count)

        // 空白：新建 / 粘贴 / 网格 / 全选 / 适应窗口
        let onBlank = FCContextMenu.entries(doc: doc, selection: [], hitID: nil, at: .zero)
        let blankTitles = itemTitles(onBlank)
        XCTAssertTrue(blankTitles.contains("新建执行框"))
        XCTAssertTrue(blankTitles.contains("粘贴到此处"))
        XCTAssertTrue(blankTitles.contains("隐藏网格"), "网格开着时应给「隐藏网格」")
        XCTAssertTrue(blankTitles.contains("全选"))
        XCTAssertTrue(blankTitles.contains("适应窗口"))
        XCTAssertFalse(blankTitles.contains("删除"))

        // 网格关掉后，空白菜单给「显示网格」
        var hidden = doc
        hidden.showGrid = false
        XCTAssertTrue(itemTitles(FCContextMenu.entries(doc: hidden, selection: [], hitID: nil, at: .zero))
            .contains("显示网格"))
    }

    /// 右键坐标换算：窗口坐标（左下原点）→ 画布内坐标（左上原点）
    func testContextMenuCoordinateConversion() {
        let frame = CGRect(x: 152, y: 100, width: 600, height: 400)   // 窗口坐标
        // 画布左上角（窗口坐标：x=152, y=500）→ 画布内 (0,0)
        XCTAssertEqual(FCContextGeometry.canvasPoint(windowPoint: CGPoint(x: 152, y: 500),
                                                     canvasFrameInWindow: frame),
                       CGPoint(x: 0, y: 0))
        // 画布内 (48, 50) → 窗口坐标 (200, 450)
        XCTAssertEqual(FCContextGeometry.canvasPoint(windowPoint: CGPoint(x: 200, y: 450),
                                                     canvasFrameInWindow: frame),
                       CGPoint(x: 48, y: 50))
        // 没有画布尺寸信息时原样返回（不崩）
        XCTAssertEqual(FCContextGeometry.canvasPoint(windowPoint: CGPoint(x: 5, y: 6),
                                                     canvasFrameInWindow: nil),
                       CGPoint(x: 5, y: 6))
    }

    /// 整屏（工具栏 + 画布 + 检查器）渲染：用来肉眼检查界面，也防止布局整体崩掉
    @MainActor
    func testEditorChromeRenders() throws {
        let (store, root) = try TestEnv.makeStore()
        let doc = FlowchartTests.sampleDocument()
        let url = FlowchartStore.url(root: root, name: doc.name)
        FlowchartStore.save(doc, url: url)
        let editor = FlowchartEditor(doc: doc, url: url)
        let size = CGSize(width: 1012, height: 620)
        editor.canvasSize = size
        editor.fit(in: size)
        editor.selection = [doc.nodes[2].id]   // 选中「已登录？」：右侧检查器出现
        let view = FlowchartEditorHost(editor: editor,
                                       theme: FlowchartTheme.current,
                                       docs: FlowchartStore.list(root: root),
                                       root: root,
                                      onOpen: { _ in }, onNew: {},
                                      onRename: {}, onDelete: {})
            .environment(store)
            .frame(width: 1012, height: 620)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.4
        let image = try XCTUnwrap(renderer.nsImage, "整屏应该能出图")
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 5000, "工具栏 / 画布 / 检查器都该画出来")
        try? png.write(to: URL(fileURLWithPath: "/tmp/marknote-flowchart-ui.png"))
    }

    /// 覆盖全部图形 + 三种路由 + 标签 + 分组 + 独立文本框的示例
    static func sampleDocument() -> FCDocument {
        var doc = FCDocument(name: "示例")
        var start = FCNode(kind: .capsule, origin: CGPoint(x: 60, y: 40), text: "开始")
        var login = FCNode(kind: .roundedRect, origin: CGPoint(x: 60, y: 150), text: "打开登录页")
        var judge = FCNode(kind: .diamond, origin: CGPoint(x: 50, y: 270), text: "已登录？")
        var pwd = FCNode(kind: .parallelogram, origin: CGPoint(x: 300, y: 280), text: "输入密码")
        var fail = FCNode(kind: .rect, origin: CGPoint(x: 300, y: 400), text: "提示错误")
        var db = FCNode(kind: .cylinder, origin: CGPoint(x: 540, y: 280), text: "账号库")
        var ok = FCNode(kind: .ellipse, origin: CGPoint(x: 60, y: 400), text: "进入首页")
        var note = FCNode(kind: .note, origin: CGPoint(x: 540, y: 400), text: "验证码走短信")
        start.id = "s"; login.id = "l"; judge.id = "j"; pwd.id = "p"
        fail.id = "f"; db.id = "db"; ok.id = "ok"; note.id = "n"
        doc.nodes = [start, login, judge, pwd, fail, db, ok, note]
        var g = FCGroup(origin: CGPoint(x: 20, y: 240), title: "认证流程")
        g.w = 620
        g.h = 200
        doc.groups = [g]
        var e1 = FCEdge(fromNode: "s", toNode: "l")
        var e2 = FCEdge(fromNode: "l", toNode: "j")
        var e3 = FCEdge(fromNode: "j", toNode: "p", label: "否")
        var e4 = FCEdge(fromNode: "j", toNode: "ok", label: "是")
        var e5 = FCEdge(fromNode: "p", toNode: "db")
        e5.route = .curve
        var e6 = FCEdge(fromNode: "p", toNode: "f", label: "错了")
        e6.route = .straight
        e1.route = .orthogonal
        e2.route = .orthogonal
        e3.route = .orthogonal
        e4.route = .straight
        doc.edges = [e1, e2, e3, e4, e5, e6]
        doc.texts = [FCTextItem(origin: CGPoint(x: 60, y: 500), text: "登录流程图 · 示例")]
        return doc
    }
}

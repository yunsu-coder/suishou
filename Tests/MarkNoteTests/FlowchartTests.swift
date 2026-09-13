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
                                       onOpen: { _ in }, onNew: {}, onRename: {}, onDelete: {})
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

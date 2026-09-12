import XCTest
@testable import MarkNote

/// 视图插件（声明式）：解码、注册、隔离门槛。
final class ViewPluginTests: XCTestCase {

    @MainActor
    private func makePackage(_ viewsJSON: String, manifestID: String = "view-test") throws -> (PluginManager, URL) {
        let (_, temp) = try TestEnv.makeStore()
        let dir = temp.appendingPathComponent(".plugins/\(manifestID)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try """
        { "id": "\(manifestID)", "name": "测试视图", "version": "1.0.0", "kind": "views", "main": "views.json" }
        """.write(to: dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try viewsJSON.write(to: dir.appendingPathComponent("views.json"), atomically: true, encoding: .utf8)
        UserDefaults.standard.set(true, forKey: "pluginEnabled.\(manifestID)")
        let pm = PluginManager.shared
        pm.scan(workspaceDir: temp)
        return (pm, temp)
    }

    /// 合法的卡片墙声明：注册成功，且带出 scope / placement / options。
    @MainActor
    func testNoteCardsViewRegisters() throws {
        let (pm, id) = try makePackage("""
        [ { "id": "cards", "name": "卡片墙", "type": "noteCards", "scope": "workspace",
            "placement": "main", "options": { "previewLines": 6, "actions": ["open","star"] } } ]
        """)
        defer {
            UserDefaults.standard.removeObject(forKey: "pluginEnabled.view-test")
            _ = id
        }
        let views = pm.allViews().filter { $0.type == .noteCards }
        XCTAssertEqual(views.count, 1, "卡片墙应注册为一个视图")
        let v = try XCTUnwrap(views.first)
        XCTAssertEqual(v.scope, .workspace)
        XCTAssertEqual(v.placement, .main)
        XCTAssertEqual(v.previewLines, 6)
        XCTAssertTrue(pm.viewIssues(for: "view-test").isEmpty)
        XCTAssertNotNil(pm.mainAreaView(type: .noteCards), "主区域视图应可被查询到")
    }

    /// 隔离门槛：读笔记内容的卡片墙声明成 global 必须被拦截（不进列表）。
    @MainActor
    func testNoteCardsRejectsGlobalScope() throws {
        let (pm, _) = try makePackage("""
        [ { "id": "cards", "name": "越权卡片墙", "type": "noteCards", "scope": "global", "placement": "main" } ]
        """, manifestID: "view-bad-scope")
        defer { UserDefaults.standard.removeObject(forKey: "pluginEnabled.view-bad-scope") }
        XCTAssertTrue(pm.allViews().filter { $0.name == "越权卡片墙" }.isEmpty)
        XCTAssertTrue(pm.viewIssues(for: "view-bad-scope").contains { $0.contains("workspace") },
                      "应给出「必须 workspace」的原因")
    }

    /// 未知视图类型 / 未知 placement 一律拒绝（插件不能自定义渲染器）。
    @MainActor
    func testUnknownTypeAndPlacementRejected() throws {
        let (pm, _) = try makePackage("""
        [ { "id": "a", "name": "未知类型", "type": "customHTML", "scope": "workspace", "placement": "main" },
          { "id": "b", "name": "未知位置", "type": "assetGrid", "scope": "workspace", "placement": "floating" } ]
        """, manifestID: "view-bad-type")
        defer { UserDefaults.standard.removeObject(forKey: "pluginEnabled.view-bad-type") }
        XCTAssertTrue(pm.allViews().filter { $0.dir.contains("view-bad-type") }.isEmpty)
        let issues = pm.viewIssues(for: "view-bad-type")
        XCTAssertTrue(issues.contains { $0.contains("未知视图类型") })
        XCTAssertTrue(issues.contains { $0.contains("placement") })
    }

    /// 卡片墙只收笔记：素材文件（png/pdf/zip…）不进卡片；预览去掉 Markdown 标记。
    @MainActor
    func testCardsOnlyIncludeNotesAndPlainPreview() {
        XCTAssertTrue(NoteCardsView.isNoteFile("随手.md"))
        XCTAssertTrue(NoteCardsView.isNoteFile("source/周记.txt"))
        XCTAssertTrue(NoteCardsView.isNoteFile("无扩展名笔记"))
        XCTAssertFalse(NoteCardsView.isNoteFile("source/image/img-1.png"))
        XCTAssertFalse(NoteCardsView.isNoteFile("source/pdf/文档.pdf"))
        XCTAssertFalse(NoteCardsView.isNoteFile("source/mp4/录屏.mp4"))

        XCTAssertEqual(NoteCardsView.folderLabel("source/image"), "image")
        XCTAssertEqual(NoteCardsView.folderLabel(""), "根目录")

        XCTAssertEqual(NoteCardsView.plainText("**粗体**与`代码`"), "粗体与代码")
        XCTAssertEqual(NoteCardsView.plainText("- [ ] 待办事项"), "待办事项")
        XCTAssertEqual(NoteCardsView.plainText("==高光==文本"), "高光文本")
    }

    /// 素材网格：注册为 panel 视图；同样受「必须 workspace」的隔离门槛约束。
    @MainActor
    func testAssetGridRegistersAndRejectsGlobal() throws {
        let (pm, _) = try makePackage("""
        [ { "id": "assets", "name": "素材网格", "type": "assetGrid", "scope": "workspace",
            "placement": "panel", "options": { "dirs": ["source"], "showRefCount": true } } ]
        """, manifestID: "view-asset-ok")
        defer { UserDefaults.standard.removeObject(forKey: "pluginEnabled.view-asset-ok") }
        let assets = pm.allViews().filter { $0.type == .assetGrid }
        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(assets.first?.placement, .panel)
        XCTAssertEqual(assets.first?.options.dirs, ["source"])

        let (pm2, _) = try makePackage("""
        [ { "id": "assets", "name": "越权素材", "type": "assetGrid", "scope": "global", "placement": "panel" } ]
        """, manifestID: "view-asset-bad")
        defer { UserDefaults.standard.removeObject(forKey: "pluginEnabled.view-asset-bad") }
        XCTAssertTrue(pm2.allViews().filter { $0.name == "越权素材" }.isEmpty)
        XCTAssertTrue(pm2.viewIssues(for: "view-asset-bad").contains { $0.contains("workspace") })
    }

    /// 素材面板的小工具函数：标题去扩展名、大小格式化、类型图标。
    func testAssetHelpers() {
        XCTAssertEqual(AssetGridView.title("09-11-手绘线稿.png"), "09-11-手绘线稿")
        XCTAssertEqual(AssetGridView.sizeLabel(2048), "2 KB")
        XCTAssertEqual(AssetGridView.sizeLabel(3 * 1024 * 1024), "3.0 MB")
        XCTAssertEqual(AssetGridView.symbol(for: "pdf"), "doc.richtext")
        XCTAssertEqual(AssetGridView.symbol(for: "mp4"), "film")
        XCTAssertEqual(AssetGridView.symbol(for: "zip"), "archivebox")
    }

    /// 插入 / 复制 / 拖拽三处共用同一套引用写法（拖进编辑器后长得和手动插入完全一致）。
    func testAssetMarkdownRefIsSharedByInsertCopyAndDrag() {
        XCTAssertEqual(AssetGridView.markdownRef(name: "09-11-手绘线稿.png", path: "img/09-11-手绘线稿.png"),
                       "![09-11-手绘线稿](img/09-11-手绘线稿.png)")
        XCTAssertEqual(AssetGridView.markdownRef(name: "字段 表.pdf", path: "pdf/字段 表.pdf"),
                       "![字段 表](pdf/字段 表.pdf)")
    }

    /// 跨工作台导入：复制进当前工作台、原库只读、同名加序号（隔离规则第 2 条）。
    @MainActor
    func testCrossWorkspaceImportCopiesAndNeverTouchesSource() throws {
        // 两个工作台：source（源）/ dest（当前）
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("mn-import-\(UUID().uuidString)")
        let srcRoot = base.appendingPathComponent("note")
        let dstRoot = base.appendingPathComponent("origin")
        defer { try? fm.removeItem(at: base) }

        let srcImg = srcRoot.appendingPathComponent("source/image")
        try fm.createDirectory(at: srcImg, withIntermediateDirectories: true)
        try "PNGDATA".write(to: srcImg.appendingPathComponent("封面.png"), atomically: true, encoding: .utf8)
        let srcPDF = srcRoot.appendingPathComponent("source/pdf")
        try fm.createDirectory(at: srcPDF, withIntermediateDirectories: true)
        try "PDF".write(to: srcPDF.appendingPathComponent("字段表.pdf"), atomically: true, encoding: .utf8)
        try fm.createDirectory(at: dstRoot, withIntermediateDirectories: true)

        // 扫描源工作台（只读）
        let found = NotesStore.scanAssets(in: srcRoot)
        XCTAssertEqual(found.count, 2, "应扫到两个素材")
        XCTAssertTrue(found.contains { $0.isImage && $0.name == "封面.png" })

        // 目标目录预置同名文件 → 导入必须加序号而不是覆盖
        let destImgDir = dstRoot.appendingPathComponent("source/image")
        try fm.createDirectory(at: destImgDir, withIntermediateDirectories: true)
        try "EXISTING".write(to: destImgDir.appendingPathComponent("封面.png"), atomically: true, encoding: .utf8)

        let previous = UserDefaults.standard.string(forKey: NotesStore.kDirKey)
        UserDefaults.standard.set(dstRoot.path, forKey: NotesStore.kDirKey)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: NotesStore.kDirKey) }
            else { UserDefaults.standard.removeObject(forKey: NotesStore.kDirKey) }
        }
        let store = NotesStore()
        let result = store.importAssets(from: found.map(\.url))
        XCTAssertEqual(result.ok, 2, "两个素材都该导入成功")
        XCTAssertEqual(result.failed, 0)

        // 目标工作台：新文件存在、且没有覆盖已有同名文件
        let destNames = try fm.contentsOfDirectory(atPath: destImgDir.path).sorted()
        XCTAssertTrue(destNames.contains("封面.png"))
        XCTAssertTrue(destNames.contains("封面 (1).png"), "同名应自动加序号，实际：\(destNames)")
        let preserved = try String(contentsOf: destImgDir.appendingPathComponent("封面.png"), encoding: .utf8)
        XCTAssertEqual(preserved, "EXISTING", "已有文件绝不能被覆盖")
        XCTAssertTrue(fm.fileExists(atPath: dstRoot.appendingPathComponent("source/pdf/字段表.pdf").path))

        // 源工作台只读：文件一个不少、内容不变
        let srcNames = try fm.contentsOfDirectory(atPath: srcImg.path).sorted()
        XCTAssertEqual(srcNames, ["封面.png"])
        XCTAssertEqual(try String(contentsOf: srcImg.appendingPathComponent("封面.png"), encoding: .utf8), "PNGDATA")
    }
}

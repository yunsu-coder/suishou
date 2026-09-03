import XCTest
import Foundation
@testable import MarkNote

final class StoreIOTests: XCTestCase {

    @MainActor
    private func currentID(_ store: NotesStore) -> String {
        store.selectedNoteID ?? ""
    }

    @MainActor
    func testDuplicateTitleRejected() throws {
        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertTrue(store.createNote(title: "A", category: ""))
        XCTAssertFalse(store.createNote(title: "A", category: ""), "同目录同名必须被拒")
        store.createCategory("folder")
        let folderID = store.categories[0].id
        XCTAssertTrue(store.createNote(title: "A", category: folderID), "不同目录同名允许")
        let bID = store.selectedNoteID ?? ""
        // 重命名冲突（同目录）
        XCTAssertFalse(store.renameNote(bID, to: "A"))
        XCTAssertTrue(store.renameNote(bID, to: "B2"))
    }

    @MainActor
    func testImportGovernance() throws {
        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("note.md")
        // BOM + YAML front matter + 首行标题 + CRLF
        let md = "\u{FEFF}---\ntitle: 我的标题\n---\n# 重复标题\n正文\r\n第二行"
        try Data(md.utf8).write(to: f)
        let id1 = try XCTUnwrap(store.importNote(from: f))
        TestEnv.pump()
        let title1 = store.index.first { $0.id == id1 }?.title
        let content1 = try String(contentsOf: store.noteURL(id1), encoding: .utf8)
        XCTAssertEqual(title1, "重复标题", "首行标题提升（覆盖 front matter）")
        XCTAssertEqual(content1, "正文\n第二行", "标题移除 + CRLF 规整 + BOM 剥离")
        // 同目录同名 → 自动加序号
        let id2 = try XCTUnwrap(store.importNote(from: f))
        TestEnv.pump()
        let title2 = store.index.first { $0.id == id2 }?.title
        XCTAssertEqual(title2, "重复标题 2")
    }

    @MainActor
    func testPhysicalDeleteSanitized() throws {
        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertTrue(store.createNote(title: "待删", category: ""))
        let id = currentID(store)
        TestEnv.pump()
        XCTAssertTrue(store.deleteNote(id))
        TestEnv.pump()
        XCTAssertFalse(store.index.contains { $0.id == id }, "删除后索引消失")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.noteURL(id).path), "文件已被物理删除（回收站机制已停用）")
        XCTAssertEqual(store.listTrash().count, 0, "回收站恒为空")
    }
}

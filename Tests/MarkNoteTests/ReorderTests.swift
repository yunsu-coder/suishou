import XCTest
@testable import MarkNote

/// 树内拖拽排序（手动顺序 + .order.json 持久化）
final class ReorderTests: XCTestCase {

    @MainActor
    func testDragReorderChangesTreeOrder() throws {
        let (store, temp) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: temp) }
        XCTAssertTrue(store.createNote(title: "a.md", category: ""))
        XCTAssertTrue(store.createNote(title: "b.md", category: ""))
        XCTAssertTrue(store.createNote(title: "c.md", category: ""))
        TestEnv.pump(0.4)

        store.reorderNotes(["c.md"], before: "a.md")

        let ids = store.treeRows(openFolders: []).compactMap { row -> String? in
            if case .note(let n, _) = row { return n.id }
            return nil
        }
        guard let ci = ids.firstIndex(of: "c.md"), let ai = ids.firstIndex(of: "a.md") else {
            return XCTFail("缺少文件：\(ids)")
        }
        XCTAssertLessThan(ci, ai, "c.md 应排在 a.md 之前：\(ids)")
        let orderURL = store.notesDir.appendingPathComponent(".order.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: orderURL.path), "应持久化 .order.json")
    }
}

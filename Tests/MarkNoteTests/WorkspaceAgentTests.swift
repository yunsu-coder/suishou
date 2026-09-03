import XCTest
import Foundation
@testable import MarkNote

final class WorkspaceAgentTests: XCTestCase {

    @MainActor
    private func makeStore() throws -> (NotesStore, URL) {
        let (store, dir) = try TestEnv.makeStore()
        return (store, dir)
    }

    @MainActor
    private func call(_ name: String, _ args: [String: Any]) -> FileTools.ParsedCall {
        let data = try! JSONSerialization.data(withJSONObject: args)
        return FileTools.ParsedCall(id: name + "-1", name: name, arguments: String(data: data, encoding: .utf8)!)
    }

    @MainActor
    func testWriteReadRoundtrip() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let agent = WorkspaceAgent(store: store)

        let w = agent.handle(call("write_file", ["path": "笔记/a.md", "content": "你好，世界", "mode": "create"]))
        guard case .result(let wr) = w else { return XCTFail("write 应为 result") }
        XCTAssertTrue(wr.contains("已写入"))

        let r = agent.handle(call("read_file", ["path": "笔记/a.md"]))
        guard case .result(let rr) = r else { return XCTFail("read 应为 result") }
        XCTAssertEqual(rr, "你好，世界")
    }

    @MainActor
    func testPathTraversalRejected() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let agent = WorkspaceAgent(store: store)
        for bad in ["../evil.md", "/tmp/evil.md", ".versions/x.md"] {
            let w = agent.handle(call("write_file", ["path": bad, "content": "x", "mode": "overwrite"]))
            guard case .result(let rr) = w else { return XCTFail("越界路径应返回 result(拒绝)") }
            XCTAssertTrue(rr.contains("越界") || rr.contains("无效"), "拒绝 \(bad): \(rr)")
        }
    }

    @MainActor
    func testDeleteConfirmThenMovesToTrash() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let agent = WorkspaceAgent(store: store)
        _ = agent.handle(call("write_file", ["path": "todelete.md", "content": "内容", "mode": "create"]))

        let d = agent.handle(call("delete_file", ["path": "todelete.md"]))
        switch d {
        case .confirm(let pending):
            let result = agent.performDelete(pending.call)
            XCTAssertTrue(result.contains(".trash"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.noteURL("todelete.md").path))
            let trash = store.notesDir.appendingPathComponent(".trash", isDirectory: true)
            XCTAssertNotNil(try FileManager.default.contentsOfDirectory(atPath: trash.path).first)
        case .result(let rr):
            XCTFail("delete 应进入确认流程：\(rr)")
        }
    }

    @MainActor
    func testWriteOpenNoteSyncsEditor() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = store.createNote(title: "同步", category: "")
        let id = store.selectedNoteID ?? ""
        TestEnv.pump()
        store.workingText = "初始"
        store.saveCurrent()
        TestEnv.pump()

        let agent = WorkspaceAgent(store: store)
        let w = agent.handle(call("write_file", ["path": id, "content": "AI 写入的内容", "mode": "overwrite"]))
        guard case .result(let wr) = w else { return XCTFail("write 应为 result") }
        XCTAssertTrue(wr.contains("已写入"))
        XCTAssertEqual(store.workingText, "AI 写入的内容", "AI 写当前打开文件 → 编辑器即时同步")
    }

    @MainActor
    func testListFilesShowsWrites() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let agent = WorkspaceAgent(store: store)
        _ = agent.handle(call("write_file", ["path": "目录/文件.md", "content": "x", "mode": "create"]))
        let l = agent.handle(call("list_files", ["path": ""]))
        guard case .result(let rr) = l else { return XCTFail("list 应为 result") }
        XCTAssertTrue(rr.contains("目录/"), "根目录应显示文件夹：\n\(rr)")
        // 单层列出：进入目录看文件
        let l2 = agent.handle(call("list_files", ["path": "目录"]))
        guard case .result(let rr2) = l2 else { return XCTFail("list2 应为 result") }
        XCTAssertTrue(rr2.contains("文件.md"), "子目录应显示文件：\n\(rr2)")
    }
}

final class FileToolsSpecTests: XCTestCase {
    func testToolSpecsComplete() {
        let names = FileTools.specs.compactMap { t -> String? in
            ((t["function"] as? [String: Any])?["name"] as? String)
        }
        XCTAssertGreaterThanOrEqual(names.count, 5, "工具数 >= 5")
        XCTAssertEqual(Set(names).count, names.count, "工具名唯一")
        XCTAssertTrue(names.contains("read_file"))
        XCTAssertTrue(names.contains("write_file"))
        XCTAssertTrue(names.contains("delete_file"))
    }
}

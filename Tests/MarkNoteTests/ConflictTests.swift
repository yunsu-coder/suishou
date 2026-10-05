import XCTest
import Foundation
@testable import MarkNote

final class ConflictTests: XCTestCase {

    /// 模拟其他端（start/另一实例/Finder）改写磁盘上的当前笔记（v2：原始 Markdown 文本）
    @MainActor
    private func injectExternal(_ store: NotesStore, id: String, text: String) {
        try? text.write(to: store.noteURL(id), atomically: true, encoding: .utf8)
    }

    @MainActor
    private func fileText(_ store: NotesStore, _ id: String) -> String? {
        try? String(contentsOf: store.noteURL(id), encoding: .utf8)
    }

    @MainActor
    private func create(_ store: NotesStore, _ title: String) -> String {
        _ = store.createNote(title: title, category: "")
        return store.selectedNoteID ?? ""
    }

    /// 自己没有任何未保存改动 → 外部改了就直接静默载入磁盘版本（VS Code 同款行为）。
    /// 旧策略会在这里弹冲突并暂停自动保存，实测把用户卡死在"改了不落盘"的状态。
    @MainActor
    func testExternalChangeAutoReloadsWhenNoLocalEdits() throws {
        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = create(store, "并发笔记.md")
        TestEnv.pump()
        XCTAssertFalse(store.dirty)

        injectExternal(store, id: id, text: "另一端的修改")
        store.reloadIndex()
        TestEnv.pump(0.5)

        XCTAssertFalse(store.externalConflict, "无本地改动时不该弹冲突")
        XCTAssertEqual(store.workingText, "另一端的修改", "应自动载入磁盘版本")
    }

    /// 有未保存改动 → 以编辑器内容为准自动落盘（外部版本进历史快照），不弹任何冲突框。
    /// 旧策略会弹冲突并暂停自动保存，实测把用户卡死在"改了不落盘"。
    @MainActor
    func testExternalChangeWithLocalEditsKeepsEditorContent() throws {
        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = create(store, "并发笔记2.md")
        TestEnv.pump()
        store.workingText = "我的本地修改"
        store.dirty = true

        injectExternal(store, id: id, text: "另一端的修改")
        store.reloadIndex()
        TestEnv.pump(0.6)

        XCTAssertFalse(store.externalConflict, "不该再进入需要人工处理的冲突态")
        XCTAssertEqual(store.workingText, "我的本地修改", "编辑器内容不被外部版本替换")
        XCTAssertEqual(fileText(store, id), "我的本地修改", "编辑器内容应已落盘")
        XCTAssertFalse(store.listVersions(id).isEmpty, "外部版本应留在历史快照里，可回查")
    }
}

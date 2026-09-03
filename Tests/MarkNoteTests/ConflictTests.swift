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

    @MainActor
    func testExternalChangeDetected() throws {
        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = create(store, "并发笔记.md")
        TestEnv.pump()
        XCTAssertFalse(store.externalConflict)

        injectExternal(store, id: id, text: "另一端的修改")
        store.reloadIndex()
        TestEnv.pump(0.5)

        XCTAssertTrue(store.externalConflict, "外部修改后应进入冲突状态")
        XCTAssertEqual(store.workingText, "", "冲突未解决时编辑器内容不应被外部版本替换")
    }

    @MainActor
    func testResolveReloadKeepsMyContentAsVersion() throws {
        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = create(store, "并发笔记.md")
        TestEnv.pump()
        store.workingText = "我的本地修改"
        store.dirty = true

        injectExternal(store, id: id, text: "外部版本内容")
        store.reloadIndex()
        TestEnv.pump(0.5)
        XCTAssertTrue(store.externalConflict)

        store.resolveExternalConflict(.reload)
        TestEnv.pump(0.5)

        XCTAssertFalse(store.externalConflict)
        XCTAssertEqual(store.workingText, "外部版本内容", "reload 后编辑器应显示外部版本")
        let versions = store.listVersions(id)
        XCTAssertFalse(versions.isEmpty, "reload 前应给本地内容留快照")
        let latest = versions.first!
        let archived = store.versionNote(id, latest.ts)
        XCTAssertEqual(archived?.content, "我的本地修改", "本地改动先入快照（原始文本）")
    }

    @MainActor
    func testResolveKeepMineSnapshotsExternalThenOverwrite() throws {
        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = create(store, "并发笔记.md")
        TestEnv.pump()
        store.workingText = "我的坚持"
        store.dirty = true

        injectExternal(store, id: id, text: "外部先改的")
        store.reloadIndex()
        TestEnv.pump(0.5)
        store.resolveExternalConflict(.keepMine)
        TestEnv.pump(0.5)

        XCTAssertEqual(fileText(store, id), "我的坚持", "keepMine 后磁盘应是我的内容")
        let archived = store.listVersions(id).first.flatMap { store.versionNote(id, $0.ts) }
        XCTAssertEqual(archived?.content, "外部先改的", "外部版本应入快照")
    }

    @MainActor
    func testLaterPausesAutoSaveAndFlushSavesCopy() throws {
        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = create(store, "并发笔记.md")
        TestEnv.pump()
        store.workingText = "未决定的内容"
        store.dirty = true

        injectExternal(store, id: id, text: "外部版本")
        store.reloadIndex()
        TestEnv.pump(0.5)
        store.resolveExternalConflict(.later)
        XCTAssertTrue(store.conflictHandled)

        // 冲突挂起时：手动保存被阻止（文件仍为外部版本）
        store.saveCurrent()
        TestEnv.pump()
        XCTAssertEqual(fileText(store, id), "外部版本")

        // 退出兜底：flush → 另存为副本，不覆盖
        store.flush()
        TestEnv.pump(0.5)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".md") }
        XCTAssertGreaterThan(files.count, 1, "flush 应另存副本而非覆盖")
    }
}

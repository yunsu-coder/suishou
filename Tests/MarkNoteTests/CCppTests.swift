import XCTest
import Foundation
@testable import MarkNote

final class CCppTests: XCTestCase {

    @MainActor
    func testImportCPreservesExtension() throws {
        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("main.c")
        try "#include <stdio.h>\nint main(){ return 0; }".write(to: f, atomically: true, encoding: .utf8)
        let id = store.importDroppedFile(from: f, into: "code")
        TestEnv.pump(0.4)
        XCTAssertEqual(id, "code/main.c", "导入应保留 .c：\(id ?? "nil")")
        let md = FileManager.default.fileExists(atPath: store.notesDir.appendingPathComponent("code/main.md").path)
        XCTAssertFalse(md, "不得生成 main.md")
    }

    @MainActor
    func testCPPEditableExtClassification() {
        XCTAssertTrue(Workspace.isEditorText("cpp"))
        XCTAssertTrue(Workspace.isEditorText("C"))
        XCTAssertFalse(Workspace.isEditorText("mp4"))
        XCTAssertEqual(Workspace.lineComment(for: "c"), "//")
        XCTAssertEqual(Workspace.lineComment(for: "cpp"), "//")
        XCTAssertEqual(Workspace.fileSymbol(for: "cpp"), "chevron.left.forwardslash.chevron.right")
    }
}

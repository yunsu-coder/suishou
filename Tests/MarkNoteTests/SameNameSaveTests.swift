import XCTest
import Foundation
@testable import MarkNote

/// 同名判定按「完整文件名（含扩展名）」：1.cpp 与 1.md 是两份不同文件，
/// 不能因为去掉扩展名后都叫「1」就拒绝保存（线上实测：1.cpp 的保存被 1.md 挡掉了）。
final class SameNameSaveTests: XCTestCase {

    @MainActor
    func testDifferentExtensionsDoNotBlockSave() throws {
        let (store, temp) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: temp) }

        XCTAssertTrue(store.createNote(title: "1.cpp", category: ""))
        store.openNote("1.cpp")
        store.textChanged("int main() { return 0; }\n")
        store.saveCurrent()
        XCTAssertEqual(try String(contentsOf: store.notesDir.appendingPathComponent("1.cpp"), encoding: .utf8),
                       "int main() { return 0; }\n", "1.cpp 应正常落盘（哪怕同目录有 1.md）")

        // 同目录再来一个同名的 .md：两份都该能存
        XCTAssertTrue(store.createNote(title: "1.md", category: ""))
        store.openNote("1.md")
        store.textChanged("# 笔记\n")
        store.saveCurrent()
        XCTAssertEqual(try String(contentsOf: store.notesDir.appendingPathComponent("1.md"), encoding: .utf8),
                       "# 笔记\n", "1.md 也应正常落盘")
        XCTAssertEqual(try String(contentsOf: store.notesDir.appendingPathComponent("1.cpp"), encoding: .utf8),
                       "int main() { return 0; }\n", "1.cpp 内容不该被改动")

        // 回到 1.cpp 继续改再存：不能被 1.md 判成"同名"
        store.openNote("1.cpp")
        store.textChanged("// quick pow\nint main() { return 1; }\n")
        store.saveCurrent()
        XCTAssertEqual(try String(contentsOf: store.notesDir.appendingPathComponent("1.cpp"), encoding: .utf8),
                       "// quick pow\nint main() { return 1; }\n")
    }

    /// 真正的同名（同目录同扩展名）仍然要被挡住 —— 不能把校验整个删了
    @MainActor
    func testExactSameFileNameStillRejected() throws {
        let (store, temp) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: temp) }
        XCTAssertTrue(store.createNote(title: "note.md", category: ""))
        XCTAssertFalse(store.createNote(title: "note.md", category: ""), "同目录同名同扩展名必须拒绝")
    }

    /// 文件夹删除：树行 hover 的 🗑 现在两种方式都要能用
    @MainActor
    func testDeleteFolderTwoWays() throws {
        let (store, temp) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: temp) }

        XCTAssertTrue(store.createNote(title: "a.md", category: "docs"))
        XCTAssertTrue(store.createNote(title: "b.md", category: "docs"))
        TestEnv.pump(0.4)   // 索引刷新是异步的（后台扫描 → 主线程应用）
        XCTAssertEqual(store.noteCount(inCategory: "docs"), 2, "确认框要能报出文件数")

        // 方式一：只删文件夹，文件移到根目录
        store.deleteCategory("docs")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.notesDir.appendingPathComponent("docs").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.notesDir.appendingPathComponent("a.md").path),
                      "文件应被移到根目录而不是删掉")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.notesDir.appendingPathComponent("b.md").path))

        // 方式二：连同文件一起删
        XCTAssertTrue(store.createNote(title: "c.md", category: "tmp2"))
        store.deleteCategoryWithContents("tmp2")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.notesDir.appendingPathComponent("tmp2").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.notesDir.appendingPathComponent("tmp2/c.md").path),
                       "连同内容一起删时文件也不该留下")
    }
}

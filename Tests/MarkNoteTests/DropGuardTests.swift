import XCTest
import Foundation
@testable import MarkNote

final class DropGuardTests: XCTestCase {

    @MainActor
    func testMP4DropLandsRawNotMD() throws {
        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        // 伪造一个 MP4（二进制头）
        let fake = dir.appendingPathComponent("sample.mp4")
        var bytes = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70])
        bytes.append(Data(repeating: 0x41, count: 4096))
        try bytes.write(to: fake)

        let id = store.importDroppedFile(from: fake, into: "test")
        TestEnv.pump(0.4)
        XCTAssertNotNil(id, "非文本文件应成功放入")
        XCTAssertEqual(id, "test/sample.mp4", "保留扩展名：\(id ?? "nil")")
        // 不得生成 .md
        let mdExists = FileManager.default.fileExists(
            atPath: store.notesDir.appendingPathComponent("test/sample.mp4.md").path)
        XCTAssertFalse(mdExists, "绝不允许 .md 化")
        // 原始内容一致
        let got = try? Data(contentsOf: store.notesDir.appendingPathComponent("test/sample.mp4"))
        XCTAssertEqual(got, bytes)
    }

    @MainActor
    func testBinaryRejectedFromTextImport() throws {
        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = dir.appendingPathComponent("huge.jpg")
        try Data(repeating: 0x00, count: 1024).write(to: fake)
        XCTAssertNil(store.importNote(from: fake), "二进制文件不得走文本导入")
    }

    @MainActor
    func testExternalCopyKeepsOriginal() throws {
        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        // 外部文件放在工作台之外（独立临时目录）
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        let original = outside.appendingPathComponent("外部.mp4")
        try Data([0x00, 0x01, 0x02]).write(to: original)
        let id = store.importRawFile(original, into: "")
        TestEnv.pump(0.4)
        XCTAssertEqual(id, "外部.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path), "外部文件复制而非移动")
    }
}

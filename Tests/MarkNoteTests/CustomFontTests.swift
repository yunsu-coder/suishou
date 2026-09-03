import XCTest
import Foundation
@testable import MarkNote

/// 自定义字体库：导入 / 去重 / 删除 / 坏文件容错
final class CustomFontTests: XCTestCase {

    /// 隔离的临时字体库目录
    private func tmpLibrary() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("marknote-fonts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 系统内置真字体（Menlo.ttc）—— 全 macOS 一致存在；缺失时跳过
    private func realFontURL() throws -> URL? {
        let url = URL(fileURLWithPath: "/System/Library/Fonts/Menlo.ttc")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func testUnsupportedExtension() throws {
        let lib = try tmpLibrary()
        let src = try tmpLibrary()
        let junk = src.appendingPathComponent("a.pdf")
        try Data("not a font".utf8).write(to: junk)
        if case .unsupported = CustomFonts.importFont(from: junk, into: lib) {
            XCTAssertTrue(true)
        } else {
            XCTFail("非字体扩展名应返回 .unsupported")
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: lib.path).isEmpty)
    }

    func testJunkFontDataFailsGracefully() throws {
        let lib = try tmpLibrary()
        let src = try tmpLibrary()
        let junk = src.appendingPathComponent("bad.ttf")
        try Data("not a real ttf".utf8).write(to: junk)
        if case .unreadable = CustomFonts.importFont(from: junk, into: lib) {
            XCTAssertTrue(true)
        } else {
            XCTFail("损坏的字体文件应返回 .unreadable，不崩溃、不残留")
        }
        // 坏文件必须被清理（不留半成品）
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: lib.path).isEmpty)
    }

    func testImportRealFontDedupeAndRemove() throws {
        guard let src = try realFontURL() else {
            throw XCTSkip("系统字体 Menlo.ttc 不存在")
        }
        let dir = try tmpLibrary()
        guard case .ok(let entry) = CustomFonts.importFont(from: src, into: dir) else {
            return XCTFail("Menlo.ttc 应导入成功")
        }
        XCTAssertFalse(entry.family.isEmpty, "家族名必须解析出来")
        XCTAssertEqual(CustomFonts.loadLibrary(in: dir).map(\.family), [entry.family], "库中应出现该字体")
        // 同内容二次导入 → 去重
        if case .duplicate(let dup) = CustomFonts.importFont(from: src, into: dir) {
            XCTAssertEqual(dup.id, entry.id)
        } else {
            XCTFail("同内容二次导入应判重")
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 1, "去重后目录不应新增文件")
        // 删除 → 库清空
        CustomFonts.remove(entry, in: dir)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }
}

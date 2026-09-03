import XCTest
import Foundation
@testable import MarkNote

final class PluginTests: XCTestCase {

    @MainActor
    func testScanExpertsAndToggle() throws {
        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pm = PluginManager.shared
        let pid = "t-exp-\(Int(Date().timeIntervalSince1970))"
        UserDefaults.standard.set(false, forKey: "pluginEnabled.\(pid)")
        let root = dir.appendingPathComponent(".plugins/\(pid)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manifest = ["id": pid, "name": "测试专家", "version": "1.0", "kind": "experts", "main": "experts.json"]
        try JSONSerialization.data(withJSONObject: manifest).write(to: root.appendingPathComponent("manifest.json"))
        let experts = [["id": "t1", "name": "测试", "icon": "sparkles", "desc": "d", "system": "你是测试专家"]]
        try JSONSerialization.data(withJSONObject: experts).write(to: root.appendingPathComponent("experts.json"))

        pm.scan(workspaceDir: dir)
        let pkg = pm.allPackages().first { $0.id == pid }
        XCTAssertNotNil(pkg, "扫到测试包")
        XCTAssertFalse(pkg?.enabled ?? true, "默认禁用（显式启用）")
        XCTAssertTrue(pm.allExperts().filter { $0.id == "t1" }.isEmpty, "禁用时专家不注册")

        pm.toggle(pid)
        XCTAssertTrue(pm.allPackages().first { $0.id == pid }?.enabled ?? false, "切换后启用")
        XCTAssertEqual(pm.allExperts().filter { $0.id == "t1" }.count, 1, "启用后专家注册")
        UserDefaults.standard.set(false, forKey: "pluginEnabled.\(pid)")
    }

    @MainActor
    func testBadManifestSkipped() throws {
        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = dir.appendingPathComponent(".plugins/bad-id-dev", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "not-json".write(to: root.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        PluginManager.shared.scan(workspaceDir: dir)
        let bad = PluginManager.shared.allPackages().first { $0.id == "bad-id-dev" }
        XCTAssertNil(bad, "坏 manifest 静默跳过")
    }

    func testFileOverridePriority() {
        let icon = Workspace.fileSymbol(for: "cpp")
        XCTAssertEqual(icon, "chevron.left.forwardslash.chevron.right")
        XCTAssertEqual(Workspace.lineComment(for: "md"), "<!--")
    }
}

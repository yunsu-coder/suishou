import XCTest
import Foundation
@testable import MarkNote

final class ReferenceTests: XCTestCase {

    @MainActor
    func testFindReferenceMatching() throws {
        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let agent = WorkspaceAgent(store: store)
        // 造两个文件（走 agent 写，再 pump 让索引就绪）
        _ = agent.handle(FileTools.ParsedCall(id: "w1", name: "write_file",
                                              arguments: try! JSONString(["path": "甲.md", "content": "甲内容", "mode": "create"])))
        _ = agent.handle(FileTools.ParsedCall(id: "w2", name: "write_file",
                                              arguments: try! JSONString(["path": "归档/乙.md", "content": "乙内容", "mode": "create"])))
        store.reloadIndex()
        TestEnv.pump(0.5)

        XCTAssertEqual(agent.findReference("甲"), "甲.md", "文件名精确命中")
        XCTAssertEqual(agent.findReference("甲.md"), "甲.md", "含扩展名命中")
        XCTAssertEqual(agent.findReference("乙"), "归档/乙.md", "子目录文件命中")
        XCTAssertEqual(agent.findReference("归档/乙"), "归档/乙.md", "路径前缀命中")
        XCTAssertNil(agent.findReference("不存在的文件"), "无命中返回 nil")

        // 引用读取（同一限额）
        let content = agent.readReference("甲.md")
        XCTAssertEqual(content, "甲内容")
        XCTAssertNil(agent.readReference("../x.md"), "越界引用拒绝")
    }
}

func JSONString(_ obj: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: obj)
    return String(data: data, encoding: .utf8)!
}

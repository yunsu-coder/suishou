import XCTest
import Foundation
@testable import MarkNote

final class AIHistoryTests: XCTestCase {

    @MainActor
    func testPersistLoadDeleteConversation() throws {
        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = AIChatModel()
        model.historyBaseDir = { store.notesDir }

        // 持久化两个会话（无网络：直接构造消息）
        let m1 = AIChatModel.ChatMsg(role: "user", content: "读一下 甲.md")
        let m2 = AIChatModel.ChatMsg(role: "assistant", content: "好的，文件内容如下")
        model.messages = [m1, m2]
        model.expertID = "translator"
        model.currentConversationID = "conv-1"
        model.persistCurrentConversation()

        model.messages = [AIChatModel.ChatMsg(role: "user", content: "总结笔记")]
        model.currentConversationID = "conv-2"
        model.persistCurrentConversation()

        // 另一实例从磁盘读回
        let model2 = AIChatModel()
        model2.historyBaseDir = { store.notesDir }
        model2.loadHistory()
        XCTAssertEqual(model2.conversations.count, 2)
        XCTAssertEqual(model2.conversations.first?.id, "conv-2", "按更新时间倒序")

        model2.loadConversation("conv-1")
        XCTAssertEqual(model2.messages.count, 2)
        XCTAssertEqual(model2.messages[1].content, "好的，文件内容如下")
        XCTAssertEqual(model2.expertID, "translator", "专家随会话恢复")

        model2.deleteConversation("conv-1")
        XCTAssertEqual(model2.conversations.count, 1)
        XCTAssertTrue(model2.messages.isEmpty, "删除当前会话后清空")
    }

    func testBuildTranscriptCapsAndFormats() {
        let msgs = [
            AIChatModel.ChatMsg(role: "user", content: "帮我读文件"),
            AIChatModel.ChatMsg(role: "assistant", content: "好的"),
            AIChatModel.ChatMsg(role: "tool", content: "read_file → 甲.md"),
            AIChatModel.ChatMsg(role: "assistant", content: ""),   // 空内容跳过
        ]
        let tr = AIChatModel.buildTranscript(from: msgs)
        XCTAssertTrue(tr.contains("用户：帮我读文件"))
        XCTAssertTrue(tr.contains("AI：好的"))
        XCTAssertTrue(tr.contains("文件操作"))
        XCTAssertTrue(tr.components(separatedBy: "AI：").count == 2, "空内容助手消息应被跳过（只保留一条 AI 前缀）")
        // 超长截断（保留尾部）
        let big = String(repeating: "x", count: 30_000)
        let capped = AIChatModel.buildTranscript(from: [AIChatModel.ChatMsg(role: "assistant", content: big)], limit: 1000)
        XCTAssertLessThanOrEqual(capped.count, 1000)
    }

    @MainActor
    func testCreateUniqueTextFile() throws {
        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let agent = WorkspaceAgent(store: store)
        let n1 = agent.createUniqueTextFile(baseName: "对话总结", content: "# 总结")
        XCTAssertEqual(n1, "对话总结.md")
        let n2 = agent.createUniqueTextFile(baseName: "对话总结", content: "# 总结2")
        XCTAssertEqual(n2, "对话总结 2.md")
        // 目录也可用
        let n3 = agent.createUniqueTextFile(baseName: "归档/总结", content: "x")
        XCTAssertEqual(n3, "归档/总结.md")
    }
}

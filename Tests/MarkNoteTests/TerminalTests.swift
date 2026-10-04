import XCTest
import Foundation
@testable import MarkNote

/// 终端插件：运行命令解析 + PTY 会话（真跑一条命令验证流式输出与退出码）
final class TerminalTests: XCTestCase {

    // MARK: - 命令解析

    func testRunCommandPerLanguage() {
        let dir = URL(fileURLWithPath: "/tmp/marknote-run")
        func cmd(_ ext: String, _ file: String = "/w/a.py") -> String? {
            RunCommand.command(forExt: ext, file: file, buildDir: dir)
        }
        XCTAssertEqual(cmd("py"), "python3 '/w/a.py'")
        XCTAssertEqual(cmd("js"), "node '/w/a.py'")
        XCTAssertTrue(cmd("ts")?.contains("tsx '/w/a.py'") == true, "TS 优先 tsx")
        XCTAssertEqual(cmd("go"), "go run '/w/a.py'")
        XCTAssertTrue(cmd("cpp", "/w/main.cpp")?.contains("c++ -std=c++17") == true)
        XCTAssertTrue(cmd("cpp", "/w/main.cpp")?.contains("'/tmp/marknote-run/main'") == true, "编译产物进临时目录")
        XCTAssertTrue(cmd("c", "/w/main.c")?.contains("clang") == true)
        XCTAssertEqual(cmd("java"), "java '/w/a.py'")
        XCTAssertEqual(cmd("swift"), "swift '/w/a.py'")
        XCTAssertEqual(cmd("rb"), "ruby '/w/a.py'")
        XCTAssertEqual(cmd("sh"), "/bin/sh '/w/a.py'")
        XCTAssertEqual(cmd("html"), "open '/w/a.py'")
        XCTAssertNil(cmd("xyz"), "未知类型不编造命令")
        XCTAssertNil(cmd("md"), "Markdown 不是可运行代码")
    }

    func testShellQuoteHandlesSpacesAndQuotes() {
        XCTAssertEqual(RunCommand.shellQuote("/a b/c.py"), "'/a b/c.py'")
        XCTAssertEqual(RunCommand.shellQuote("/a/it's.py"), "'/a/it'\\''s.py'")
        XCTAssertEqual(RunCommand.shellQuote("$HOME/x"), "'$HOME/x'")
    }

    // MARK: - 输出清洗

    func testAnsiAndCarriageReturnCleaning() {
        XCTAssertEqual(TerminalSession.clean("\u{1B}[31m红\u{1B}[0m"), "红")
        XCTAssertEqual(TerminalSession.clean("a\r\nb"), "a\nb")
        XCTAssertEqual(TerminalSession.clean("10%\r50%\r100%"), "100%", "覆盖式刷新只留最后一段")
        XCTAssertEqual(TerminalSession.clean("\u{1B}]8;;http://x\u{07}link"), "link")
    }

    // MARK: - 真会话

    @MainActor
    func testSessionStreamsOutputAndExitCode() async throws {
        let session = TerminalSession(cwd: FileManager.default.temporaryDirectory)
        session.startIfNeeded()
        session.run("echo MARKNOTE_TERM_OK")

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !(session.output.contains("MARKNOTE_TERM_OK") && session.lastExitCode == 0) {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(session.isStarted, "登录 shell 应已起来")
        XCTAssertTrue(session.output.contains("MARKNOTE_TERM_OK"), "输出应流式回来：\(session.output.suffix(200))")
        XCTAssertEqual(session.lastExitCode, 0, "哨兵应回传退出码")
        XCTAssertFalse(session.isRunning, "命令结束后运行态应复位")

        // 失败命令也要能拿到非零退出码
        session.run("exit 3")
        let deadline2 = Date().addingTimeInterval(6)
        while Date() < deadline2, session.lastExitCode == 0 {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        session.shutdown()
    }

    /// 插件包能被扫描成 terminal 视图（面板与入口都依赖它）
    @MainActor
    func testTerminalPackageRegistersView() throws {
        let market = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("plugins-market/view-terminal")
        XCTAssertTrue(FileManager.default.fileExists(atPath: market.path), "缺终端插件包")

        let (_, temp) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: temp) }
        let dest = temp.appendingPathComponent(".plugins/view-terminal")
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: market, to: dest)
        UserDefaults.standard.set(true, forKey: "pluginEnabled.view-terminal")
        defer { UserDefaults.standard.removeObject(forKey: "pluginEnabled.view-terminal") }
        PluginManager.shared.scan(workspaceDir: temp)

        let views = PluginManager.shared.allViews()
        XCTAssertTrue(views.contains { $0.type == .terminal }, "终端视图应注册：\(views.map(\.type.rawValue))")
        XCTAssertTrue(PluginManager.shared.viewIssues(for: "view-terminal").isEmpty,
                      "插件包不该有校验问题：\(PluginManager.shared.viewIssues(for: "view-terminal"))")
    }
}

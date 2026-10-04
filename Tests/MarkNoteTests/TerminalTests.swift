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
        XCTAssertEqual(TerminalSession.clean("\u{1B}]7;file://h/Users/me\u{1B}\\out"), "out",
                       "OSC 7（cwd 通知）用 ESC\\ 结束时也要吃掉")
        XCTAssertEqual(TerminalSession.clean("a\u{1B}[0Kb"), "ab", "CSI 的 K 类也要吃掉")
        XCTAssertEqual(TerminalSession.clean("\u{1B}[?2004h$ "), "$ ", "括号粘贴模式开关")
    }

    func testSplitEscapeSequenceIsHeldBack() {
        // OSC 7 被拆包：前半段不能漏成 "]7;file://…" 乱码
        XCTAssertEqual(TerminalSession.danglingEscapeIndex("ok\u{1B}]7;file://h/Us"), 2)
        XCTAssertNil(TerminalSession.danglingEscapeIndex("\u{1B}]7;file://h/Us\u{07}done"))
        XCTAssertEqual(TerminalSession.danglingEscapeIndex("x\u{1B}[32"), 1)
        XCTAssertNil(TerminalSession.danglingEscapeIndex("x\u{1B}[32m"))
        XCTAssertNil(TerminalSession.danglingEscapeIndex("plain"))
        // 回归：完整的 CSI 后面跟正文（提示符块就是这种形态）不能被当成未闭合，
        // 否则后续输出会被无限压进缓冲、连哨兵都收不到
        XCTAssertNil(TerminalSession.danglingEscapeIndex("\u{1B}[0m      \r \r"))
        XCTAssertNil(TerminalSession.danglingEscapeIndex("\u{1B}[1m%\u{1B}[27m tail"))
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
        // 用户实测到的乱码：提示符残留、OSC 7、哨兵外泄，都不该出现
        XCTAssertFalse(session.output.contains("]7;"), "不应有 OSC 7（cwd 通知）残留")
        XCTAssertFalse(session.output.contains("__MARKNOTE_EXIT__"), "退出码哨兵不该露出来")
        XCTAssertFalse(session.output.contains("__MARKNOTE_READY__"), "握手哨兵不该露出来")
        let hits = session.output.split(separator: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces) == "MARKNOTE_TERM_OK" }
        XCTAssertEqual(hits.count, 1, "命令输出只该出现一次（回显不算）：\(session.output)")

        // 中断：长命令点 ⏹ 要真的停下（^C → 前台进程组）
        session.run("sleep 30")
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertTrue(session.isRunning, "长命令应在跑")
        session.interrupt()
        let deadline2 = Date().addingTimeInterval(8)
        while Date() < deadline2, session.isRunning {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertFalse(session.isRunning, "中断后应结束：\(session.output.suffix(160))")
        XCTAssertNotEqual(session.lastExitCode, 0, "被中断的命令不该是 0")
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

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

    /// 终端配色：ANSI 16 色齐全（VS Code 默认 Dark+ / Light+ 两套），明暗各一套
    func testTerminalThemePalettes() {
        XCTAssertEqual(TerminalTheme.vsCodeDark.count, 16)
        XCTAssertEqual(TerminalTheme.vsCodeLight.count, 16)
        XCTAssertEqual(TerminalTheme.vsCodeDark[1].red, UInt16(0xCD) * 257, "红色 #CD3131")
        XCTAssertEqual(TerminalTheme.vsCodeLight[2].green, UInt16(0xBC) * 257, "绿色 #00BC00")
        let theme = TerminalTheme.current(fontFamily: "mono")
        XCTAssertEqual(theme.ansi.count, 16)
        XCTAssertGreaterThan(theme.font.pointSize, 8)
    }

    /// 真终端集成：SwiftTerm 起登录 shell → 打进一条命令 → 终端缓冲里能看到输出
    /// （等于验证了 pty 分配、shell 启动、xterm 解析三个环节）
    @MainActor
    func testTerminalTabRunsCommandThroughRealPty() async throws {
        let tab = TerminalTab(theme: TerminalTheme.current(fontFamily: "mono"),
                              cwd: FileManager.default.temporaryDirectory)
        defer { tab.stop() }
        XCTAssertFalse(tab.exited, "shell 应该在跑")

        tab.run("echo MARKNOTE_TERM_OK")
        var screen = ""
        for _ in 0..<60 {
            try await Task.sleep(nanoseconds: 100_000_000)
            screen = Self.screenText(of: tab)
            if screen.contains("MARKNOTE_TERM_OK") { break }
        }
        XCTAssertTrue(screen.contains("MARKNOTE_TERM_OK"),
                      "命令输出应出现在终端缓冲：\(screen.suffix(200))")
    }

    private static func screenText(of tab: TerminalTab) -> String {
        let term = tab.view.getTerminal()
        var out = ""
        for row in 0..<term.rows {
            if let line = term.getLine(row: row) {
                out += line.translateToString(trimRight: true) + "\n"
            }
        }
        return out
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

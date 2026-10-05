import XCTest
import Foundation
import SwiftTerm
@testable import MarkNote

/// 终端插件：运行命令解析 + PTY 会话（真跑一条命令验证流式输出与退出码）
final class TerminalTests: XCTestCase {

    // MARK: - 命令解析

    func testRunCommandPerLanguage() {
        let dir = URL(fileURLWithPath: "/tmp/marknote-run")
        func cmd(_ ext: String, _ file: String = "/w/a.py") -> String? {
            RunCommand.command(forExt: ext, file: file, buildDir: dir)
        }
        XCTAssertTrue(cmd("py")?.contains("python3 '/w/a.py'") == true, "Python 无 venv 时回落系统 python3")
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

    // MARK: - 第三方库 / 项目识别（IDE 式运行）

    func testThirdPartyLibsArePassedViaPkgConfig() throws {
        let ws = FileManager.default.temporaryDirectory.appendingPathComponent("mn-run-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: ws, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ws) }
        let src = ws.appendingPathComponent("main.cpp")
        try "int main(){}".write(to: src, atomically: true, encoding: .utf8)

        var cfg = RunConfig()
        cfg.libs = ["fmt", "sdl2"]
        cfg.cxxFlags = ["-std=c++20", "-Wall"]
        cfg.linkFlags = ["-lpthread"]
        try cfg.save(to: ws)

        let cmd = try XCTUnwrap(RunCommand.command(forExt: "cpp", file: src.path, workspace: ws))
        XCTAssertTrue(cmd.contains("pkg-config --cflags --libs 'fmt' 'sdl2'"), "第三方库走 pkg-config：\(cmd)")
        XCTAssertTrue(cmd.contains("-std=c++20"), "自定义编译参数要带上")
        XCTAssertTrue(cmd.contains("-I/opt/homebrew/include"), "Homebrew 头文件路径要带上")
        XCTAssertTrue(cmd.contains("-lpthread"), "链接参数要带上")
        // 已经显式给了 -std= 就不该再塞默认的 -std=c++17
        XCTAssertFalse(cmd.contains("-std=c++17"))
    }

    func testPythonPrefersWorkspaceVenv() throws {
        let ws = FileManager.default.temporaryDirectory.appendingPathComponent("mn-venv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: ws, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ws) }
        let src = ws.appendingPathComponent("a.py")
        try "print(1)".write(to: src, atomically: true, encoding: .utf8)

        let cmd = try XCTUnwrap(RunCommand.command(forExt: "py", file: src.path, workspace: ws))
        XCTAssertTrue(cmd.contains(".venv/bin/python"), "有虚拟环境就用它：\(cmd)")

        var cfg = RunConfig()
        cfg.python = "/opt/homebrew/bin/python3.12"
        try cfg.save(to: ws)
        let cmd2 = try XCTUnwrap(RunCommand.command(forExt: "py", file: src.path, workspace: ws))
        XCTAssertTrue(cmd2.contains("'/opt/homebrew/bin/python3.12'"), "手工指定的解释器优先：\(cmd2)")
    }

    func testProjectDetectionAndCustomCommands() throws {
        let ws = FileManager.default.temporaryDirectory.appendingPathComponent("mn-proj-\(UUID().uuidString)")
        let srcDir = ws.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ws) }
        let src = srcDir.appendingPathComponent("main.cpp")
        try "int main(){}".write(to: src, atomically: true, encoding: .utf8)

        XCTAssertEqual(ProjectKind.detect(in: ws), .single)
        XCTAssertEqual(ProjectKind.detect(from: src, workspace: ws).kind, .single, "没有项目文件就是单文件模式")

        try "cmake_minimum_required(VERSION 3.20)".write(to: ws.appendingPathComponent("CMakeLists.txt"),
                                                         atomically: true, encoding: .utf8)
        XCTAssertEqual(ProjectKind.detect(in: ws), .cmake)
        XCTAssertEqual(ProjectKind.detect(from: src, workspace: ws).kind, .cmake, "从 src/ 往上找到项目根")
        let cmd = try XCTUnwrap(RunCommand.command(forExt: "cpp", file: src.path, workspace: ws))
        XCTAssertTrue(cmd.contains("cmake -S . -B build"), "CMake 项目走 cmake 构建：\(cmd)")

        // 自定义命令优先级最高，且支持占位符
        var cfg = RunConfig()
        cfg.commands["cpp"] = "echo custom {stem} in {dir}"
        try cfg.save(to: ws)
        let custom = try XCTUnwrap(RunCommand.command(forExt: "cpp", file: src.path, workspace: ws))
        XCTAssertEqual(custom, "echo custom main in '\(srcDir.path)'")
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

    /// 读一行文本：SwiftTerm 缓冲里宽字符/空白用 NUL 占位，测试侧统一清掉
    private static func rowText(_ term: Terminal, _ row: Int) -> String {
        (term.getLine(row: row)?.translateToString(trimRight: true, skipNullCellsFollowingWide: true) ?? "")
            .replacingOccurrences(of: "\0", with: "")
    }

    private static func screenText(of tab: TerminalTab) -> String {
        let term = tab.view.getTerminal()
        var out = ""
        for row in 0..<term.rows {
            if let line = term.getLine(row: row) {
                out += line.translateToString(trimRight: true, skipNullCellsFollowingWide: true).replacingOccurrences(of: "\0", with: "") + "\n"
            }
        }
        return out
    }

    /// 真仿真验证：直接喂字节给模拟器（不经 shell，排除回显干扰），
    /// 光标定位（CUP）、清屏（ED）、SGR 颜色都必须如实生效。
    @MainActor
    func testTerminalEmulatesCupColorAndWideChars() async throws {
        let tab = TerminalTab(theme: TerminalTheme.current(fontFamily: "mono"),
                              cwd: FileManager.default.temporaryDirectory)
        defer { tab.stop() }
        let term = tab.view.getTerminal()

        // 清屏 → 第 3 行第 5 列写红字 RED → 换行后写中文
        let bytes = Array("\u{1B}[2J\u{1B}[3;5H\u{1B}[31mRED\u{1B}[0m\n中文宽字符\n".utf8)
        tab.view.feed(byteArray: bytes[...])
        try await Task.sleep(nanoseconds: 200_000_000)

        // 空白格在缓冲里是 NUL 占位：原样读出应是「4 个占位 + RED」→ R 落在第 5 列
        let raw2 = term.getLine(row: 2)?.translateToString(trimRight: false, skipNullCellsFollowingWide: true) ?? ""
        XCTAssertTrue(raw2.hasPrefix("\u{0}\u{0}\u{0}\u{0}RED"),
                      "CUP 3;5 应让 RED 从第 5 列开始，实际：[[\(Self.rowText(term, 2))]]")
        XCTAssertEqual(Self.rowText(term, 2), "RED", "第 3 行只有 RED")

        // 颜色：RED 的 R 应该带非默认前景
        if let cell = term.getCharData(col: 4, row: 2) {
            if case .defaultColor = cell.attribute.fg {
                XCTFail("SGR 31 应让 R 带上红色前景")
            }
        } else {
            XCTFail("取不到 RED 的 cell")
        }

        // 清屏生效：第 0/1 行应为空
        XCTAssertEqual(term.getLine(row: 0)?.translateToString(trimRight: true), "")

        // 宽字符：第 4 行应是中文，且每个汉字占 2 列
        let row3 = Self.rowText(term, 3)
        XCTAssertEqual(row3, "中文宽字符", "宽字符应原样落在下一行（NUL 占位格按宽字符处理）")
    }

    /// 诊断用：跑一圈真实输出（颜色 / 宽字符 / 中英混排 / 彩色 ls），把终端画面渲染成 PNG
    @MainActor
    func testTerminalRenderToPNG() async throws {
        let tab = TerminalTab(theme: TerminalTheme.current(fontFamily: "mono"),
                              cwd: FileManager.default.temporaryDirectory)
        defer { tab.stop() }
        tab.view.frame = NSRect(x: 0, y: 0, width: 900, height: 300)
        func wait(_ t: Double) async { try? await Task.sleep(nanoseconds: UInt64(t * 1_000_000_000)) }

        tab.run("clear")
        await wait(0.5)
        tab.run("printf '\\033[31m红\\033[32m绿\\033[34m蓝\\033[0m 普通中文与 English 混排\\n'")
        await wait(0.5)
        tab.run("printf '\\033[1;33m加粗黄\\033[0m \\033[4m下划线\\033[0m \\033[7m反色\\033[0m\\n'")
        await wait(0.5)
        tab.run("ls -la --color=always / | head -8")
        await wait(0.8)

        guard let rep = tab.view.bitmapImageRepForCachingDisplay(in: tab.view.bounds) else {
            return XCTFail("无法缓存终端画面")
        }
        tab.view.cacheDisplay(in: tab.view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("PNG 编码失败")
        }
        let out = URL(fileURLWithPath: "/tmp/terminal-render.png")
        try data.write(to: out)
        print("TERM-PNG \(out.path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
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

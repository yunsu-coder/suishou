import XCTest
@testable import MarkNote

/// clangd 端到端冒烟：真启动进程 → 打开文件 → 收到未定义标识符诊断。
/// 本机没有 clangd（非 Xcode 环境）时自动跳过。
final class ClangdClientTests: XCTestCase {

    @MainActor
    func testClangdReportsUndefinedIdentifier() throws {
        let path = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clangd"
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw XCTSkip("clangd not installed")
        }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clangd-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer {
            ClangdClient.shared.close(path: tmp.appendingPathComponent("t.cpp").path)
            ClangdClient.shared.shutdown()
            try? FileManager.default.removeItem(at: tmp)
        }
        let src = tmp.appendingPathComponent("t.cpp")
        let code = "int main() { return totally_undefined_thing; }\n"
        try code.write(to: src, atomically: true, encoding: .utf8)

        ClangdClient.shared.activate(root: tmp)
        ClangdClient.shared.sync(path: src.path, text: code, openIfNeeded: true)

        var hit = false
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            let diags = ClangdClient.shared.diagnostics(forPath: src.path)
            if diags.contains(where: { $0.message.contains("totally_undefined_thing") }) {
                hit = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(hit, "clangd 应在 30s 内报告未定义标识符")
    }

    @MainActor
    func testClangdCompletionIncludesThread() throws {
        let path = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clangd"
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw XCTSkip("clangd not installed")
        }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clangd-comp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer {
            ClangdClient.shared.close(path: tmp.appendingPathComponent("t2.cpp").path)
            ClangdClient.shared.shutdown()
            try? FileManager.default.removeItem(at: tmp)
        }
        let src = tmp.appendingPathComponent("t2.cpp")
        let code = "#include <thread>\nint main() { std::thr; }\n"
        try code.write(to: src, atomically: true, encoding: .utf8)

        ClangdClient.shared.activate(root: tmp)
        ClangdClient.shared.sync(path: src.path, text: code, openIfNeeded: true)

        // 光标在 "std::thr" 的 r 之后：0-based 行 1、字符 21
        var names: [String] = []
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            let exp = expectation(description: "completion")
            ClangdClient.shared.completion(path: src.path, line: 1, character: 21) { result in
                names = result
                exp.fulfill()
            }
            wait(for: [exp], timeout: 10)
            if names.contains(where: { $0.hasPrefix("thread") }) { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTAssertTrue(names.contains(where: { $0.hasPrefix("thread") }),
                      "补全应包含 thread，实际：\(names.prefix(20))")
    }
}

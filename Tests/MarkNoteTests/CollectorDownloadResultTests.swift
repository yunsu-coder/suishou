import XCTest
import Foundation
@testable import MarkNote

/// 「选了 4 个只下来 2 个」的账要算清楚：失败必须带原因，
/// 图片下载要按图站防盗链规则换 Referer 重试（本机 HTTP 服务模拟，不依赖外网）。
@MainActor
final class CollectorDownloadResultTests: XCTestCase {

    // MARK: - Referer 尝试序列（纯函数）

    func testImageRefererAttemptsSourceThenRootThenNone() throws {
        let page = try XCTUnwrap(URL(string: "https://www.bilibili.com/video/BV1?x=1"))
        XCTAssertEqual(NotesStore.imageDownloadReferers(page: page),
                       ["https://www.bilibili.com/video/BV1?x=1", "https://www.bilibili.com/", nil])
        // 只有根域时别重复试两遍
        XCTAssertEqual(NotesStore.imageDownloadReferers(page: URL(string: "https://weibo.com/")!),
                       ["https://weibo.com/", nil])
        // 没有来源页 → 只试不带 Referer
        XCTAssertEqual(NotesStore.imageDownloadReferers(page: nil), [nil])
    }

    // MARK: - 真下载：防盗链回退 / 失败原因（本机 HTTP）

    func testHotlinkBlockedImageFallsBackAndSaves() async throws {
        let (server, port, root) = try startServer()
        defer { server.terminate(); try? FileManager.default.removeItem(at: root) }
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/hotlink.png"))
        let page = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/article/1"))

        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = await store.downloadCollectedImage(from: url, preferredName: "带防盗链的图",
                                                        referer: page)

        let rel = try XCTUnwrap(result.path, "带 Referer 403、不带 Referer 200 时应能存下来"
                               + "（\(result.failureReason ?? "无原因")）")
        XCTAssertTrue(rel.hasPrefix("img/"), "图片按约定映射成 img/ 短前缀，实际 \(rel)")
        XCTAssertTrue(rel.hasSuffix(".png"), "按字节嗅探扩展名，实际 \(rel)")
        // img/ 是引用前缀，落盘位置是 source/image/
        let onDisk = dir.appendingPathComponent("source/image")
            .appendingPathComponent((rel as NSString).lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: onDisk.path), "文件要真的落进素材库：\(rel)")
    }

    func testHTMLPageReportsNotAnImage() async throws {
        let (server, port, root) = try startServer()
        defer { server.terminate(); try? FileManager.default.removeItem(at: root) }
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/page.html"))

        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = await store.downloadCollectedImage(from: url, preferredName: "错误页",
                                                        referer: nil)

        XCTAssertNil(result.path)
        let why = try XCTUnwrap(result.failureReason)
        XCTAssertTrue(why.contains("不是图片"), "原因要人话，实际「\(why)」")
    }

    func testMissingImageReportsHTTPStatus() async throws {
        let (server, port, root) = try startServer()
        defer { server.terminate(); try? FileManager.default.removeItem(at: root) }
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/missing.png"))

        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = await store.downloadCollectedImage(from: url, preferredName: "404",
                                                        referer: nil)

        XCTAssertNil(result.path)
        XCTAssertEqual(result.failureReason, "HTTP 404")
    }

    func testTinyPlaceholderReportsSize() async throws {
        let (server, port, root) = try startServer()
        defer { server.terminate(); try? FileManager.default.removeItem(at: root) }
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/tiny.png"))

        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = await store.downloadCollectedImage(from: url, preferredName: "占位图",
                                                        referer: nil)

        XCTAssertNil(result.path)
        XCTAssertTrue(try XCTUnwrap(result.failureReason).contains("字节"), "要说清多小")
    }

    // MARK: - 本机 HTTP 服务：按 Referer 判防盗链 + 各种坏响应

    private func startServer() throws -> (Process, Int, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("marknote-img-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = """
        import http.server, socketserver, sys
        PNG = bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + b"\\x00" * 3000
        class H(http.server.BaseHTTPRequestHandler):
            def log_message(self, *a): pass
            def _send(self, code, body, ctype=None):
                self.send_response(code)
                if ctype: self.send_header("Content-Type", ctype)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            def do_GET(self):
                if self.path.startswith("/hotlink.png"):
                    if self.headers.get("Referer"):
                        return self._send(403, b"hotlink denied", "text/plain")
                    return self._send(200, PNG, "image/png")
                if self.path.startswith("/page.html"):
                    return self._send(200, b"<html><body>not an image</body></html>" * 100,
                                      "text/html; charset=utf-8")
                if self.path.startswith("/tiny.png"):
                    return self._send(200, b"\\x89PNG\\r\\n\\x1a\\n", "image/png")
                return self._send(404, b"nope", "text/plain")
        socketserver.TCPServer.allow_reuse_address = True
        srv = socketserver.TCPServer(("127.0.0.1", 0), H)
        print(srv.server_address[1], flush=True)
        srv.serve_forever()
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = ["-c", script]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do {
            try p.run()
        } catch {
            throw XCTSkip("没有可用的 python3：跳过本机 HTTP 测试")
        }
        let deadline = Date().addingTimeInterval(5)
        var buffer = Data()
        while Date() < deadline {
            let chunk = out.fileHandleForReading.availableData
            if !chunk.isEmpty { buffer.append(chunk) }
            if let text = String(data: buffer, encoding: .utf8),
               let first = text.split(separator: "\n").first,
               let port = Int(first.trimmingCharacters(in: .whitespaces)) {
                return (p, port, root)
            }
            if !p.isRunning, buffer.isEmpty {
                throw XCTSkip("python3 http.server 起不来：跳过本机 HTTP 测试")
            }
        }
        p.terminate()
        throw XCTSkip("本机 HTTP 服务 5 秒内没就绪：跳过")
    }
}

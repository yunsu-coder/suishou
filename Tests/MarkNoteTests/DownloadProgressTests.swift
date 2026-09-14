import XCTest
import Foundation
@testable import MarkNote

/// 下载进度：样本 / 节流是纯函数；`ProgressDownload` 用**本机 HTTP 服务**跑真下载，
/// 不依赖外网、也不需要 RUN_NET_TESTS（只在没有 python3 时跳过）。
final class DownloadProgressTests: XCTestCase {

    // MARK: - 纯函数：样本与节流

    func testSampleFractionAndBytesText() {
        let known = DownloadProgressSample(written: 512 * 1024, expected: 1024 * 1024)
        XCTAssertEqual(try XCTUnwrap(known.fraction), 0.5, accuracy: 0.001)
        XCTAssertEqual(known.bytesText, "512 KB / 1.0 MB")
        // 总长未知 → 不给假百分比，只报已下载量
        let unknown = DownloadProgressSample(written: 3 * 1024, expected: 0)
        XCTAssertNil(unknown.fraction)
        XCTAssertEqual(unknown.bytesText, "3 KB")
        // 超过声明长度也不再 >100%
        XCTAssertEqual(try XCTUnwrap(DownloadProgressSample(written: 300, expected: 100).fraction),
                       1, accuracy: 0.0001)
    }

    func testThrottleEmitsFirstPercentStepsAndFinish() {
        var t = DownloadProgressThrottle(minDelta: 0.01, minInterval: 0.08)
        let base = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(t.shouldEmit(.init(written: 10, expected: 1000), now: base), "首个样本必发")
        XCTAssertFalse(t.shouldEmit(.init(written: 11, expected: 1000),
                                    now: base.addingTimeInterval(0.01)),
                       "同一瞬间的小变化不刷 UI")
        XCTAssertTrue(t.shouldEmit(.init(written: 30, expected: 1000),
                                   now: base.addingTimeInterval(0.02)),
                      "跨过 1% 就发（进度看得见在走）")
        XCTAssertFalse(t.shouldEmit(.init(written: 31, expected: 1000),
                                    now: base.addingTimeInterval(0.03)))
        XCTAssertTrue(t.shouldEmit(.init(written: 32, expected: 1000),
                                   now: base.addingTimeInterval(0.20)),
                      "慢速下载靠时间兜底（80ms 也发一次）")
        XCTAssertTrue(t.shouldEmit(.init(written: 1000, expected: 1000),
                                   now: base.addingTimeInterval(0.21)),
                      "完成必发")
    }

    func testThrottleUnknownTotalUsesTimeOnly() {
        var t = DownloadProgressThrottle(minDelta: 0.01, minInterval: 0.08)
        let base = Date(timeIntervalSince1970: 2_000)
        XCTAssertTrue(t.shouldEmit(.init(written: 100, expected: 0), now: base))
        XCTAssertFalse(t.shouldEmit(.init(written: 200, expected: 0),
                                    now: base.addingTimeInterval(0.1)))
        XCTAssertTrue(t.shouldEmit(.init(written: 300, expected: 0),
                                   now: base.addingTimeInterval(0.5)))
    }

    // MARK: - 真下载（本机 HTTP 服务）

    func testProgressDownloadStreamsToDiskWithProgress() async throws {
        let (server, port, root) = try startServer()
        defer { server.terminate(); try? FileManager.default.removeItem(at: root) }
        let blob = Data(repeating: 0x7B, count: 3 * 1024 * 1024)
        try blob.write(to: root.appendingPathComponent("blob.bin"))
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/blob.bin"))
        let dest = root.appendingPathComponent("out/landed.bin")

        let samples = SampleSink()
        let file = try await ProgressDownload.run(URLRequest(url: url), to: dest, maxBytes: 0) {
            samples.append($0)
        }

        XCTAssertEqual(file.bytes, Int64(blob.count), "落盘字节数 = 源文件大小")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path), "要真的写进目标路径")
        let diskSize = ((try? FileManager.default.attributesOfItem(atPath: dest.path))?[.size]
            as? NSNumber)?.int64Value ?? 0
        XCTAssertEqual(diskSize, Int64(blob.count))
        let got = samples.values
        XCTAssertFalse(got.isEmpty, "至少要报一次进度（首帧必发）")
        XCTAssertEqual(got.map(\.written), got.map(\.written).sorted(), "已下载字节必须单调不减")
        XCTAssertTrue(got.allSatisfy { $0.expected == Int64(blob.count) },
                      "本机服务带 Content-Length，样本应知道总长")
    }

    func testProgressDownloadRejectsTooLargeBeforeFinish() async throws {
        let (server, port, root) = try startServer()
        defer { server.terminate(); try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0x5A, count: 3 * 1024 * 1024)
            .write(to: root.appendingPathComponent("big.bin"))
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/big.bin"))
        let dest = root.appendingPathComponent("out/too-big.bin")

        do {
            _ = try await ProgressDownload.run(URLRequest(url: url), to: dest, maxBytes: 256 * 1024)
            XCTFail("超过体积上限必须失败")
        } catch let failure as ProgressDownload.Failure {
            guard case .tooLarge = failure else {
                return XCTFail("应是 .tooLarge，实际 \(failure)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path), "超限不该留下半截文件")
    }

    /// 入库链路：命名清洗 + 字节嗅探（ftyp → source/mp4）+ 进度回调
    @MainActor
    func testCollectedVideoIngestKeepsNameAndSniffsFormat() async throws {
        let (server, port, root) = try startServer()
        defer { server.terminate(); try? FileManager.default.removeItem(at: root) }
        var blob = Data([0x00, 0x00, 0x00, 0x18]) + Data("ftypisom".utf8)
        blob.append(Data(repeating: 0x21, count: 200 * 1024))
        try blob.write(to: root.appendingPathComponent("clip.bin"))
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/clip.bin"))

        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let samples = SampleSink()
        let rel = await store.downloadCollectedVideo(from: url, preferredName: "夜景 视频/测试",
                                                     referer: nil) { samples.append($0) }

        let relPath = try XCTUnwrap(rel, "≥64KB 的视频应能入库")
        XCTAssertTrue(relPath.hasPrefix("source/mp4/"), "字节是 mp4（ftyp）就该进 source/mp4，实际 \(relPath)")
        XCTAssertTrue(relPath.hasSuffix(".mp4"), "扩展名按字节嗅探，实际 \(relPath)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(relPath).path))
        XCTAssertFalse(samples.values.isEmpty, "入库下载也要报进度（界面进度条的数据源）")
    }

    // MARK: - 本机 HTTP 服务（端口交给系统分配，读第一行 stdout 拿端口）

    private func startServer() throws -> (Process, Int, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("marknote-dl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = """
        import http.server, socketserver, sys, os
        os.chdir(sys.argv[1])
        class H(http.server.SimpleHTTPRequestHandler):
            def log_message(self, *a): pass
        socketserver.TCPServer.allow_reuse_address = True
        srv = socketserver.TCPServer(("127.0.0.1", 0), H)
        print(srv.server_address[1], flush=True)
        srv.serve_forever()
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = ["-c", script, root.path]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do {
            try p.run()
        } catch {
            throw XCTSkip("没有可用的 python3：跳过本机 HTTP 下载测试")
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
                throw XCTSkip("python3 http.server 起不来：跳过本机 HTTP 下载测试")
            }
        }
        p.terminate()
        throw XCTSkip("本机 HTTP 服务 5 秒内没就绪：跳过")
    }
}

/// 进度回调在后台线程，收集时要加锁（测试断言前统一取快照）
private final class SampleSink: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DownloadProgressSample] = []

    func append(_ s: DownloadProgressSample) {
        lock.lock(); storage.append(s); lock.unlock()
    }

    var values: [DownloadProgressSample] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}

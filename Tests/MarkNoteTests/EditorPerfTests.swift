import AppKit
import SwiftUI
import XCTest
@testable import MarkNote

/// 编辑器性能回归：语法着色的大文档解析必须留在预算内。
/// 背景：着色调度一度排在主队列上、每击键全量 tokenize 两遍 → 长笔记输入直接卡死。
final class EditorPerfTests: XCTestCase {

    private func bigDocument(lines: Int) -> String {
        var out: [String] = []
        for i in 0..<lines {
            switch i % 9 {
            case 0: out.append("## 第 \(i) 节 · 标题")
            case 1: out.append("- [x] 已完成事项 \(i) **重点** 与 *强调*")
            case 2: out.append("1. 有序条目 \(i).1 子项")
            case 3: out.append("| 列 A | 列 B | 列 C |")
            case 4: out.append("| --- | --- | --- |")
            case 5: out.append("> 引用 \(i)：包含 `代码` 与 [链接](https://example.com/\(i))")
            case 6: out.append("```swift")
            case 7: out.append("let value\(i): Int = \(i)  // 注释")
            default: out.append("```")
            }
        }
        return out.joined(separator: "\n")
    }

    /// 单次 tokenize 的耗时（旧代码每击键跑两遍，而且排在主队列上）
    func testTokenizeLargeDocumentStaysFast() throws {
        let md = bigDocument(lines: 3000)
        XCTAssertGreaterThan(md.count, 60_000, "样本得够大才测得出来")
        _ = MarkdownHighlighter.tokenize(md)   // 预热
        let start = Date()
        let tokens = MarkdownHighlighter.tokenize(md)
        let ms = Date().timeIntervalSince(start) * 1000
        print("PERF tokenize(\(md.count) chars / 3000 lines) = \(Int(ms)) ms, tokens=\(tokens.count)")
        XCTAssertGreaterThan(tokens.count, 1000)
        XCTAssertLessThan(ms, 1200, "单次全量解析超过 1.2s：输入必然卡顿")
        // 线性度体检：规模翻倍耗时不剧增（防 O(n²) 回潮）
        let half = bigDocument(lines: 1500)
        let t0 = Date()
        _ = MarkdownHighlighter.tokenize(half)
        let halfMs = max(1, Date().timeIntervalSince(t0) * 1000)
        print("PERF tokenize half-size = \(Int(halfMs)) ms (ratio \(String(format: "%.2f", ms / halfMs)))")
        XCTAssertLessThan(ms / halfMs, 3.5, "解析耗时随文档大小超线性增长")
    }

    /// 着色应用（主线程只做这一步）也要在预算内
    func testApplyHighlightBudget() throws {
        let md = bigDocument(lines: 1500)
        let textView = NSTextView()
        textView.string = md
        guard let ts = textView.textStorage else { return XCTFail("no storage") }
        let tokens = MarkdownHighlighter.tokenize(md)
        let len = ts.length
        let start = Date()
        ts.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: len))
        ts.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: len))
        for t in tokens where t.range.location + t.range.length <= len {
            ts.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: t.range)
        }
        let ms = Date().timeIntervalSince(start) * 1000
        print("PERF apply(\(len) chars, \(tokens.count) tokens) = \(Int(ms)) ms")
        XCTAssertLessThan(ms, 400, "主线程着色应用太慢")
    }

    /// 真实敲键路径：insertText → 委托回调（onChange / 行号 / 着色调度）的同步耗时。
    /// 旧实现里这一步会连带 1.3s 的全量解析 → 输入卡死；现在只应剩毫秒级。
    @MainActor
    func testTypingLatencyOnLargeDocument() throws {
        let md = bigDocument(lines: 3000)
        let view = MarkdownEditorView(
            text: md, fontSize: 13, glass: 0,
            onChange: { _ in }, onLineChange: { _, _ in },
            fileExtension: "md", revision: 1, textViewRef: .constant(nil))
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 900, height: 600)
        host.layoutSubtreeIfNeeded()
        guard let tv = Self.findTextView(in: host) else {
            return XCTFail("找不到 NSTextView")
        }
        XCTAssertEqual((tv.string as NSString).length, (md as NSString).length)
        // 预热一次（首次布局 / 首次着色调度）
        tv.insertText("x", replacementRange: NSRange(location: 10, length: 0))
        var worst: Double = 0
        var total: Double = 0
        let rounds = 12
        for i in 0..<rounds {
            let at = 2000 + i * 37
            let start = Date()
            tv.insertText("a", replacementRange: NSRange(location: at, length: 0))
            let ms = Date().timeIntervalSince(start) * 1000
            worst = max(worst, ms)
            total += ms
        }
        print("PERF typing(3000 lines) avg=\(Int(total / Double(rounds)))ms worst=\(Int(worst))ms")
        XCTAssertLessThan(worst, 120, "单次敲键同步耗时超过 120ms：输入会明显卡")
    }

    private static func findTextView(in view: NSView) -> NSTextView? {
        if let tv = view as? NSTextView { return tv }
        for sub in view.subviews {
            if let found = findTextView(in: sub) { return found }
        }
        return nil
    }

    /// 视图更新期写 SwiftUI 状态 → 更新风暴（输入法组合中 / store 落后时的"输入卡死"）。
    /// 复现方式：让 NSTextView 的内容领先于绑定值（模拟输入法组合），再触发一次刷新。
    @MainActor
    func testNoUpdateStormWhenViewLeadsStore() throws {
        final class Counter { var onChange = 0; var onLine = 0 }
        let counter = Counter()
        struct Harness: View {
            @State var text: String
            @State var tick = 0
            let counter: Counter
            var body: some View {
                MarkdownEditorView(
                    text: text, fontSize: 13, glass: 0,
                    onChange: { _ in counter.onChange += 1 },
                    onLineChange: { _, _ in counter.onLine += 1 },
                    fileExtension: "md", revision: 1, textViewRef: .constant(nil))
                    .id(tick)
            }
        }
        let harness = Harness(text: "", counter: counter)
        let host = NSHostingView(rootView: harness)
        host.frame = CGRect(x: 0, y: 0, width: 700, height: 400)
        host.layoutSubtreeIfNeeded()
        guard let tv = Self.findTextView(in: host) else { return XCTFail("找不到 NSTextView") }

        // 直接改文本视图（不经过委托）→ 视图内容领先绑定值，模拟输入法组合中的状态
        tv.string = "组合中的中文内容"
        counter.onChange = 0
        counter.onLine = 0
        // 触发若干次宿主刷新：如果 updateNSView 里同步回写状态，会自我激增
        for _ in 0..<5 {
            host.needsLayout = true
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        print("PERF updateStorm onChange=\(counter.onChange) onLine=\(counter.onLine)")
        XCTAssertLessThan(counter.onChange, 12,
                          "视图更新期回写状态导致更新风暴：onChange 被调用 \(counter.onChange) 次")
    }
}

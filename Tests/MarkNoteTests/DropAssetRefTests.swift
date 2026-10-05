import XCTest
import AppKit
@testable import MarkNote

/// 素材从素材库拖进编辑器：**不该因为目标文件类型不同而失效**。
/// 这里用一个最小的 NSDraggingInfo 假件复现拖拽落点，分别验证 .md 与 .cpp。
final class DropAssetRefTests: XCTestCase {

    /// 最小可用的拖拽信息假件：只喂一个纯文本 pasteboard
    private final class FakeDrag: NSObject, NSDraggingInfo {
        let pb = NSPasteboard(name: NSPasteboard.Name("marknote-test-drag"))
        init(text: String, location: NSPoint = .zero) {
            super.init()
            pb.clearContents()
            pb.setString(text, forType: .string)
            self.location = location
        }
        private var location: NSPoint = .zero
        var draggingDestinationWindow: NSWindow? { nil }
        var draggingSourceOperationMask: NSDragOperation { .copy }
        var draggingLocation: NSPoint { location }
        var draggedImageLocation: NSPoint { location }
        var draggedImage: NSImage? { nil }
        var draggingPasteboard: NSPasteboard { pb }
        var draggingSource: Any? { nil }
        var draggingSequenceNumber: Int { 1 }
        var numberOfValidItemsForDrop: Int = 1
        var springLoadingHighlight: NSSpringLoadingHighlight { .none }
        var draggingFormation: NSDraggingFormation = .default
        var animatesToDestination: Bool = false
        var numberOfValidItemsForDropValue = 1
        func slideDraggedImage(to screenPoint: NSPoint) {}
        func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions,
                                    for view: NSView?,
                                    classes: [AnyClass],
                                    searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                    using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
        func resetSpringLoading() {}
    }

    private func makeTextView(ext: String, text: String = "line one\nline two\n") -> MarkdownTextView {
        let tv = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        tv.fileExtension = ext
        tv.string = text
        return tv
    }

    func testAssetRefDropWorksForMarkdownAndCode() {
        let ref = "![照片](img/2026-10-05-photo.png)"
        for ext in ["md", "cpp", "py", "txt"] {
            let tv = makeTextView(ext: ext)
            let drag = FakeDrag(text: ref, location: NSPoint(x: 10, y: 10))
            XCTAssertEqual(tv.draggingEntered(drag), .copy, "\(ext)：拖拽进入应被接受")
            XCTAssertTrue(tv.performDragOperation(drag), "\(ext)：落点应被处理")
            XCTAssertTrue(tv.string.contains(ref), "\(ext)：素材引用应插进正文，实际：\(tv.string)")
        }
    }

    func testVideoAndAttachmentRefDropWorksForCode() {
        let video = "<video src=\"source/mp4/a.mp4\" controls></video>"
        let attach = "@[报告.pdf](source/pdf/报告.pdf)"
        for ref in [video, attach] {
            let tv = makeTextView(ext: "cpp")
            let drag = FakeDrag(text: ref)
            XCTAssertTrue(tv.performDragOperation(drag), "cpp：\(ref.prefix(12))… 应被处理")
            XCTAssertTrue(tv.string.contains(ref), "cpp：\(ref.prefix(12))… 应插入")
        }
    }

    func testPlainTextDropFallsThrough() {
        let tv = makeTextView(ext: "cpp")
        let drag = FakeDrag(text: "普通文本，不是素材引用")
        // 不是素材引用形态 → 不由这条分支消费（交给 AppKit 默认文本拖放）
        XCTAssertFalse(tv.dragConsumedAssetRefForTesting(drag))
    }
}

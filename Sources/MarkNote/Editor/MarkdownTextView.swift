import AppKit
import UniformTypeIdentifiers

/// 增强版 NSTextView：粘贴/拖拽图片时自动存入笔记附件目录，
/// 并在光标处插入 Markdown 图片引用（否则回退默认文本粘贴行为）。
final class MarkdownTextView: NSTextView {

    /// (data, ext) -> 相对笔记目录的引用路径；nil 表示保存失败
    var imageHandler: ((Data, String) -> String?)?
    /// 任意文件 (data, fileName) -> 引用路径；用于非图片文件的粘贴/拖拽
    var attachmentHandler: ((Data, String) -> String?)?

    private static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff"]

    /// 编辑器焦点下 ⌘⌫/⌘⌦（两种退格）也会被文本系统截胡 —— 拦截并转给"删除笔记"命令
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.keyCode == 51 || event.keyCode == 117 {   // 51=Delete(⌫) 117=DeleteForward(⌦)
            NotificationCenter.default.post(name: .deleteNoteRequested, object: nil)
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - 手感：列表延续 / 缩进 / Tab

    override func insertNewline(_ sender: Any?) {
        let text = string as NSString
        let sel = selectedRange()
        guard text.length > 0 else { super.insertNewline(sender); return }
        let lineRange = text.lineRange(for: NSRange(location: min(sel.location, text.length), length: 0))
        let lineText = text.substring(with: lineRange)
        let trimmed = lineText.replacingOccurrences(of: "\n", with: "")
        let ws = trimmed.prefix(while: { $0 == " " || $0 == "\t" })
        let core = trimmed.drop(while: { $0 == " " || $0 == "\t" })
        var indent = String(ws)
        // 列表/引用回车自动延续 Markdown 语法
        if core.hasPrefix("- [ ] ") { indent += "- [ ] " }
        else if core.hasPrefix("- [x] ") { indent += "- [x] " }
        else if core.hasPrefix("- ") || core.hasPrefix("* ") || core.hasPrefix("+ ") {
            indent += (core.hasPrefix("- ") ? "- " : String(core.prefix(2)))
        } else if core.hasPrefix("> ") {
            indent += "> "
        } else if let m = core.range(of: #"^\d+\. "#, options: [.regularExpression]), let num = Int(core[m].dropLast(2)) {
            indent += "\(num + 1). "
        }
        super.insertNewline(sender)
        if !indent.isEmpty {
            insertText(indent, replacementRange: selectedRange())
        }
    }

    /// Tab = 2 空格（轻量缩进）
    override func insertTab(_ sender: Any?) {
        insertText("  ", replacementRange: selectedRange())
    }

    // MARK: - 粘贴

    override func paste(_ sender: Any?) {
        if let (data, ext) = Self.extractBitmap(NSPasteboard.general), handleImage(data, ext: ext) {
            return
        }
        // 非图片文件（Finder 复制 PDF/zip 等）→ 作为附件插入
        if let (data, name) = Self.extractFile(NSPasteboard.general), handleAttachment(data, name: name) {
            return
        }
        super.paste(sender)
    }

    // MARK: - 拖拽

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if Self.dragImageData(sender) != nil {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let (data, ext) = Self.dragImageData(sender), handleImage(data, ext: ext) {
            return true
        }
        if let (data, name) = Self.dragFileData(sender), handleAttachment(data, name: name) {
            return true
        }
        return super.performDragOperation(sender)
    }

    // MARK: - 核心

    /// 保存图片并在光标处插入引用；返回是否已被消费
    private func handleImage(_ data: Data, ext: String?) -> Bool {
        guard let handler = imageHandler else { return false }
        var finalData = data
        var finalExt = ext ?? "png"
        // PNG/TIFF 类位图统一转 PNG（WebView 里渲染稳定；Finder 拖的 jpg 保持原样）
        if ext == "tiff" || ext == "bmp" {
            guard let img = NSImage(data: data),
                  let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return false }
            finalData = png
            finalExt = "png"
        }
        guard let rel = handler(finalData, finalExt) else { return false }
        insertText("![图片](\(rel))", replacementRange: selectedRange())
        return true
    }

    /// 任意文件附件：保存 + 插入链接；返回是否被消费
    private func handleAttachment(_ data: Data, name: String) -> Bool {
        guard let handler = attachmentHandler else { return false }
        guard let rel = handler(data, name) else { return false }
        insertText("[\(name)](\(rel))", replacementRange: selectedRange())
        return true
    }

    // MARK: - 粘贴板解析

    private static func extractBitmap(_ pb: NSPasteboard) -> (Data, String?)? {
        // 1. Finder 复制文件（含图片文件）
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true, .urlReadingContentsConformToTypes: [UTType.image.identifier]]) as? [URL],
           let u = urls.first,
           imageExts.contains(u.pathExtension.lowercased()),
           let d = try? Data(contentsOf: u) {
            return (d, u.pathExtension.lowercased())
        }
        // 2. 位图数据（截图复制通常是 PNG/TIFF）
        for (pt, ext) in [(NSPasteboard.PasteboardType.png, "png"), (NSPasteboard.PasteboardType.tiff, "tiff")] {
            if let d = pb.data(forType: pt) {
                return (d, ext)
            }
        }
        // 3. 现代 provider 型剪贴板（浏览器/聊天工具复制的图片，按 item 逐个探测）
        if let items = pb.pasteboardItems {
            for item in items {
                for (pt, ext) in [(NSPasteboard.PasteboardType.png, "png"), (NSPasteboard.PasteboardType.tiff, "tiff")] {
                    if let d = item.data(forType: pt) {
                        return (d, ext)
                    }
                }
            }
        }
        // 4. NSImage 兜底（任何位图 → 统一转 PNG）
        if let img = NSImage(pasteboard: pb),
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return (png, "png")
        }
        return nil
    }

    private static func dragImageData(_ sender: NSDraggingInfo) -> (Data, String?)? {
        let pb = sender.draggingPasteboard
        if let (data, ext) = extractBitmap(pb) {
            return (data, ext)
        }
        // 应用内拖拽（WebView/资源库等）以 NSImage 形式
        if let img = NSImage(pasteboard: pb),
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return (png, "png")
        }
        return nil
    }

    /// 任意文件（非图片）拖拽提取：返回 (data, fileName)
    private static func dragFileData(_ sender: NSDraggingInfo) -> (Data, String)? {
        let pb = sender.draggingPasteboard
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              let u = urls.first,
              let d = try? Data(contentsOf: u) else { return nil }
        return (d, u.lastPathComponent)
    }

    /// 粘贴板上的文件 URL（非图片）提取
    private static func extractFile(_ pb: NSPasteboard) -> (Data, String)? {
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              let u = urls.first,
              !imageExts.contains(u.pathExtension.lowercased()),
              let d = try? Data(contentsOf: u) else { return nil }
        return (d, u.lastPathComponent)
    }
}

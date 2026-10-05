import SwiftUI
import AppKit

/// 文件类型的外观（图标槽位 / SF Symbol 兜底 / 语言色 / 扩展名标签）——
/// 文件树、标签页、状态栏共用同一套，避免同一个 .cpp 在三个地方长得不一样。
enum FileTypeStyle {

    /// 主题图标槽位（主题包没画这个语言时会回落到 SF Symbol + 语言色）
    static func themeIconKey(for ext: String) -> String { Workspace.themeIconKey(for: ext) }

    /// SF Symbol 兜底图标
    static func symbol(for ext: String) -> String { Workspace.fileSymbol(for: ext) }

    /// 语言色（主题没提供专属图标时用它上色）
    static func tint(for ext: String) -> NSColor {
        let key = Workspace.themeIconKey(for: ext)
        if let hex = languageTint[key] { return color(hex) }
        return NSColor.secondaryLabelColor
    }

    /// 标签页/状态栏显示的扩展名（大写；无扩展名 → nil）
    static func extensionLabel(for noteID: String) -> String? {
        let ext = (noteID as NSString).pathExtension
        guard !ext.isEmpty else { return nil }
        return ext.uppercased()
    }

    /// 语言 → 兜底色（与各语言品牌色相近）
    private static let languageTint: [String: String] = [
        "file.python": "#3B7EA1", "file.javascript": "#C9A227", "file.typescript": "#2F74C0",
        "file.go": "#1FA3B8", "file.rust": "#C1663D", "file.c": "#5B7DB1",
        "file.cpp": "#3F6FD8", "file.csharp": "#8B5CD6", "file.java": "#C0563C",
        "file.kotlin": "#7F52FF", "file.swift": "#E0703A", "file.html": "#D9642F",
        "file.css": "#2C6FB8", "file.vue": "#3FA36B", "file.xml": "#8A8F98",
        "file.json": "#B08A2E", "file.yaml": "#C4536F", "file.shell": "#4E9A5F",
        "file.sql": "#3C8C8C", "file.ruby": "#C43D3D", "file.php": "#6B6FC4",
        "file.lua": "#2C4F9E", "file.asm": "#7A8290", "file.r": "#276DC3",
        "file.data": "#4E9C78", "file.markdown": "#6C8CC7",
        "file.image": "#43A88F", "file.video": "#8A63C4", "file.audio": "#C4708F",
        "file.document": "#7A7F87", "file.archive": "#9A7B4F", "file.other": "#8A8F98",
    ]

    static func color(_ hex: String) -> NSColor {
        var h = hex.replacingOccurrences(of: "#", with: "")
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return .secondaryLabelColor }
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                       green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

/// 文件类型图标：主题给了专属图标就用它（与文件树一致），否则 SF Symbol + 语言色
struct FileTypeIcon: View {
    let ext: String
    var size: CGFloat = 14

    var body: some View {
        Group {
            if let img = themeIconImage(FileTypeStyle.themeIconKey(for: ext), trimmed: true) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: FileTypeStyle.symbol(for: ext))
                    .font(.system(size: size * 0.86))
                    .foregroundStyle(Color(nsColor: FileTypeStyle.tint(for: ext)))
            }
        }
        .frame(width: size, height: size)
    }
}

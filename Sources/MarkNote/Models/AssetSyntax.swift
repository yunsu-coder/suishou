import Foundation

/// 素材语法（素材面板 / 编辑器 / 外部拖入共用）。
///
/// 所有入库与引用入口（面板插入 / 复制 / 拖拽、Finder 拖入、插入附件面板）都走这里，
/// 保证「同一种素材在任何入口写出的语法完全一致」：
/// · 图片 → `![名](路径)` 行内图片
/// · 视频 → `<video src="路径" controls></video>` 预览内嵌播放器
/// · 音频 → `<audio src="路径" controls></audio>` 预览内嵌播放器
/// · 其他（pdf/zip/docx…）→ `@[名](路径)` 附件卡（点击打开）
enum AssetSyntax {

    enum Kind: Equatable {
        case image, video, audio, file
    }

    static func kind(forExt ext: String) -> Kind {
        switch ext.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "avif", "tiff", "tif", "bmp", "svg":
            return .image
        case "mp4", "mov", "m4v", "mv4", "webm", "mkv", "avi":
            return .video
        case "mp3", "m4a", "wav", "flac", "aac", "ogg", "aiff":
            return .audio
        default:
            return .file
        }
    }

    /// 素材引用文本：插入 / 复制 / 拖拽 / 外部拖入共用。
    static func reference(name: String, path: String) -> String {
        let p = escapePath(path)
        switch kind(forExt: (name as NSString).pathExtension) {
        case .image: return "![\(title(name))](\(p))"
        case .video: return "<video src=\"\(p)\" controls></video>"
        case .audio: return "<audio src=\"\(p)\" controls></audio>"
        case .file:  return "@[\(title(name))](\(p))"
        }
    }

    /// 链接路径里的空格 / 括号 / # 等会破坏 Markdown 与附件卡语法解析 → 百分号编码（保留中文，便于阅读）。
    static func escapePath(_ path: String) -> String {
        var out = path
        // % 必须最先编码，避免把后续产生的编码串二次编码
        for (raw, enc) in [("%", "%25"), (" ", "%20"), ("(", "%28"), (")", "%29"),
                           ("#", "%23"), ("[", "%5B"), ("]", "%5D")] {
            out = out.replacingOccurrences(of: raw, with: enc)
        }
        return out
    }

    static func title(_ fileName: String) -> String {
        (fileName as NSString).deletingPathExtension
    }

    /// 块级引用（视频 / 音频 / 附件卡）插入时应独占整行；图片是行内元素。
    static func isBlockReference(_ text: String) -> Bool {
        text.hasPrefix("<video") || text.hasPrefix("<audio") || text.hasPrefix("@[")
    }
}

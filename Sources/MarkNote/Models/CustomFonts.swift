import Foundation
import CoreText

/// 自定义字体库（应用级资源）：导入 → 拷贝 + md5 去重；进程级注册（编辑器 NSFont 可直接选用）；
/// 家族名解析 + data URL 生成（预览 @font-face 通道 —— WKWebView 的 WebContent 进程
/// 看不到宿主进程注册的字体，必须把字体字节推过去）。
enum CustomFonts {
    struct Entry: Identifiable, Equatable {
        let id: String      // 稳定 id = 内容 md5（去重键）
        let family: String  // 家族名（设置选择器的值；NSFont/CSS 都按它来）
        let fileName: String
        /// data URL 的 MIME（按扩展名）
        var mime: String {
            switch (fileName as NSString).pathExtension.lowercased() {
            case "otf": return "font/otf"
            case "ttc": return "font/ttc"
            default: return "font/ttf"
            }
        }
    }

    enum ImportResult {
        case ok(Entry)
        case duplicate(Entry)
        case unsupported
        case unreadable
    }

    static let extensions = ["ttf", "otf", "ttc"]

    /// 字体库目录：~/Library/Application Support/MarkNote/fonts/（app 级资源，随数据目录独立）
    static func libraryDir() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MarkNote/fonts", isDirectory: true)
    }

    /// 扫描库目录：注册 + 解析家族名（坏文件跳过）
    static func loadLibrary(in dir: URL? = nil) -> [Entry] {
        let dir = dir ?? libraryDir()
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        var entries: [Entry] = []
        for f in files where extensions.contains(f.pathExtension.lowercased()) {
            if let e = entry(for: f) { entries.append(e) }
        }
        return entries.sorted { $0.family < $1.family }
    }

    /// 进程级注册：让 NSFont(name:size:) 解析到该家族（重启后由 loadLibrary 重新注册）
    @discardableResult
    static func register(_ file: URL) -> Bool {
        CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
    }

    /// 解析文件 → 家族名 Entry（坏文件 / 空家族返回 nil）
    static func entry(for file: URL) -> Entry? {
        guard let data = try? Data(contentsOf: file),
              let faces = CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor],
              let first = faces.first,
              let family = CTFontDescriptorCopyAttribute(first, kCTFontFamilyNameAttribute) as? String,
              !family.isEmpty else { return nil }
        return Entry(id: NotesStore.md5hex(data), family: family, fileName: file.lastPathComponent)
    }

    /// 导入：拷贝到库目录（md5 命名，内容去重）+ 注册
    static func importFont(from src: URL, into dir: URL? = nil) -> ImportResult {
        let ext = src.pathExtension.lowercased()
        guard extensions.contains(ext) else { return .unsupported }
        guard let data = try? Data(contentsOf: src) else { return .unreadable }
        let md5 = NotesStore.md5hex(data)
        let dir = dir ?? libraryDir()
        // 去重：同内容 → 返回既有条目（不写盘）
        for e in loadLibrary(in: dir) where e.id == md5 { return .duplicate(e) }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(md5 + "." + ext)
            try data.write(to: dest, options: .atomic)
            _ = register(dest)
            guard let e = entry(for: dest) else {
                try? FileManager.default.removeItem(at: dest)
                return .unreadable
            }
            return .ok(e)
        } catch {
            return .unreadable
        }
    }

    /// 删除：注销 + 移除文件
    static func remove(_ entry: Entry, in dir: URL? = nil) {
        let url = (dir ?? libraryDir()).appendingPathComponent(entry.fileName)
        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
        try? FileManager.default.removeItem(at: url)
    }
}

import Foundation
import CoreText

/// 主题字体通道：注册到宿主进程（编辑器 NSFont 可用），并生成 WebContent 的 data URL。
/// 用户不再维护自定义字体库，字体完全随主题包走。
enum ThemeFonts {
    @discardableResult
    static func register(_ file: URL) -> Bool {
        CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
    }

    static func dataURL(for file: URL) -> String? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let ext = file.pathExtension.lowercased()
        let mime = ext == "otf" ? "font/otf" : (ext == "ttc" ? "font/ttc" : "font/ttf")
        return "data:\(mime);base64," + data.base64EncodedString()
    }
}

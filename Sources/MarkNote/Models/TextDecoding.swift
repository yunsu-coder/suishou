import Foundation

/// 文本文件解码 —— 用系统自带的编码探测，避免"中文变 ????"。
///
/// 之前的写法是 `UTF-8 失败 → isoLatin1`：Latin-1 永不失败，于是 Windows/GBK 的
/// 中文文件会被逐字节拆成一堆乱码字符；更糟的是某些路径用
/// `String(decoding:as:)` 会把非法字节直接变成 U+FFFD（就是界面上那些"菱形问号"）。
///
/// 这里按成熟做法来：先 UTF-8（最严），再用 `NSString.stringEncoding(for:)`
/// 让系统判断（它内置 GB18030/Big5/Shift-JIS 等的统计模型），最后才退到
/// 明确列出的编码。返回 nil 表示"实在解不出来"，交给调用方决定怎么提示。
enum TextDecoding {

    static func string(from data: Data) -> String? {
        if data.isEmpty { return "" }
        // 1) UTF-8（带 BOM 也认）
        if let s = String(data: data, encoding: .utf8) { return stripBOM(s) }
        // 2) 系统编码探测（GB18030 / Big5 / Shift-JIS / UTF-16 …）
        var converted: NSString?
        let detected = NSString.stringEncoding(for: data, encodingOptions: nil,
                                               convertedString: &converted, usedLossyConversion: nil)
        if detected != 0, let converted { return stripBOM(converted as String) }
        // 3) 明确候选（系统探测偶尔不给答案）
        func enc(_ cf: CFStringEncodings) -> String.Encoding {
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cf.rawValue)))
        }
        for enc in [String.Encoding.utf16, .utf16LittleEndian, .utf16BigEndian,
                    enc(.GB_18030_2000), enc(.big5), enc(.shiftJIS), .isoLatin1] {
            if let s = String(data: data, encoding: enc) { return stripBOM(s) }
        }
        return nil
    }

    /// 读文件并解码（路径不存在/读不出来 → nil）
    static func string(contentsOf url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return string(from: data)
    }

    /// 该文本是不是"被解码坏掉"的（含替换字符 U+FFFD）——用于导入时如实告知
    static func looksCorrupted(_ s: String) -> Bool {
        s.unicodeScalars.contains { $0.value == 0xFFFD }
    }

    private static func stripBOM(_ s: String) -> String {
        s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s
    }
}

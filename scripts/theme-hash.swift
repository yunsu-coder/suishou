// 计算主题包的 reviewedHash：与 ThemeQuality.contentHash 完全一致。
// 用法: swift scripts/theme-hash.swift <包目录> [主文件名]

import Foundation
import CryptoKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("用法: swift theme-hash.swift <包目录> [theme.json]\n".utf8))
    exit(2)
}
let packageDir = URL(fileURLWithPath: args[1])
let mainFileName = args.count > 2 ? args[2] : "theme.json"
let themeURL = packageDir.appendingPathComponent(mainFileName)

guard let data = try? Data(contentsOf: themeURL),
      let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
    FileHandle.standardError.write(Data("无法解析 \(themeURL.path)\n".utf8))
    exit(3)
}

var files = Set<String>()
let cleaned: [[String: Any]] = raw.map { entry in
    var e = entry
    e.removeValue(forKey: "reviewedHash")
    if let css = e["cssFile"] as? String { files.insert(css) }
    for key in ["uiFont", "codeFont", "displayFont"] {
        if let font = e[key] as? [String: Any], let file = font["file"] as? String {
            files.insert(file)
        }
    }
    if let icons = e["icons"] as? [String: String] {
        for rel in icons.values { files.insert(rel) }
    }
    return e
}

guard let canonical = try? JSONSerialization.data(withJSONObject: cleaned, options: [.sortedKeys]) else {
    FileHandle.standardError.write(Data("规范化失败\n".utf8))
    exit(4)
}

var hasher = SHA256()
hasher.update(data: canonical)
for rel in files.sorted() {
    hasher.update(data: Data(rel.utf8))
    if let asset = try? Data(contentsOf: packageDir.appendingPathComponent(rel)) {
        hasher.update(data: asset)
    } else {
        hasher.update(data: Data("missing".utf8))
    }
}
print(hasher.finalize().map { String(format: "%02x", $0) }.joined())

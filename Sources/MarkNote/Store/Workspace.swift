import Foundation

/// 工作台（VSCode 式本地文件夹）：文件即笔记、资源自动归类、目录即分类。
/// 工作台根 = 用户选定文件夹（多工作台）；引用资源统一自动进 `source/<type>/`。
enum Workspace {

    /// 可在应用内编辑的文本/代码扩展名（VSCode 式：文本即笔记，其余交系统程序）
    static let textExtensions: Set<String> = [
        // Markdown / 文档
        "md", "markdown", "mdown", "mdx", "txt", "rtf", "rst", "log", "csv", "tsv",
        // 代码
        "swift", "m", "mm", "c", "h", "cpp", "hpp", "cc", "mpp", "cs", "java", "kt", "go", "rs",
        "py", "rb", "php", "pl", "lua", "js", "jsx", "ts", "tsx", "mjs", "cjs", "vue", "svelte",
        "html", "htm", "css", "scss", "sass", "less", "styl", "xml", "svg", "plist", "xib", "storyboard",
        "sh", "bash", "zsh", "fish", "sql", "ps1", "bat", "cmd", "vim", "asm", "s", "zig", "nim", "ex", "exs", "erl", "hs",
        // 配置 / 数据
        "json", "jsonc", "yaml", "yml", "toml", "ini", "cfg", "conf", "env", "properties", "gradle", "pom", "mk", "makefile",
        "dockerfile", "gitignore", "gitattributes", "editorconfig", "lock", "lockb", "babelrc", "eslintrc", "prettierrc",
    ]

    /// 是否属于可编辑文本（空扩展名也算 —— 用户创建的无后缀文件）
    static func isEditorText(_ ext: String) -> Bool {
        ext.isEmpty || textExtensions.contains(ext.lowercased())
    }

    /// 文件类型图标（SF Symbol；VSCode 式区分）；插件覆盖优先
    static func fileSymbol(for ext: String) -> String {
        let key = ext.lowercased()
        if let o = PluginManager.shared.fileOverride(for: key), let icon = o.icon, !icon.isEmpty {
            return icon
        }
        switch key {
        case "md", "markdown", "mdown": return "doc.richtext"
        case "txt", "log", "csv", "tsv", "rst": return "doc.plaintext"
        case "json", "jsonc", "yaml", "yml", "toml", "plist", "ini", "cfg", "conf", "properties", "gradle": return "doc.text.magnifyingglass"
        case "html", "htm", "svg", "xml", "xib", "storyboard", "vue", "svelte": return "chevron.left.forwardslash.chevron.right"
        case "css", "scss", "sass", "less", "styl": return "paintbrush"
        case "swift", "m", "mm", "java", "kt", "go", "rs", "c", "cpp", "h", "cs", "rb", "php", "py", "js", "ts", "jsx", "tsx", "sh", "sql": return "chevron.left.forwardslash.chevron.right"
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff", "ico": return "photo"
        case "mp4", "mov", "m4v", "webm", "mkv", "avi": return "film"
        case "mp3", "m4a", "wav", "flac", "aac", "ogg": return "music.note"
        case "pdf": return "doc.richtext"
        case "zip", "rar", "7z", "gz", "tar", "dmg": return "archivebox"
        default:
            return ext.isEmpty ? "doc.text" : "doc"
        }
    }

    /// 注释符号表（⌘/ 按语言切换；未匹配 → "#"）；插件覆盖优先
    static func lineComment(for ext: String) -> String {
        let key = ext.lowercased()
        if let o = PluginManager.shared.fileOverride(for: key), let c = o.comment, !c.isEmpty {
            return c
        }
        switch key {
        case "swift", "m", "mm", "c", "h", "cpp", "hpp", "cc", "mpp", "cs", "java", "kt", "go", "rs",
             "js", "jsx", "ts", "tsx", "mjs", "cjs", "vue", "svelte", "css", "scss", "sass", "less", "styl",
             "php", "pl", "lua", "json", "jsonc", "yaml", "yml", "toml", "plist", "xib", "storyboard", "properties":
            return "//"
        case "html", "htm", "xml", "svg", "md", "markdown", "mdown", "mdx", "vue", "svelte":
            return "<!--"    // 简单行注释符号（md 里用 <!-- 常见；xhtml）
        case "py", "rb", "sh", "bash", "zsh", "fish", "sql", "ps1", "bat", "cmd", "vim", "gradle", "mk", "makefile",
             "dockerfile", "gitignore", "gitattributes", "editorconfig", "ini", "cfg", "conf", "env", "rst", "yaml", "yml":
            return "#"
        default:
            return "#"
        }
    }

    /// 扩展名 → source/<type> 归类（可扩展；未列出 → other）
    static func sourceFolder(for ext: String) -> String {
        switch ext.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff", "svg", "ico": return "image"
        case "doc", "docx", "pages", "rtf", "odt", "wps": return "doc"
        case "pdf": return "pdf"
        case "mp4", "mov", "m4v", "webm", "mkv", "avi": return "mp4"
        case "mp3", "m4a", "wav", "aac", "ogg", "flac": return "audio"
        case "xls", "xlsx", "csv", "numbers", "ods": return "excel"
        case "ppt", "pptx", "key", "odp": return "ppt"
        case "py", "js", "ts", "swift", "rb", "go", "rs", "java", "c", "cpp", "h",
             "cs", "php", "sh", "sql", "json", "yaml", "yml", "toml", "zip", "rar", "7z", "gz", "tar", "dmg": return "code"
        case "md", "markdown", "mdown", "txt": return "md"
        default: return "other"
        }
    }

    /// 资源目标目录（工作台/source/<type>），不存在则创建
    static func ensureSourceDir(_ root: URL, ext: String) -> URL {
        let dir = root
            .appendingPathComponent("source", isDirectory: true)
            .appendingPathComponent(sourceFolder(for: ext), isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 目标目录内唯一文件名（同名自动加序号，防覆盖）
    static func uniqueName(in dir: URL, fileName: String) -> String {
        let fm = FileManager.default
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var name = fileName
        var i = 1
        while fm.fileExists(atPath: dir.appendingPathComponent(name).path) {
            name = ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)"
            i += 1
        }
        return name
    }

    /// 遍历工作台全部文件（跳过隐藏/点目录 → source/ 亦在其中）
    static func walk(_ root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var out: [URL] = []
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { continue }
            out.append(url)
        }
        return out
    }

    /// 相对路径（工作台标识；id 表示法 = 相对路径字符串，去除前导 / ）
    static func relativeID(_ url: URL, root: URL) -> String {
        let rp = url.standardizedFileURL.path.replacingOccurrences(of: root.standardizedFileURL.path + "/", with: "")
        return rp
    }

    /// 相对路径 → 绝对 URL
    static func url(for relativeID: String, root: URL) -> URL {
        root.appendingPathComponent(relativeID)
    }

    /// 笔记标题 = 文件名（去扩展名）
    static func title(for url: URL) -> String {
        (url.lastPathComponent as NSString).deletingPathExtension
    }

    /// 所属目录（分类 id = 相对目录；'' = 根）
    static func folderLabel(for url: URL, root: URL) -> String {
        let dir = url.deletingLastPathComponent().standardizedFileURL
        let r = root.standardizedFileURL
        // 根级文件：目录即根 → 分类为空串（此前会误得绝对路径，导致"var/…"假分类）
        if dir.path == r.path { return "" }
        return Workspace.relativeID(dir, root: r)
    }
}

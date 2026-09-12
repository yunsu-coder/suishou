import Foundation
import AppKit
import CryptoKit

/// 主题质量硬门槛：不达标主题不会进入选择器。
///
/// 规则目标不是“能换色”，而是完整主题体验：
/// 专属字体 + 语义图标 + 专属风格 + 彩蛋 + 特效/动画 + 可读性 + 体积/性能约束。
enum ThemeQuality {
    /// v1 基础槽位。
    static let baseIconKeys: Set<String> = [
        "folder",                    // 工作台
        "puzzlepiece.extension",     // 插件市场入口
        "shippingbox",               // 插件市场页面 / 空状态
        "gearshape",                 // 设置
        "sidebar.left",              // 侧栏显隐
        "magnifyingglass",           // 搜索
        "sparkles",                  // AI
        "clock.arrow.circlepath",    // 版本历史
        "paw",                       // 主题彩蛋
    ]

    /// v2 新增：文件格式 / 文件夹开合 / 颜色层级槽位。
    static let fileIconKeys: Set<String> = [
        "folder.open",
        "file.markdown", "file.code", "file.data", "file.image",
        "file.video", "file.audio", "file.document", "file.archive", "file.other",
    ]

    static func requiredIconKeys(for version: Int) -> Set<String> {
        version >= 2 ? baseIconKeys.union(fileIconKeys) : baseIconKeys
    }

    static func distinctIconKeys(for version: Int) -> [String] {
        version >= 2 ? ["folder"] + fileIconKeys.sorted() : ["folder"]
    }
    static let maxFontBytes = 12 * 1024 * 1024
    static let maxIconBytes = 256 * 1024
    static let maxCSSBytes = 256 * 1024

    /// v4 新增：预览必须吃到的主题变量（缺一个，预览就会出现「默认色」而不是主题色）。
    static let previewVarsV4 = [
        "--surface", "--text-secondary", "--border", "--border-strong", "--accent-soft",
        "--code-bg", "--code-text",
        "--hl-kw", "--hl-str", "--hl-num", "--hl-comment",
        "--note", "--note-bg", "--tip", "--tip-bg", "--warn", "--warn-bg",
        "--danger", "--danger-bg", "--info", "--info-bg",
    ]
    static let highlightKeysV4 = ["--hl-kw", "--hl-str", "--hl-num", "--hl-comment"]
    static let calloutKeysV4 = ["--note", "--tip", "--warn", "--danger", "--info"]

    // ── v5：编辑器 Markdown 语法配色（主题必填，且要有可量化的区分度）──
    /// 内容类：正文级对比度 ≥4.5:1，两两 ΔE ≥ 12
    static let mdContentVarsV5 = [
        "--md-h1", "--md-h2", "--md-h3", "--md-bold", "--md-italic", "--md-code",
        "--md-link", "--md-quote", "--md-math", "--md-highlight", "--md-strike", "--md-insert",
    ]
    /// 主色 6 个：两两 ΔE ≥ 22（标题三级 + 粗体 + 斜体 + 代码）
    static let mdCoreVarsV5 = ["--md-h1", "--md-h2", "--md-h3", "--md-bold", "--md-italic", "--md-code"]
    /// 标记 / 结构类：对比度 ≥3.0:1，且彩度 ≤30（保持安静，不与内容抢色）
    static let mdMarkerVarsV5 = [
        "--md-marker", "--md-url",
        "--md-hr", "--md-table", "--md-fence", "--md-html",
    ]
    /// 可见结构（列表符号 / 序号 / 任务框）：必须是有色相的颜色，不能是灰 —— 否则"看起来没生效"
    static let mdVisibleVarsV5 = ["--md-list", "--md-number", "--md-task"]
    /// 背景类（行内代码底、高亮底）
    static let mdBackgroundVarsV5 = ["--md-code-bg", "--md-highlight-bg"]
    /// 其余语义色（Callout 标记、表头）
    static let mdSemanticVarsV5 = [
        "--md-callout", "--md-table-head",
        // 渲染器支持、编辑器同样要能看出来的语法（覆盖度：一眼确认有没有生效）
        "--md-embed", "--md-kbd", "--md-mention", "--md-emoji",
        "--md-badge", "--md-timeline", "--md-term", "--md-mermaid",
    ]

    static var requiredEditorSyntaxVarsV5: [String] {
        mdContentVarsV5 + mdMarkerVarsV5 + mdVisibleVarsV5 + mdBackgroundVarsV5 + mdSemanticVarsV5
    }

    /// 返回空数组 = 通过；否则为阻止上架的具体原因。
    static func audit(_ spec: ThemeSpec, packageDir: URL, mainFileName: String = "theme.json") -> [String] {
        var issues: [String] = []
        let version = max(1, spec.auditVersion ?? 1)

        // 0. 人工审核：代码质量达标只是必要条件，必须由用户看过设计稿并批准。
        let hash = contentHash(packageDir: packageDir, mainFileName: mainFileName)
        if spec.reviewed != true || spec.reviewedHash == nil || spec.reviewedHash != hash {
            issues.append("等待人工审核（主题内容已变更）")
        }

        // 1. 专属字体：界面/标题至少一套 + 代码一套
        if spec.uiFont == nil && spec.displayFont == nil {
            issues.append("缺少专属界面或标题字体")
        }
        if spec.codeFont == nil {
            issues.append("缺少专属编辑字体（codeFont）")
        }
        for (label, font) in [
            ("界面字体", spec.uiFont),
            ("代码字体", spec.codeFont),
            ("标题字体", spec.displayFont),
        ].compactMap({ $0.1 == nil ? nil : ($0.0, $0.1!) }) {
            let url = packageDir.appendingPathComponent(font.file)
            guard FileManager.default.fileExists(atPath: url.path) else {
                issues.append("\(label)文件不存在：\(font.file)")
                continue
            }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size > maxFontBytes {
                issues.append("\(label)过大（>\(maxFontBytes / 1024 / 1024)MB）")
            }
        }

        // 2. 专属图标：覆盖全部随手语义槽位；未知键视为语义错配，直接拦截。
        let icons = spec.icons ?? [:]
        let requiredKeys = requiredIconKeys(for: version)
        for key in requiredKeys.sorted() where icons[key] == nil {
            issues.append("图标语义未覆盖：\(key)")
        }
        let unknown = Set(icons.keys).subtracting(requiredKeys)
        for key in unknown.sorted() {
            issues.append("图标语义未适配：\(key)")
        }
        if version >= 3 {
            for key in (fileIconKeys.union(["folder"])).sorted() {
                guard let rel = icons[key] else { continue }
                let url = packageDir.appendingPathComponent(rel)
                if let coverage = opaqueCoverage(url), coverage > 0.82 {
                    issues.append("文件/文件夹图标必须使用透明字形，不得加背景底板：\(key)")
                }
            }
        }
        var seen: [String: String] = [:]
        for key in distinctIconKeys(for: version) {
            guard let rel = icons[key] else { continue }
            if let other = seen[rel] {
                issues.append("图标语义复用：\(key) 与 \(other) 使用同一资源（缺少颜色/类型层级）")
            } else {
                seen[rel] = key
            }
        }
        for (key, rel) in icons {
            let url = packageDir.appendingPathComponent(rel)
            guard FileManager.default.fileExists(atPath: url.path) else {
                issues.append("图标缺失：\(key) → \(rel)")
                continue
            }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size > maxIconBytes {
                issues.append("图标过大：\(key)（>\(maxIconBytes / 1024)KB）")
            }
        }

        // 3. 专属彩蛋
        if spec.easterEgg == nil {
            issues.append("缺少专属彩蛋")
        }

        // 4. 专属特效/动画（必须有可执行动效，且尊重减少动态效果）
        if let motion = spec.motion {
            let hasEffect = motion.ambientBubbles == true || motion.ambientPixels == true
                || motion.ambientInk == true || motion.ambientPollen == true || motion.scanlines == true
                || motion.iconBounce == true || motion.tabSpring == true
            if !hasEffect { issues.append("未声明可执行的特效或动画") }
            if motion.respectReduceMotion == false {
                issues.append("动效必须尊重系统“减少动态效果”")
            }
            if let ms = motion.durationMs, ms < 120 || ms > 600 {
                issues.append("动效时长需在 120–600ms 之间")
            }
        } else {
            issues.append("缺少专属特效或动画")
        }

        // 5. CSS 体积 + 可读性（正文/次级文字/强调文字）
        let cssURL = packageDir.appendingPathComponent(spec.cssFile)
        guard let css = try? String(contentsOf: cssURL, encoding: .utf8) else {
            issues.append("CSS 无法读取：\(spec.cssFile)")
            return issues
        }
        if css.utf8.count > maxCSSBytes {
            issues.append("CSS 过大（>\(maxCSSBytes / 1024)KB）")
        }
        if version >= 4 && css.contains("gradient(") {
            issues.append("禁止渐变：CSS 里出现 gradient(")
        }
        let layers = PluginCSS.parse(css)
        var worstText = Double.greatestFiniteMagnitude
        var worstSecondary = Double.greatestFiniteMagnitude
        var worstAccent = Double.greatestFiniteMagnitude
        var resolvedAny = false
        var v4Issues = Set<String>()
        var missingV4Vars = Set<String>()
        var editorIssues = Set<String>()
        var missingEditorVars = Set<String>()
        for variant in ["dawn", "night"] {
            for dark in [false, true] {
                let vars = PluginCSS.vars(layers, variant: variant, dark: dark)
                guard let bg = PluginCSS.color(from: vars["--bg"]) else { continue }
                resolvedAny = true
                if let text = PluginCSS.color(from: vars["--text"]) {
                    worstText = min(worstText, contrast(text, bg))
                }
                if let secondary = PluginCSS.color(from: vars["--text-secondary"]) {
                    worstSecondary = min(worstSecondary, contrast(secondary, bg))
                }
                let accentValue = vars["--accent-ink"] ?? vars["--accent"]
                if let accent = PluginCSS.color(from: accentValue) {
                    worstAccent = min(worstAccent, contrast(accent, bg))
                }
                if version >= 4 {
                    for key in previewVarsV4 where vars[key] == nil {
                        missingV4Vars.insert(key)
                    }
                    // 代码高亮色在代码底上必须可读
                    if let codeBG = PluginCSS.color(from: vars["--code-bg"]) {
                        for key in highlightKeysV4 {
                            guard let token = PluginCSS.color(from: vars[key]) else { continue }
                            let ratio = contrast(token, codeBG)
                            if ratio < 3.0 {
                                v4Issues.insert(String(format: "代码高亮色对比不足：%@ %.2f:1（需 ≥3.0）", key, ratio))
                            }
                        }
                    }
                    // 提示块文字色：按「自身底色叠在纸底上」的真实观感检查
                    for key in calloutKeysV4 {
                        guard let fg = PluginCSS.color(from: vars[key]) else { continue }
                        guard let tint = PluginCSS.color(from: vars[key + "-bg"]),
                              let base = blend(tint, over: bg) else { continue }
                        let ratio = contrast(fg, base)
                        if ratio < 4.0 {
                            v4Issues.insert(String(format: "提示色对比不足：%@ %.2f:1（需 ≥4.0）", key, ratio))
                        }
                    }
                }
                if version >= 5 {
                    // ① 变量齐备
                    missingEditorVars.formUnion(requiredEditorSyntaxVarsV5.filter { vars[$0] == nil })
                    func md(_ key: String) -> NSColor? {
                        vars[key].flatMap { PluginCSS.color(from: $0) }
                    }
                    // ② 对比度：内容 ≥4.5；标记 ≥3.0
                    for key in mdContentVarsV5 + mdSemanticVarsV5 {
                        guard let c = md(key) else { continue }
                        let ratio = contrast(c, bg)
                        if ratio < 4.5 {
                            editorIssues.insert(String(format: "编辑器语法色对比不足：%@ %.2f:1（需 ≥4.5）", key, ratio))
                        }
                    }
                    for key in mdMarkerVarsV5 {
                        guard let c = md(key) else { continue }
                        let ratio = contrast(c, bg)
                        if ratio < 3.0 {
                            editorIssues.insert(String(format: "编辑器标记色对比不足：%@ %.2f:1（需 ≥3.0）", key, ratio))
                        }
                        let chromaValue = chroma(c)
                        if chromaValue > 30 {
                            editorIssues.insert(String(format: "编辑器标记色过艳：%@ 彩度 %.0f（需 ≤30）", key, chromaValue))
                        }
                    }
                    // 列表符号 / 序号 / 任务框：必须有色相（灰的等于没生效）
                    for key in mdVisibleVarsV5 {
                        guard let c = md(key) else { continue }
                        let ratio = contrast(c, bg)
                        if ratio < 4.0 {
                            editorIssues.insert(String(format: "编辑器结构色对比不足：%@ %.2f:1（需 ≥4.0）", key, ratio))
                        }
                        let chromaValue = chroma(c)
                        if chromaValue < 12 {
                            editorIssues.insert(String(format: "编辑器结构色是灰色：%@ 彩度 %.0f（需 ≥12，列表符号必须看得见）", key, chromaValue))
                        }
                    }
                    // ③ 区分度：主色两两 ΔE ≥22；内容色两两 ΔE ≥12
                    let core = mdCoreVarsV5.compactMap { key in md(key).map { (key, $0) } }
                    for i in 0..<core.count {
                        for j in (i + 1)..<core.count where deltaE(core[i].1, core[j].1) < 22 {
                            editorIssues.insert(String(format: "编辑器主色区分不足：%@ ↔ %@ ΔE %.0f（需 ≥22）",
                                                       core[i].0, core[j].0, deltaE(core[i].1, core[j].1)))
                        }
                    }
                    let content = mdContentVarsV5.compactMap { key in md(key).map { (key, $0) } }
                    for i in 0..<content.count {
                        for j in (i + 1)..<content.count where deltaE(content[i].1, content[j].1) < 12 {
                            editorIssues.insert(String(format: "编辑器语法色区分不足：%@ ↔ %@ ΔE %.0f（需 ≥12）",
                                                       content[i].0, content[j].0, deltaE(content[i].1, content[j].1)))
                        }
                    }
                }
            }
        }
        guard resolvedAny else {
            issues.append("缺少 --bg/--text 主题变量")
            return issues
        }
        if worstText < 4.5 { issues.append(String(format: "正文对比度不足 %.2f:1（需 ≥4.5）", worstText)) }
        if worstSecondary < 3.5 { issues.append(String(format: "次级文字对比度不足 %.2f:1（需 ≥3.5）", worstSecondary)) }
        if worstAccent < 4.0 { issues.append(String(format: "强调文字对比度不足 %.2f:1（需 ≥4.0）", worstAccent)) }
        issues.append(contentsOf: v4Issues.sorted())
        if !missingV4Vars.isEmpty {
            issues.append("预览变量缺失：" + missingV4Vars.sorted().joined(separator: "、"))
        }
        issues.append(contentsOf: editorIssues.sorted())
        if !missingEditorVars.isEmpty {
            issues.append("编辑器语法色缺失：" + missingEditorVars.sorted().joined(separator: "、"))
        }

        // 6. v4：标题必须有自己的字体、动效至少两项、图标必须是 ≥64 正方形
        if version >= 4 {
            if !hasHeadingFontRule(css) {
                issues.append("标题未指定专属字体：需要给 .markdown-body h1…h4 声明 font-family")
            }
            if let motion = spec.motion {
                let effects = [motion.ambientBubbles, motion.ambientPixels, motion.ambientInk,
                               motion.ambientPollen, motion.scanlines, motion.iconBounce, motion.tabSpring]
                    .filter { $0 == true }.count
                if effects < 2 { issues.append("动效至少需要 2 项（当前 \(effects) 项）") }
            }
            for (key, rel) in icons {
                let url = packageDir.appendingPathComponent(rel)
                guard let size = pixelSize(url) else { continue }
                if size.width != size.height || size.width < 64 {
                    issues.append("图标尺寸不足：\(key)（\(size.width)×\(size.height)，需 ≥64×64 正方形）")
                }
            }
        }

        return issues
    }

    /// 标题字体规则：h1…h4 所在规则里必须出现 font-family（不要求具体字体名）。
    private static func hasHeadingFontRule(_ css: String) -> Bool {
        let pattern = "h[1-4][^{}]{0,240}\\{[^{}]{0,400}?font-family"
        return css.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// 半透明色叠在底色上的实际颜色（用于提示块背景的真实观感）
    private static func blend(_ color: NSColor, over base: NSColor) -> NSColor? {
        guard let c = color.usingColorSpace(.sRGB), let b = base.usingColorSpace(.sRGB) else { return nil }
        let a = c.alphaComponent
        return NSColor(srgbRed: c.redComponent * a + b.redComponent * (1 - a),
                       green: c.greenComponent * a + b.greenComponent * (1 - a),
                       blue: c.blueComponent * a + b.blueComponent * (1 - a),
                       alpha: 1)
    }

    // MARK: - 感知色差（CIE Lab ΔE76）与彩度

    private static func labComponents(_ color: NSColor) -> (Double, Double, Double)? {
        guard let c = color.usingColorSpace(.sRGB) else { return nil }
        func linear(_ v: CGFloat) -> Double {
            let x = Double(v)
            return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        let r = linear(c.redComponent), g = linear(c.greenComponent), b = linear(c.blueComponent)
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? pow(t, 1.0 / 3.0) : (7.787 * t + 16.0 / 116.0) }
        let fx = f(x), fy = f(y), fz = f(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    /// 感知色差：ΔE 越大越容易分辨（≥22 明显不同，≥12 可分辨）
    static func deltaE(_ a: NSColor, _ b: NSColor) -> Double {
        guard let la = labComponents(a), let lb = labComponents(b) else { return 0 }
        return sqrt(pow(la.0 - lb.0, 2) + pow(la.1 - lb.1, 2) + pow(la.2 - lb.2, 2))
    }

    /// Lab 彩度：≤30 视为「安静的中性色」，用于标记类
    static func chroma(_ color: NSColor) -> Double {
        guard let l = labComponents(color) else { return 0 }
        return sqrt(l.1 * l.1 + l.2 * l.2)
    }

    /// 图标像素尺寸
    private static func pixelSize(_ url: URL) -> (width: Int, height: Int)? {
        guard let image = NSImage(contentsOf: url),
              let rep = NSBitmapImageRep(data: image.tiffRepresentation ?? Data()) else { return nil }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        return (w > 0 && h > 0) ? (w, h) : nil
    }

    private static func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        let l1 = PluginCSS.luminance(a)
        let l2 = PluginCSS.luminance(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// 估算图标不透明覆盖率：>82% 视为整块底板图标（透明字形通常 ≤75%）。
    private static func opaqueCoverage(_ url: URL) -> Double? {
        guard let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        guard w > 0, h > 0 else { return nil }
        let stepX = max(1, w / 32), stepY = max(1, h / 32)
        var opaque = 0, total = 0
        for y in stride(from: 0, to: h, by: stepY) {
            for x in stride(from: 0, to: w, by: stepX) {
                total += 1
                if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.15 {
                    opaque += 1
                }
            }
        }
        return total > 0 ? Double(opaque) / Double(total) : nil
    }

    /// 主题内容哈希：theme.json（去掉 reviewedHash）+ 所有引用资源。
    /// 任何图标/字体/CSS 改动都会改变哈希，使旧审核自动失效。
    static func contentHash(packageDir: URL, mainFileName: String = "theme.json") -> String? {
        let themeURL = packageDir.appendingPathComponent(mainFileName)
        guard let data = try? Data(contentsOf: themeURL),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
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
            return nil
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
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

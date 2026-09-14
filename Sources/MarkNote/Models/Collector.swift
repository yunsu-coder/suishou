import Foundation

// MARK: - 采集需求（卡片式确认的数据模型）

/// 选项目录：每个选项带「中文名 + 英文关键词」，用于界面展示与搜索词拼接。
enum CollectOptions {
    /// 风格（多选）
    static let styles: [(zh: String, en: String)] = [
        ("写实摄影", "photography"), ("电影感", "cinematic"), ("二次元", "anime"),
        ("插画", "illustration"), ("3D 渲染", "3d render"), ("扁平", "flat design"),
        ("极简", "minimal"), ("复古胶片", "retro film"), ("赛博朋克", "cyberpunk"),
        ("蒸汽波", "vaporwave"), ("国潮", "chinese style"), ("水墨", "ink painting"),
        ("水彩", "watercolor"), ("油画", "oil painting"), ("线稿", "line art"),
        ("像素", "pixel art"), ("剪纸", "paper cut"), ("拼贴", "collage"),
        ("科技感", "tech"), ("治愈系", "cozy"),
    ]
    /// 色调（多选）
    static let tones: [(zh: String, en: String)] = [
        ("冷色", "cool tones"), ("暖色", "warm tones"), ("中性", "neutral tones"),
        ("黑白", "black and white"), ("高饱和", "vivid colors"), ("低饱和", "muted colors"),
        ("暗调", "dark moody"), ("明亮", "bright"), ("柔和", "soft light"), ("高对比", "high contrast"),
    ]
    /// 主色（多选）
    static let palette: [(zh: String, en: String)] = [
        ("红", "red"), ("橙", "orange"), ("黄", "yellow"), ("绿", "green"),
        ("青", "teal"), ("蓝", "blue"), ("紫", "purple"), ("粉", "pink"),
        ("棕", "brown"), ("黑", "black"), ("白", "white"), ("灰", "gray"),
    ]
    /// 氛围（多选）
    static let moods: [(zh: String, en: String)] = [
        ("宁静", "calm"), ("活力", "energetic"), ("紧张", "tense"), ("梦幻", "dreamy"),
        ("孤独", "lonely"), ("热闹", "lively"), ("温暖", "warm"), ("冷峻", "cold"),
        ("专业", "professional"), ("可爱", "cute"), ("神秘", "mysterious"), ("未来感", "futuristic"),
    ]
    /// 构图（多选）
    static let compositions: [(zh: String, en: String)] = [
        ("特写", "close-up"), ("半身", "half body"), ("全身", "full body"), ("远景", "wide shot"),
        ("俯拍", "top view"), ("仰拍", "low angle"), ("平视", "eye level"),
        ("居中", "centered"), ("三分法", "rule of thirds"), ("大留白", "lots of negative space"),
        ("满构图", "filled frame"), ("对称", "symmetrical"),
    ]
    /// 画面内容开关（多选）
    static let contents: [(zh: String, en: String)] = [
        ("有人物", "with people"), ("无人", "no people"), ("单人", "one person"), ("多人", "group"),
        ("有动物", "with animals"), ("有文字", "with text"), ("纯色背景", "solid background"),
        ("室内", "indoor"), ("室外", "outdoor"), ("白天", "daytime"), ("夜晚", "night"),
        ("自然", "nature"), ("城市", "city"), ("桌面", "desk"), ("食物", "food"),
    ]
    /// 视频平台（多选）
    static let platforms: [(zh: String, en: String)] = [
        ("哔哩哔哩", "bilibili"), ("抖音", "douyin"), ("快手", "kuaishou"),
        ("YouTube", "youtube"), ("小红书", "xiaohongshu"), ("腾讯视频", "v.qq.com"),
    ]

    /// 标签 → 英文关键词（查不到就用原文）
    static func english(_ label: String, in list: [(zh: String, en: String)]) -> String {
        list.first { $0.zh == label }?.en ?? label
    }
}

/// 单选枚举（存 rawValue，便于 Codable 与 AI 回填）
enum CollectOrientation: String, CaseIterable { case any, landscape, portrait, square
    var label: String { switch self {
        case .any: return _L("不限", "Any"); case .landscape: return _L("横图", "Landscape")
        case .portrait: return _L("竖图", "Portrait"); case .square: return _L("方图", "Square") } }
    var keyword: String { switch self {
        case .any: return ""; case .landscape: return "landscape"; case .portrait: return "portrait"
        case .square: return "square" } }
    var bingFilter: String? { switch self {
        case .any: return nil; case .landscape: return "aspect-wide"
        case .portrait: return "aspect-tall"; case .square: return "aspect-square" } }
}

enum CollectAspect: String, CaseIterable { case any, wide16x9, standard4x3, square1x1, tall9x16, cinema21x9
    var label: String { switch self {
        case .any: return _L("不限", "Any"); case .wide16x9: return "16:9"; case .standard4x3: return "4:3"
        case .square1x1: return "1:1"; case .tall9x16: return "9:16"; case .cinema21x9: return "21:9" } }
    var keyword: String { self == .any ? "" : label }
}

enum CollectMinSize: String, CaseIterable { case any, hd720, fhd1080, qhd1440, uhd2160
    var label: String { switch self {
        case .any: return _L("不限", "Any"); case .hd720: return "≥720p"; case .fhd1080: return "≥1080p"
        case .qhd1440: return "≥2K"; case .uhd2160: return "≥4K" } }
    var keyword: String { switch self {
        case .any: return ""; case .hd720: return "hd"; case .fhd1080: return "1080p"
        case .qhd1440: return "2k"; case .uhd2160: return "4k" } }
    /// 中文搜索词里用的写法（"4K" 比 "≥4K" 更像搜索词）
    var keywordZh: String { switch self {
        case .any: return ""; case .hd720: return "720P"; case .fhd1080: return "1080P"
        case .qhd1440: return "2K"; case .uhd2160: return "4K" } }
    var bingFilter: String? { self == .any ? nil : "imagesize-large" }
}

enum CollectRecency: String, CaseIterable { case any, week, month, year
    var label: String { switch self {
        case .any: return _L("不限", "Any"); case .week: return _L("最近一周", "Past week")
        case .month: return _L("最近一月", "Past month"); case .year: return _L("最近一年", "Past year") } }
    var bingFilter: String? { switch self {
        case .any: return nil; case .week: return "age-lt10080"; case .month: return "age-lt43200"
        case .year: return "age-lt525600" } }
}

enum CollectLicense: String, CaseIterable { case any, commercial, cc0, share
    var label: String { switch self {
        case .any: return _L("不限", "Any"); case .commercial: return _L("可商用", "Commercial")
        case .cc0: return _L("免版权", "CC0"); case .share: return _L("可分享", "Free to share") } }
    var keyword: String { switch self {
        case .any: return ""; case .commercial: return "commercial use"; case .cc0: return "cc0"
        case .share: return "free to share" } }
    var bingFilter: String? { switch self {
        case .any: return nil; case .commercial, .cc0: return "license-L2_L3_L4"
        case .share: return "license-L2_L3_L4_L5_L6" } }
}

enum CollectStrictness: String, CaseIterable { case strict, balanced, loose
    var label: String { switch self {
        case .strict: return _L("严格", "Strict"); case .balanced: return _L("均衡", "Balanced")
        case .loose: return _L("宽松", "Loose") } }
}

enum CollectImageFormat: String, CaseIterable { case any, jpeg, png, webp, gif
    var label: String { switch self {
        case .any: return _L("不限", "Any"); case .jpeg: return "JPEG"; case .png: return "PNG"
        case .webp: return "WebP"; case .gif: return _L("GIF 动图", "GIF") } }
    var keyword: String { switch self {
        case .any: return ""; case .jpeg: return "jpg"; case .png: return "png"
        case .webp: return "webp"; case .gif: return "gif animation" } }
}

enum CollectImageType: String, CaseIterable { case any, photo, illustration, vector, render3d, wallpaper, screenshot
    var label: String { switch self {
        case .any: return _L("不限", "Any"); case .photo: return _L("照片", "Photo")
        case .illustration: return _L("插画", "Illustration"); case .vector: return _L("矢量", "Vector")
        case .render3d: return "3D"; case .wallpaper: return _L("壁纸", "Wallpaper")
        case .screenshot: return _L("截图", "Screenshot") } }
    var bingFilter: String? { switch self {
        case .any: return nil; case .photo: return "photo-photo"; case .illustration: return "photo-clipart"
        case .vector: return "photo-linedrawing"; case .render3d: return "photo-photo"
        case .wallpaper: return "photo-photo"; case .screenshot: return "photo-photo" } }
}

enum CollectVideoDuration: String, CaseIterable { case any, short, medium, long
    var label: String { switch self {
        case .any: return _L("不限", "Any"); case .short: return _L("短视频 <1 分钟", "<1 min")
        case .medium: return _L("中等 1-5 分钟", "1-5 min"); case .long: return _L("长 >5 分钟", ">5 min") } }
    var bingFilter: String? { switch self {
        case .any: return nil; case .short: return "duration-short"
        case .medium: return "duration-medium"; case .long: return "duration-long" } }
}

enum CollectVideoResolution: String, CaseIterable { case any, hd, fhd, uhd
    var label: String { switch self {
        case .any: return _L("不限", "Any"); case .hd: return "≥720p"; case .fhd: return "≥1080p"
        case .uhd: return "≥4K" } }
    var keyword: String { switch self {
        case .any: return ""; case .hd: return "hd"; case .fhd: return "1080p"; case .uhd: return "4k" } }
}

enum CollectVideoAudio: String, CaseIterable { case any, with, without
    var label: String { switch self {
        case .any: return _L("不限", "Any"); case .with: return _L("要有声音", "With audio")
        case .without: return _L("静音", "Muted") } }
    var keyword: String { switch self {
        case .any: return ""; case .with: return "with audio"; case .without: return "no audio" } }
}

enum CollectVideoSubtitle: String, CaseIterable { case any, with, without
    var label: String { switch self {
        case .any: return _L("不限", "Any"); case .with: return _L("要字幕", "With subtitles")
        case .without: return _L("不要字幕", "No subtitles") } }
    var keyword: String { switch self {
        case .any: return ""; case .with: return "subtitles"; case .without: return "no subtitles" } }
}

enum CollectKeywordLang: String, CaseIterable { case both, zh, en
    var label: String { switch self {
        case .both: return _L("中英都要", "Both"); case .zh: return _L("中文", "Chinese")
        case .en: return _L("英文", "English") } }
}

/// 采集需求：AI 解析用户的话填入这些字段，缺失的必填项在卡片上高亮追问，填齐才允许采集。
/// 选项分五组：基本 / 风格 / 画面 / 来源与筛选 / 入库（另加图片、视频专属项）。
struct CollectRequest: Codable, Equatable {
    // —— 基本 ——
    var kind: String?                      // "image" / "video"，必填
    var subject: String?                   // 主题，必填
    var usage: String?                     // 用途
    var count: Int = 8                     // 想要的数量 1...60
    var avoid: String?                     // 明确不要的
    var queries: [String] = []             // AI 生成的关键词（优先于自动拼接）
    var keywordLang: String = CollectKeywordLang.both.rawValue

    // —— 风格 ——
    var styles: [String] = []
    var styleNote: String?                 // 自由补充

    // —— 画面 ——
    var orientation: String = CollectOrientation.any.rawValue
    var aspect: String = CollectAspect.any.rawValue
    var minSize: String = CollectMinSize.any.rawValue
    var tones: [String] = []
    var palette: [String] = []
    var moods: [String] = []
    var compositions: [String] = []
    var contentFlags: [String] = []
    var needTextSpace = false              // 需要留白放文字
    var noWatermark = true                 // 不要带水印
    var transparent = false                // 透明背景（图片）

    // —— 来源与筛选 ——
    var strictness: String = CollectStrictness.balanced.rawValue
    var recency: String = CollectRecency.any.rawValue
    var license: String = CollectLicense.any.rawValue
    var siteFilter: String?                // 只看这些站点（逗号分隔域名）
    var excludeSites: String?              // 排除这些站点
    var safeSearch = true
    var platforms: [String] = []           // 视频平台偏好

    // —— 图片专属 ——
    var imageFormat: String = CollectImageFormat.any.rawValue
    var imageType: String = CollectImageType.any.rawValue

    // —— 视频专属 ——
    var videoDuration: String = CollectVideoDuration.any.rawValue
    var videoResolution: String = CollectVideoResolution.any.rawValue
    var videoAudio: String = CollectVideoAudio.any.rawValue
    var videoSubtitle: String = CollectVideoSubtitle.any.rawValue

    // —— 入库（命名/目录沿用工作台约定：source/image 下「日期-描述」）——
    var skipDuplicates = true              // 本次采集里同链接跳过
    var maxImport: Int = 20                // 本次最多入库

    /// 必填但还缺的字段（卡片据此高亮追问）。
    var missing: [String] {
        var out: [String] = []
        if kind == nil { out.append("kind") }
        if (subject ?? "").trimmingCharacters(in: .whitespaces).isEmpty { out.append("subject") }
        return out
    }

    var isReady: Bool { missing.isEmpty }

    // MARK: 搜索词与筛选参数

    /// 关键词（中文侧）：主题 + 已选选项
    func chineseQuery() -> String {
        var parts: [String] = []
        if let subject, !subject.isEmpty { parts.append(subject) }
        parts.append(contentsOf: styles)
        if let styleNote, !styleNote.isEmpty { parts.append(styleNote) }
        parts.append(contentsOf: tones)
        parts.append(contentsOf: palette.map { $0 + "色" })
        parts.append(contentsOf: moods)
        parts.append(contentsOf: compositions)
        parts.append(contentsOf: contentFlags)
        let o = CollectOrientation(rawValue: orientation) ?? .any
        if o != .any { parts.append(o.label) }
        let size = CollectMinSize(rawValue: minSize) ?? .any
        if !size.keywordZh.isEmpty { parts.append(size.keywordZh) }
        if aspect != CollectAspect.any.rawValue { parts.append(aspect) }
        if let usage, !usage.isEmpty { parts.append(usage) }
        if noWatermark { parts.append("无水印") }
        return parts.joined(separator: " ")
    }

    /// 关键词（英文侧）：给公开站点用，命中率更高
    func englishQuery() -> String {
        var parts: [String] = []
        if let subject, !subject.isEmpty { parts.append(subject) }
        parts.append(contentsOf: styles.map { CollectOptions.english($0, in: CollectOptions.styles) })
        parts.append(contentsOf: tones.map { CollectOptions.english($0, in: CollectOptions.tones) })
        parts.append(contentsOf: palette.map { CollectOptions.english($0, in: CollectOptions.palette) })
        parts.append(contentsOf: moods.map { CollectOptions.english($0, in: CollectOptions.moods) })
        parts.append(contentsOf: compositions.map { CollectOptions.english($0, in: CollectOptions.compositions) })
        parts.append(contentsOf: contentFlags.map { CollectOptions.english($0, in: CollectOptions.contents) })
        parts.append(contentsOf: platforms.map { CollectOptions.english($0, in: CollectOptions.platforms) })
        let o = CollectOrientation(rawValue: orientation) ?? .any
        if !o.keyword.isEmpty { parts.append(o.keyword) }
        let size = CollectMinSize(rawValue: minSize) ?? .any
        if !size.keyword.isEmpty { parts.append(size.keyword) }
        if aspect != CollectAspect.any.rawValue { parts.append(aspect) }
        if let usage, !usage.isEmpty { parts.append(usage) }
        if needTextSpace { parts.append("copy space") }
        if noWatermark { parts.append("no watermark") }
        if kind == "video" {
            let r = CollectVideoResolution(rawValue: videoResolution) ?? .any
            if !r.keyword.isEmpty { parts.append(r.keyword) }
            let a = CollectVideoAudio(rawValue: videoAudio) ?? .any
            if !a.keyword.isEmpty { parts.append(a.keyword) }
            let s = CollectVideoSubtitle(rawValue: videoSubtitle) ?? .any
            if !s.keyword.isEmpty { parts.append(s.keyword) }
        } else {
            let f = CollectImageFormat(rawValue: imageFormat) ?? .any
            if !f.keyword.isEmpty { parts.append(f.keyword) }
            let l = CollectLicense(rawValue: license) ?? .any
            if !l.keyword.isEmpty { parts.append(l.keyword) }
        }
        return parts.joined(separator: " ")
    }

    /// 生成搜索词：AI 关键词优先；否则按「关键词语言」拼中文 / 英文 / 两者
    func composedQueries() -> [String] {
        if !queries.isEmpty { return queries }
        let lang = CollectKeywordLang(rawValue: keywordLang) ?? .both
        var out: [String] = []
        if lang == .zh || lang == .both { out.append(chineseQuery()) }
        if lang == .en || lang == .both { out.append(englishQuery()) }
        return out.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Bing 图片筛选参数（qft）：尺寸 / 方向 / 类型 / 授权 / 时效
    func imageFilterParams() -> [String] {
        var filters: [String] = []
        if let f = (CollectMinSize(rawValue: minSize) ?? .any).bingFilter { filters.append(f) }
        if let f = (CollectOrientation(rawValue: orientation) ?? .any).bingFilter { filters.append(f) }
        if let f = (CollectImageType(rawValue: imageType) ?? .any).bingFilter { filters.append(f) }
        if let f = (CollectLicense(rawValue: license) ?? .any).bingFilter { filters.append(f) }
        if let f = (CollectRecency(rawValue: recency) ?? .any).bingFilter { filters.append(f) }
        if transparent { filters.append("photo-transparent") }
        return filters
    }

    /// Bing 视频筛选参数（qft）：时长
    func videoFilterParams() -> [String] {
        var filters: [String] = []
        if let f = (CollectVideoDuration(rawValue: videoDuration) ?? .any).bingFilter { filters.append(f) }
        return filters
    }

    /// 站点限定/排除（拼进搜索词，公开站点通用做法）
    func siteClauses() -> String {
        var parts: [String] = []
        let include = (siteFilter ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !include.isEmpty { parts.append("(" + include.map { "site:\($0)" }.joined(separator: " OR ") + ")") }
        let exclude = (excludeSites ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        parts.append(contentsOf: exclude.map { "-site:\($0)" })
        return parts.joined(separator: " ")
    }

    /// 最终交给搜索的查询串（含站点限定）
    func searchQueries() -> [String] {
        let base = composedQueries()
        let clause = siteClauses()
        guard !clause.isEmpty else { return base }
        return base.map { $0 + " " + clause }
    }

    /// 候选是否满足硬性筛选（严格模式：不满足就丢；宽松模式：只作排序）
    func accepts(_ c: CollectCandidate) -> Bool {
        guard strictness == CollectStrictness.strict.rawValue else { return true }
        if noWatermark, let t = c.title.lowercased().contains("watermark") ? c.title : nil, !t.isEmpty { return false }
        return true
    }

    /// 「选项总结出来的提示词」：把卡片上的选择用人话拼成一句，便于回看/复用/分享。
    func promptSummary() -> String {
        let kindText = kind == "video" ? _L("视频", "video") : _L("图片", "images")
        var head = _L("找 \(count) 个\(kindText)", "Find \(count) \(kindText)")
        if let subject, !subject.isEmpty { head += "：" + subject }
        var details: [String] = []
        if let usage, !usage.isEmpty { details.append(_L("用途", "usage") + " " + usage) }
        if !styles.isEmpty { details.append(styles.joined(separator: "/")) }
        if let styleNote, !styleNote.isEmpty { details.append(styleNote) }
        let o = CollectOrientation(rawValue: orientation) ?? .any
        if o != .any { details.append(o.label) }
        if aspect != CollectAspect.any.rawValue { details.append(aspect) }
        let size = CollectMinSize(rawValue: minSize) ?? .any
        if !size.keywordZh.isEmpty { details.append("≥" + size.keywordZh) }
        if !tones.isEmpty { details.append(_L("色调", "tone") + " " + tones.joined(separator: "/")) }
        if !palette.isEmpty { details.append(_L("主色", "color") + " " + palette.joined(separator: "/")) }
        if !moods.isEmpty { details.append(_L("氛围", "mood") + " " + moods.joined(separator: "/")) }
        if !compositions.isEmpty { details.append(_L("构图", "composition") + " " + compositions.joined(separator: "/")) }
        if !contentFlags.isEmpty { details.append(contentFlags.joined(separator: "/")) }
        if needTextSpace { details.append(_L("要留白", "copy space")) }
        if noWatermark { details.append(_L("无水印", "no watermark")) }
        if transparent { details.append(_L("透明底", "transparent")) }
        if kind == "video" {
            if let d = CollectVideoDuration(rawValue: videoDuration), d != .any { details.append(d.label) }
            if let r = CollectVideoResolution(rawValue: videoResolution), r != .any { details.append(r.label) }
            if let a = CollectVideoAudio(rawValue: videoAudio), a != .any { details.append(a.label) }
            if let s = CollectVideoSubtitle(rawValue: videoSubtitle), s != .any { details.append(s.label) }
            if !platforms.isEmpty { details.append(platforms.joined(separator: "/")) }
        } else {
            if let f = CollectImageFormat(rawValue: imageFormat), f != .any { details.append(f.label) }
            if let t = CollectImageType(rawValue: imageType), t != .any { details.append(t.label) }
        }
        if let l = CollectLicense(rawValue: license), l != .any { details.append(l.label) }
        if let r = CollectRecency(rawValue: recency), r != .any { details.append(r.label) }
        if let s = CollectStrictness(rawValue: strictness), s != .balanced { details.append(_L("筛选", "filter") + " " + s.label) }
        if let site = siteFilter, !site.isEmpty { details.append(_L("只看", "only") + " " + site) }
        if let site = excludeSites, !site.isEmpty { details.append(_L("排除", "exclude") + " " + site) }
        if let avoid, !avoid.isEmpty { details.append(_L("不要", "avoid") + " " + avoid) }
        guard !details.isEmpty else { return head }
        return head + "（" + details.joined(separator: " · ") + "）"
    }
}

// MARK: - 采集历史（提示词记录：手动输入 + 选项总结）

/// 一条采集历史：既有用户手打的提示词，也有「选项总结出来的提示词」，
/// 还保留完整需求（点一下就能整张卡恢复，直接复用）。
struct CollectHistoryEntry: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    /// 用户手打的提示词（可能为空 —— 纯手工勾选时没有这句话）
    var text: String = ""
    /// 选项总结出来的提示词（人话摘要）
    var summary: String = ""
    /// 实际使用的搜索词（中/英各一条）
    var queries: [String] = []
    /// 完整需求，用于「再用一次」
    var request: CollectRequest = CollectRequest()
    var createdAt: Date = Date()
    /// 这次实际入库了几个（采集结束后回填）
    var importedCount: Int = 0

    var displayTitle: String {
        if let s = request.subject, !s.isEmpty { return s }
        let first = text.split(separator: "\n").first.map(String.init) ?? ""
        return first.isEmpty ? summary : first
    }

    var kindBadge: String {
        request.kind == "video" ? _L("视频", "Video") : _L("图片", "Image")
    }
}

/// 历史记录存取：按**工作台**分开存（不写进工作台目录，符合插件隔离规则），
/// 路径为 `~/Library/Application Support/MarkNote/collector-history/<hash>.json`。
enum CollectHistoryStore {
    static let limit = 50

    static func defaultBaseDir() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MarkNote/collector-history", isDirectory: true)
    }

    /// 工作台路径 → 稳定文件名（含末级目录名，便于人眼辨认）
    static func fileURL(workspace: URL, baseDir: URL? = nil) -> URL {
        let base = baseDir ?? defaultBaseDir()
        var hash: UInt64 = 14_695_981_039_346_656_037   // FNV-1a
        for b in workspace.path.utf8 { hash = (hash ^ UInt64(b)) &* 1_099_511_628_211 }
        let tail = workspace.lastPathComponent.replacingOccurrences(
            of: #"[^A-Za-z0-9\u4e00-\u9fa5_-]"#, with: "-", options: .regularExpression)
        return base.appendingPathComponent("\(tail)-\(String(hash, radix: 16)).json")
    }

    static func load(workspace: URL, baseDir: URL? = nil) -> [CollectHistoryEntry] {
        let url = fileURL(workspace: workspace, baseDir: baseDir)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([CollectHistoryEntry].self, from: data)) ?? []
    }

    @discardableResult
    static func save(_ entries: [CollectHistoryEntry], workspace: URL, baseDir: URL? = nil) -> Bool {
        let url = fileURL(workspace: workspace, baseDir: baseDir)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(Array(entries.prefix(limit))) else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// 追加一条：同一「提示词 + 选项摘要」视为同一条，更新为最新（时间/结果），并裁到上限。
    static func adding(_ entry: CollectHistoryEntry, to entries: [CollectHistoryEntry]) -> [CollectHistoryEntry] {
        var list = entries.filter { !($0.text == entry.text && $0.summary == entry.summary) }
        list.insert(entry, at: 0)
        return Array(list.prefix(limit))
    }
}

// MARK: - 候选素材

struct CollectCandidate: Identifiable, Equatable {
    let id: String
    let kind: String              // "image" / "video"
    let title: String
    let thumbURL: URL
    let fullURL: URL?             // 图片原图
    let pageURL: URL?             // 来源页
    let duration: String?         // 视频时长（"03:24"）
    /// 视频直链（mp4/webm/m3u8…）：有就能在采集面板里直接播放
    var videoURL: URL? = nil
    var selected: Bool = false

    /// 媒体直链判定：后缀像视频文件、或本来就没有页面（murl 即媒体）
    static func looksLikeMediaURL(_ s: String) -> Bool {
        let lower = s.lowercased()
        let exts = [".mp4", ".webm", ".mov", ".m4v", ".mkv", ".m3u8", ".flv", ".avi", ".ts"]
        if exts.contains(where: lower.contains) { return true }
        return false
    }
}

// MARK: - Bing 搜索客户端（直连可用，无需 API key；只搜用户明确给出的关键词）

enum CollectorSearch {
    private static let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    /// 图片搜索：cn.bing.com/images/async —— 返回 m="{...}" JSON 卡片
    /// - Parameter filters: Bing `qft` 筛选（尺寸/方向/类型/授权/时效，来自需求选项）
    static func searchImages(query: String, count: Int = 24,
                             filters: [String] = [], safeSearch: Bool = true) async -> [CollectCandidate] {
        guard var comp = URLComponents(string: "https://cn.bing.com/images/async") else { return [] }
        var items: [URLQueryItem] = [
            .init(name: "q", value: query),
            .init(name: "first", value: "0"),
            .init(name: "count", value: "\(max(8, count))"),
            .init(name: "mmasync", value: "1"),
        ]
        if !filters.isEmpty {
            items.append(.init(name: "qft", value: filters.map { "+filterui:" + $0 }.joined()))
        }
        if safeSearch { items.append(.init(name: "adlt", value: "strict")) }
        comp.queryItems = items
        guard let url = comp.url, let html = await fetch(url) else { return [] }
        return parseImages(html)
    }

    /// 视频搜索：cn.bing.com/videos/search —— 返回 mmeta="{...}" JSON 卡片（须带 first/count 参数才有多条）
    static func searchVideos(query: String, count: Int = 24,
                             filters: [String] = [], safeSearch: Bool = true) async -> [CollectCandidate] {
        guard var comp = URLComponents(string: "https://cn.bing.com/videos/search") else { return [] }
        var items: [URLQueryItem] = [
            .init(name: "q", value: query),
            .init(name: "first", value: "1"),
            .init(name: "count", value: "\(max(8, count))"),
            .init(name: "FORM", value: "HDRSC3"),
        ]
        if !filters.isEmpty {
            items.append(.init(name: "qft", value: filters.map { "+filterui:" + $0 }.joined()))
        }
        if safeSearch { items.append(.init(name: "adlt", value: "strict")) }
        comp.queryItems = items
        guard let url = comp.url, let html = await fetch(url) else { return [] }
        return parseVideos(html)
    }

    static func fetch(_ url: URL) async -> String? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: 解析（独立出来便于离线测试）

    /// 图片：`m="{&quot;murl&quot;:…}"`（a.iusc 卡片）
    static func parseImages(_ html: String) -> [CollectCandidate] {
        var out: [CollectCandidate] = []
        for raw in captures(pattern: #"class="iusc"[^>]*m="([^"]+)""#, in: html) {
            guard let dict = jsonFromEscaped(raw),
                  let murl = dict["murl"] as? String, let full = URL(string: murl),
                  let turl = dict["turl"] as? String, let thumb = URL(string: turl) else { continue }
            let title = (dict["t"] as? String) ?? (dict["desc"] as? String) ?? full.lastPathComponent
            let page = (dict["purl"] as? String).flatMap(URL.init(string:))
            out.append(CollectCandidate(id: murl, kind: "image", title: title,
                                        thumbURL: thumb, fullURL: full, pageURL: page,
                                        duration: nil))
        }
        return dedupe(out)
    }

    /// 视频：`mmeta="{&quot;murl&quot;:…,&quot;turl&quot;:…}"`（turl 缩略图 / murl 视频页 / vt 标题 / du 时长）
    static func parseVideos(_ html: String) -> [CollectCandidate] {
        var out: [CollectCandidate] = []
        for raw in captures(pattern: #"mmeta="([^"]+)""#, in: html) {
            guard let dict = jsonFromEscaped(raw),
                  let turl = dict["turl"] as? String, let thumb = URL(string: turl) else { continue }
            let murl = dict["murl"] as? String
            let pg = dict["pgurl"] as? String
            // murl 是媒体直链时留着播放；页面优先 pgurl，其次才用 murl
            let mediaURL = murl.flatMap { CollectCandidate.looksLikeMediaURL($0) ? URL(string: $0) : nil }
            let pageStr = pg ?? murl
            guard let pageStr, let page = URL(string: pageStr) else { continue }
            let title = (dict["vt"] as? String) ?? (dict["vth"] as? String) ?? thumb.lastPathComponent
            out.append(CollectCandidate(id: pageStr, kind: "video", title: title,
                                        thumbURL: thumb, fullURL: nil, pageURL: page,
                                        duration: (dict["du"] as? String), videoURL: mediaURL))
        }
        return dedupe(out)
    }

    /// HTML 里 `&quot;` 转义过的 JSON 属性 → 字典
    static func jsonFromEscaped(_ raw: String) -> [String: Any]? {
        let un = unescape(raw)
        guard let data = un.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
    }

    private static func captures(pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap {
            $0.numberOfRanges > 1 ? ns.substring(with: $0.range(at: 1)) : nil
        }
    }

    private static func dedupe(_ list: [CollectCandidate]) -> [CollectCandidate] {
        var seen = Set<String>()
        return list.filter { seen.insert($0.id).inserted }
    }
}

// MARK: - AI 需求解析（把用户的话翻译成 CollectRequest）

enum CollectorIntent {
    /// 用 LLM 把自然语言解析为需求字段；未配置 key 或解析失败 → 返回 nil（走纯手填表单）。
    static func parse(_ text: String, current: CollectRequest) async -> CollectRequest? {
        guard LLM.configured else { return nil }
        let system = """
        你是素材采集需求解析器。把用户的话解析成 JSON（只输出 JSON，不要解释）：
        {"kind":"image|video 或 null","subject":"主题（具体名词，如 赛博朋克霓虹街道；无法确定给 null）",
         "usage":"用途（封面/配图/视频素材/参考；不确定给 null）",
         "styleNote":"风格自由补充（如 雨夜霓虹反射；不确定 null）",
         "styles":["从这些里选：\(CollectOptions.styles.map(\.zh).joined(separator: " / "))"],
         "tones":["从这些里选：\(CollectOptions.tones.map(\.zh).joined(separator: " / "))"],
         "palette":["从这些里选：\(CollectOptions.palette.map(\.zh).joined(separator: " / "))"],
         "moods":["从这些里选：\(CollectOptions.moods.map(\.zh).joined(separator: " / "))"],
         "compositions":["从这些里选：\(CollectOptions.compositions.map(\.zh).joined(separator: " / "))"],
         "contentFlags":["从这些里选：\(CollectOptions.contents.map(\.zh).joined(separator: " / "))"],
         "platforms":["视频平台，从这些里选：\(CollectOptions.platforms.map(\.zh).joined(separator: " / "))"],
         "orientation":"any|landscape|portrait|square","minSize":"any|hd720|fhd1080|qhd1440|uhd2160",
         "imageType":"any|photo|illustration|vector|render3d|wallpaper|screenshot",
         "imageFormat":"any|jpeg|png|webp|gif","license":"any|commercial|cc0|share",
         "videoDuration":"any|short|medium|long","videoResolution":"any|hd|fhd|uhd",
         "videoAudio":"any|with|without","videoSubtitle":"any|with|without",
         "recency":"any|week|month|year","strictness":"strict|balanced|loose",
         "needTextSpace":true/false,"noWatermark":true/false,"transparent":true/false,
         "count":数字或null,"avoid":"明确不要的东西或null",
         "queries":["2-3 条搜索关键词，中英文各一条"]}
        规则：
        1. subject 必须贴近用户实际意图，不要泛化；
        2. 用户没提的字段给 null / 空数组，不要编造；
        3. 多选字段只能从上面给的候选里挑（中文原样），挑不到就不放；
        4. 用户说「横图/竖图/方图」→ orientation；说「4K/高清」→ minSize 或 videoResolution；
           说「无水印」→ noWatermark=true；说「要放标题的位置」→ needTextSpace=true；
           说「最近一个月内」→ recency=month；说「可商用」→ license=commercial。
        """
        let user = "用户输入：\(text)\n（已有需求：\(describe(current))）"
        guard let reply = try? await LLM.complete(system: system, user: user) else { return nil }
        let jsonText = extractJSON(reply)
        guard let data = jsonText.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var r = current
        if let k = obj["kind"] as? String, k == "image" || k == "video" { r.kind = k }
        if let s = obj["subject"] as? String, !s.isEmpty, s.lowercased() != "null" { r.subject = s }
        if let u = obj["usage"] as? String, !u.isEmpty, u.lowercased() != "null" { r.usage = u }
        if let st = obj["styleNote"] as? String, !st.isEmpty, st.lowercased() != "null" { r.styleNote = st }
        if let v = obj["style"] as? String, !v.isEmpty, v.lowercased() != "null" { r.styleNote = v }
        func pick(_ key: String, _ allowed: [(zh: String, en: String)]) -> [String] {
            guard let list = obj[key] as? [String] else { return [] }
            let names = Set(allowed.map(\.zh))
            return list.filter { names.contains($0) }
        }
        let styles = pick("styles", CollectOptions.styles); if !styles.isEmpty { r.styles = styles }
        let tones = pick("tones", CollectOptions.tones); if !tones.isEmpty { r.tones = tones }
        let palette = pick("palette", CollectOptions.palette); if !palette.isEmpty { r.palette = palette }
        let moods = pick("moods", CollectOptions.moods); if !moods.isEmpty { r.moods = moods }
        let comps = pick("compositions", CollectOptions.compositions); if !comps.isEmpty { r.compositions = comps }
        let flags = pick("contentFlags", CollectOptions.contents); if !flags.isEmpty { r.contentFlags = flags }
        let platforms = pick("platforms", CollectOptions.platforms); if !platforms.isEmpty { r.platforms = platforms }
        func raw(_ key: String, _ allowed: [String]) -> String? {
            guard let v = obj[key] as? String, allowed.contains(v) else { return nil }
            return v
        }
        if let v = raw("orientation", CollectOrientation.allCases.map(\.rawValue)) { r.orientation = v }
        if let v = raw("minSize", CollectMinSize.allCases.map(\.rawValue)) { r.minSize = v }
        if let v = raw("imageType", CollectImageType.allCases.map(\.rawValue)) { r.imageType = v }
        if let v = raw("imageFormat", CollectImageFormat.allCases.map(\.rawValue)) { r.imageFormat = v }
        if let v = raw("license", CollectLicense.allCases.map(\.rawValue)) { r.license = v }
        if let v = raw("videoDuration", CollectVideoDuration.allCases.map(\.rawValue)) { r.videoDuration = v }
        if let v = raw("videoResolution", CollectVideoResolution.allCases.map(\.rawValue)) { r.videoResolution = v }
        if let v = raw("videoAudio", CollectVideoAudio.allCases.map(\.rawValue)) { r.videoAudio = v }
        if let v = raw("videoSubtitle", CollectVideoSubtitle.allCases.map(\.rawValue)) { r.videoSubtitle = v }
        if let v = raw("recency", CollectRecency.allCases.map(\.rawValue)) { r.recency = v }
        if let v = raw("strictness", CollectStrictness.allCases.map(\.rawValue)) { r.strictness = v }
        if let v = obj["needTextSpace"] as? Bool { r.needTextSpace = v }
        if let v = obj["noWatermark"] as? Bool { r.noWatermark = v }
        if let v = obj["transparent"] as? Bool { r.transparent = v }
        if let c = obj["count"] as? Int { r.count = max(1, min(60, c)) }
        if let av = obj["avoid"] as? String, !av.isEmpty, av.lowercased() != "null" { r.avoid = av }
        if let qs = obj["queries"] as? [String] { r.queries = qs.filter { !$0.isEmpty } }
        return r
    }

    static func describe(_ r: CollectRequest) -> String {
        var parts: [String] = []
        if let k = r.kind { parts.append("类型=\(k)") }
        if let s = r.subject { parts.append("主题=\(s)") }
        if let u = r.usage { parts.append("用途=\(u)") }
        if let st = r.styleNote { parts.append("风格补充=\(st)") }
        if !r.styles.isEmpty { parts.append("风格=\(r.styles.joined(separator: "/"))") }
        if !r.tones.isEmpty { parts.append("色调=\(r.tones.joined(separator: "/"))") }
        if !r.palette.isEmpty { parts.append("主色=\(r.palette.joined(separator: "/"))") }
        if !r.moods.isEmpty { parts.append("氛围=\(r.moods.joined(separator: "/"))") }
        if !r.compositions.isEmpty { parts.append("构图=\(r.compositions.joined(separator: "/"))") }
        if !r.contentFlags.isEmpty { parts.append("内容=\(r.contentFlags.joined(separator: "/"))") }
        if !r.platforms.isEmpty { parts.append("平台=\(r.platforms.joined(separator: "/"))") }
        if let o = CollectOrientation(rawValue: r.orientation), o != .any { parts.append("方向=\(o.label)") }
        if let m = CollectMinSize(rawValue: r.minSize), m != .any { parts.append("尺寸=\(m.label)") }
        if r.noWatermark { parts.append("无水印") }
        if r.needTextSpace { parts.append("要留白") }
        return parts.isEmpty ? "（空）" : parts.joined(separator: "，")
    }

    private static func extractJSON(_ reply: String) -> String {
        if let s = reply.firstIndex(of: "{"), let e = reply.lastIndex(of: "}") {
            return String(reply[s...e])
        }
        return reply
    }
}

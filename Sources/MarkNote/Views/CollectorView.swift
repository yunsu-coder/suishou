import SwiftUI

/// 素材采集面板（视图插件 `collector` 的内置渲染器）。
///
/// 流程（老规矩：先签合同再干活）：
/// 一句话需求 → AI 解析成需求卡片 → 缺字段高亮追问 → 开工确认 → 搜索 → 候选勾选 → 入库。
/// 结果不自动落地：用户勾选哪些、哪些才下载。
struct CollectorView: View {
    @Environment(NotesStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    enum Stage { case input, review, candidates }

    @State private var stage: Stage = .input
    @State private var inputText = ""
    @State private var request = CollectRequest()
    @State private var parsing = false
    @State private var searching = false
    @State private var candidates: [CollectCandidate] = []
    /// 正在放大查看的候选（点缩略图打开）
    @State private var previewCandidate: CollectCandidate?
    @State private var showBilibiliLogin = false
    /// B 站登录用户名（nil = 未登录；影响可下载画质）
    @State private var bilibiliUser: String?
    @State private var importing = false
    @State private var importedCount = 0
    /// 提示词历史（手动输入的 + 选项总结的），按工作台存
    @State private var history: [CollectHistoryEntry] = []
    /// 本次采集对应的历史条目（入库完成后回填结果）
    @State private var currentEntryID: String?
    /// 本次会话已入库的来源链接（「跳过重复」用）
    @State private var importedURLs: Set<String> = []
    @State private var statusText: String?

    /// 供测试 / 预览直接进到某一步（默认从「一句话输入」开始）
    init(initialStage: Stage = .input, request: CollectRequest = CollectRequest()) {
        _stage = State(initialValue: initialStage)
        _request = State(initialValue: request)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch stage {
                case .input: inputStage
                case .review: reviewStage
                case .candidates: candidateStage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 820, height: 660)
        .background(Color(nsColor: appAppearance.editorBackground))
        .sheet(item: $previewCandidate) { c in
            MediaPreviewSheet(
                title: c.title.isEmpty ? _L("未命名", "Untitled") : c.title,
                subtitle: c.pageURL?.host ?? c.thumbURL.host ?? "",
                imageURL: c.kind == "video" ? (c.videoURL == nil ? c.thumbURL : nil)
                                            : (c.fullURL ?? c.thumbURL),
                videoURL: c.videoURL,
                pageURL: c.pageURL ?? c.videoURL,
                resolvePlayableFromPage: c.kind == "video",
                extra: AnyView(
                    Button(c.selected ? _L("取消选中", "Deselect") : _L("选中这个", "Select")) {
                        if let i = candidates.firstIndex(where: { $0.id == c.id }) {
                            candidates[i].selected.toggle()
                        }
                    }
                    .controlSize(.small)
                ))
        }
        .task(id: store.notesDir.path) {
            history = CollectHistoryStore.load(workspace: store.notesDir)
        }
        .task {
            bilibiliUser = await BilibiliLogin.currentUserName()
        }
        .sheet(isPresented: $showBilibiliLogin) {
            CollectorBilibiliLoginSheet { user in bilibiliUser = user }
        }
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundStyle(appAppearance.accent)
            Text(_L("素材采集", "Collect Assets"))
                .font(.system(size: 14, weight: .semibold))
            Text("· " + store.notesDir.lastPathComponent)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
            if let statusText {
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(appAppearance.accent)
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - 第一步：一句话需求

    private var inputStage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(_L("用一句话说清你想要什么素材，AI 会解析成需求卡片；缺什么、补什么，确认后才开始采集。",
                    "Describe what you need in one sentence. The AI turns it into a requirement card — fill the gaps, confirm, then collection starts."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextEditor(text: $inputText)
                .font(.system(size: 13))
                .frame(height: 110)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: appAppearance.surface ?? appAppearance.editorBackground)))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: appAppearance.editorForeground.withAlphaComponent(0.15))))
            Text(_L("例：找 5 张赛博朋克霓虹街道图做笔记封面（视频同理）",
                    "e.g. Find 5 cyberpunk neon street images for note covers"))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            HStack {
                if !LLM.configured {
                    Text(_L("未配置 API Key，将直接进入手动填写", "No API key — fill the card manually"))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button(_L("手动填写", "Fill manually")) {
                    stage = .review
                }
                Button {
                    Task { await runParse() }
                } label: {
                    if parsing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(_L("解析需求", "Parse"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(parsing || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !history.isEmpty {
                Divider()
                historySection
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: 提示词历史（手动输入的 + 选项总结的，都能复用）

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11))
                    .foregroundStyle(appAppearance.accent)
                Text(_L("提示词历史 \(history.count)", "Prompt history \(history.count)"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(_L("清空", "Clear")) {
                    history = []
                    CollectHistoryStore.save([], workspace: store.notesDir)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(history) { entry in
                        historyRow(entry)
                    }
                }
            }
            .frame(maxHeight: 240)
        }
    }

    private func historyRow(_ entry: CollectHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(entry.kindBadge)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(appAppearance.accent.opacity(0.16)))
                    .foregroundStyle(appAppearance.accent)
                Text(entry.displayTitle)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(Self.historyTime(entry.createdAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                if entry.importedCount > 0 {
                    Text(_L("已入库 \(entry.importedCount)", "\(entry.importedCount) saved"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            // 选项总结出来的提示词
            Text(entry.summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            // 手动输入的提示词（有就显示）
            if !entry.text.isEmpty {
                Text("「" + entry.text.replacingOccurrences(of: "\n", with: " ") + "」")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                Button(_L("再用一次", "Use again")) {
                    inputText = entry.text
                    request = entry.request
                    currentEntryID = entry.id
                    statusText = nil
                    stage = .review
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(appAppearance.accent)
                Button {
                    history.removeAll { $0.id == entry.id }
                    CollectHistoryStore.save(history, workspace: store.notesDir)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(_L("删除这条记录", "Delete this record"))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(Color(nsColor: appAppearance.surface ?? appAppearance.editorBackground)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color(nsColor: appAppearance.editorForeground.withAlphaComponent(0.08))))
    }

    static func historyTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }

    private func runParse() async {
        parsing = true
        defer { parsing = false }
        if let r = await CollectorIntent.parse(inputText, current: request) {
            request = r
            statusText = nil
        } else {
            statusText = LLM.configured
                ? _L("解析失败，手动补一下吧", "Parse failed — fill manually")
                : _L("未配置 API Key：手动填写", "No API key: fill manually")
        }
        stage = .review
    }

    // MARK: - 第二步：需求卡片（缺字段高亮追问）

    private var reviewStage: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    basicsSection
                    styleSection
                    visualSection
                    if request.kind == "video" { videoSection } else { imageSection }
                    sourceSection
                    archiveSection
                    queryPreview
                }
                .padding(18)
            }
            Divider()
            HStack {
                Button(_L("返回", "Back")) { stage = .input }
                Spacer()
                Button {
                    Task { await runSearch() }
                } label: {
                    if searching {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text(_L("采集中…", "Searching…")) }
                    } else {
                        Text(_L("开始采集", "Start"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!request.isReady || searching)
                .help(request.isReady ? "" : _L("请先补全带 * 的必填项", "Fill the required (*) fields first"))
            }
            .padding(14)
        }
    }

    private func requiredRow(_ title: String, missing: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
            if missing {
                Text(_L("必填", "required"))
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.red.opacity(0.14)))
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: 需求表单（分组 · 越详细越好）

    /// 分组卡片
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(appAppearance.accent)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(Color(nsColor: appAppearance.surface ?? appAppearance.editorBackground)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color(nsColor: appAppearance.editorForeground.withAlphaComponent(0.08))))
    }

    /// 左侧标题 + 右侧控件的行
    private func labeled<Content: View>(_ title: String, missing: Bool = false,
                                        @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            requiredRow(title, missing: missing)
                .frame(width: 72, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func chip(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Text(label)
                .font(.system(size: 11))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .foregroundStyle(on ? Color.white : Color(nsColor: appAppearance.editorForeground))
                .background(Capsule().fill(on ? appAppearance.accent
                                              : Color(nsColor: appAppearance.editorForeground.withAlphaComponent(0.07))))
                .overlay(Capsule().stroke(on ? Color.clear
                                             : Color(nsColor: appAppearance.editorForeground.withAlphaComponent(0.15)),
                                          lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// 多选标签
    private func multiChips(_ title: String, options: [(zh: String, en: String)],
                            value: Binding<[String]>) -> some View {
        labeled(title) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(options, id: \.zh) { opt in
                    chip(opt.zh, on: value.wrappedValue.contains(opt.zh)) {
                        if let i = value.wrappedValue.firstIndex(of: opt.zh) {
                            value.wrappedValue.remove(at: i)
                        } else {
                            value.wrappedValue.append(opt.zh)
                        }
                    }
                }
            }
        }
    }

    /// 单选标签（枚举）
    private func singleChips<T: Hashable>(_ title: String, options: [(String, T)],
                                          value: Binding<T>) -> some View {
        labeled(title) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(options, id: \.1) { opt in
                    chip(opt.0, on: value.wrappedValue == opt.1) { value.wrappedValue = opt.1 }
                }
            }
        }
    }

    private func flagRow(_ title: String, isOn: Binding<Bool>) -> some View {
        labeled(title) {
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }

    private func optionalStringBinding(_ keyPath: WritableKeyPath<CollectRequest, String?>) -> Binding<String> {
        Binding(get: { request[keyPath: keyPath] ?? "" },
                set: { request[keyPath: keyPath] = $0.isEmpty ? nil : $0 })
    }

    private func enumBinding<E: RawRepresentable>(_ keyPath: WritableKeyPath<CollectRequest, String>,
                                                  _ fallback: E) -> Binding<E> where E.RawValue == String {
        Binding(get: { E(rawValue: request[keyPath: keyPath]) ?? fallback },
                set: { request[keyPath: keyPath] = $0.rawValue })
    }

    // MARK: 各分组

    var basicsSection: some View {
        section(_L("基本", "Basics")) {
            labeled(_L("类型", "Type"), missing: request.kind == nil) {
                HStack(spacing: 6) {
                    chip(_L("图片", "Images"), on: request.kind == "image") { request.kind = "image" }
                    chip(_L("视频", "Videos"), on: request.kind == "video") { request.kind = "video" }
                }
            }
            textRow(_L("主题", "Subject"), text: optionalStringBinding(\.subject),
                    required: (request.subject ?? "").isEmpty,
                    placeholder: _L("例如：赛博朋克霓虹街道", "e.g. cyberpunk neon street"))
            textRow(_L("用途", "Usage"), text: optionalStringBinding(\.usage), required: false,
                    placeholder: _L("封面 / 配图 / 视频素材 / 参考", "cover / illustration / footage / reference"))
            textRow(_L("不要", "Avoid"), text: optionalStringBinding(\.avoid), required: false,
                    placeholder: _L("水印 / 文字 / 真人 / 卡通", "watermarks / text / people / cartoon"))
            labeled(_L("数量", "Count")) {
                HStack(spacing: 8) {
                    Stepper(value: $request.count, in: 1...60) {
                        Text("\(request.count)").font(.system(size: 12)).monospacedDigit()
                    }
                    .frame(width: 120)
                    Text(_L("个候选", "candidates")).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            singleChips(_L("关键词语言", "Keywords"),
                        options: CollectKeywordLang.allCases.map { ($0.label, $0) },
                        value: enumBinding(\.keywordLang, CollectKeywordLang.both))
        }
    }

    var styleSection: some View {
        section(_L("风格", "Style")) {
            multiChips(_L("风格", "Style"), options: CollectOptions.styles, value: $request.styles)
            textRow(_L("补充", "Notes"), text: optionalStringBinding(\.styleNote), required: false,
                    placeholder: _L("自由描述（可选）：如「冷色调、雨夜、霓虹反射」", "free-form notes (optional)"))
        }
    }

    var visualSection: some View {
        section(_L("画面", "Visual")) {
            singleChips(_L("方向", "Orientation"),
                        options: CollectOrientation.allCases.map { ($0.label, $0) },
                        value: enumBinding(\.orientation, CollectOrientation.any))
            singleChips(_L("比例", "Aspect"),
                        options: CollectAspect.allCases.map { ($0.label, $0) },
                        value: enumBinding(\.aspect, CollectAspect.any))
            singleChips(_L("尺寸", "Size"),
                        options: CollectMinSize.allCases.map { ($0.label, $0) },
                        value: enumBinding(\.minSize, CollectMinSize.any))
            multiChips(_L("色调", "Tone"), options: CollectOptions.tones, value: $request.tones)
            multiChips(_L("主色", "Color"), options: CollectOptions.palette, value: $request.palette)
            multiChips(_L("氛围", "Mood"), options: CollectOptions.moods, value: $request.moods)
            multiChips(_L("构图", "Composition"), options: CollectOptions.compositions, value: $request.compositions)
            multiChips(_L("内容", "Content"), options: CollectOptions.contents, value: $request.contentFlags)
            flagRow(_L("留白", "Copy space"), isOn: $request.needTextSpace)
            flagRow(_L("无水印", "No watermark"), isOn: $request.noWatermark)
            if request.kind != "video" {
                flagRow(_L("透明底", "Transparent"), isOn: $request.transparent)
            }
        }
    }

    var imageSection: some View {
        section(_L("图片专属", "Images")) {
            singleChips(_L("格式", "Format"),
                        options: CollectImageFormat.allCases.map { ($0.label, $0) },
                        value: enumBinding(\.imageFormat, CollectImageFormat.any))
            singleChips(_L("类型", "Kind"),
                        options: CollectImageType.allCases.map { ($0.label, $0) },
                        value: enumBinding(\.imageType, CollectImageType.any))
        }
    }

    var videoSection: some View {
        section(_L("视频专属", "Videos")) {
            singleChips(_L("时长", "Duration"),
                        options: CollectVideoDuration.allCases.map { ($0.label, $0) },
                        value: enumBinding(\.videoDuration, CollectVideoDuration.any))
            singleChips(_L("清晰度", "Quality"),
                        options: CollectVideoResolution.allCases.map { ($0.label, $0) },
                        value: enumBinding(\.videoResolution, CollectVideoResolution.any))
            singleChips(_L("声音", "Audio"),
                        options: CollectVideoAudio.allCases.map { ($0.label, $0) },
                        value: enumBinding(\.videoAudio, CollectVideoAudio.any))
            singleChips(_L("字幕", "Subtitles"),
                        options: CollectVideoSubtitle.allCases.map { ($0.label, $0) },
                        value: enumBinding(\.videoSubtitle, CollectVideoSubtitle.any))
            multiChips(_L("平台", "Platform"), options: CollectOptions.platforms, value: $request.platforms)
        }
    }

    var sourceSection: some View {
        section(_L("来源与筛选", "Sources & Filtering")) {
            singleChips(_L("时效", "Freshness"),
                        options: CollectRecency.allCases.map { ($0.label, $0) },
                        value: enumBinding(\.recency, CollectRecency.any))
            singleChips(_L("筛选", "Strictness"),
                        options: CollectStrictness.allCases.map { ($0.label, $0) },
                        value: enumBinding(\.strictness, CollectStrictness.balanced))
            singleChips(_L("授权", "License"),
                        options: CollectLicense.allCases.map { ($0.label, $0) },
                        value: enumBinding(\.license, CollectLicense.any))
            textRow(_L("只看站点", "Only sites"), text: optionalStringBinding(\.siteFilter), required: false,
                    placeholder: _L("域名，逗号分隔：unsplash.com, pexels.com", "domains, comma separated"))
            textRow(_L("排除站点", "Exclude"), text: optionalStringBinding(\.excludeSites), required: false,
                    placeholder: _L("域名，逗号分隔（可选）", "domains to exclude (optional)"))
            // 平台账号：登录后采集才能下载 1080P（不登录只有 360P）
            labeled(_L("B站账号", "Bilibili")) {
                HStack(spacing: 8) {
                    if let user = bilibiliUser {
                        Text(_L("已登录：\(user)", "Signed in: \(user)"))
                            .font(.system(size: 11))
                            .foregroundStyle(appAppearance.accent)
                        Button(_L("退出", "Sign out")) {
                            Task {
                                await BilibiliLogin.logout()
                                bilibiliUser = nil
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    } else {
                        Text(_L("未登录（只能下 360P）", "Not signed in (360p only)"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Button(_L("登录 B 站…", "Sign in…")) { showBilibiliLogin = true }
                            .controlSize(.small)
                    }
                }
            }
            flagRow(_L("安全搜索", "Safe search"), isOn: $request.safeSearch)
        }
    }

    var archiveSection: some View {
        section(_L("入库", "Save")) {
            Text(_L("命名与目录沿用工作台约定：素材进 source/image，命名「日期-描述」。",
                    "Files go to source/image with the workspace convention \"date-description\"."))
                .font(.system(size: 11)).foregroundStyle(.tertiary)
            flagRow(_L("跳过重复", "Skip duplicates"), isOn: $request.skipDuplicates)
            labeled(_L("入库上限", "Max import")) {
                Stepper(value: $request.maxImport, in: 1...60) {
                    Text("\(request.maxImport)").font(.system(size: 12)).monospacedDigit()
                }
                .frame(width: 120)
            }
        }
    }

    var queryPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 选项总结出来的提示词（会记进历史，一眼能看懂这张卡要什么）
            Text(_L("需求提示词", "Requirement prompt")).font(.system(size: 12, weight: .semibold))
            Text(request.promptSummary())
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(_L("计划搜索词", "Search queries")).font(.system(size: 12, weight: .semibold))
            let qs = request.searchQueries()
            if qs.isEmpty {
                Text(_L("（填好主题后自动生成；AI 解析会直接给中英关键词）",
                        "(auto-generated once the subject is filled)"))
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            } else {
                ForEach(qs, id: \.self) { q in
                    Text("· \(q)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            let filters = request.kind == "video" ? request.videoFilterParams() : request.imageFilterParams()
            if !filters.isEmpty {
                Text(_L("站点筛选：", "Filters: ") + filters.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            Text(_L("结果以候选呈现，勾选后才下载。图片入库 source/image；视频保存为收藏条目（含封面与链接）。",
                    "Results appear as candidates — only checked items are downloaded."))
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(12)
    }

    private func textRow(_ title: String, text: Binding<String>, required: Bool, placeholder: String) -> some View {
        HStack(spacing: 10) {
            requiredRow(title, missing: required)
                .frame(width: 64, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .overlay(required ? RoundedRectangle(cornerRadius: 6).stroke(Color.red.opacity(0.6), lineWidth: 1) : nil)
        }
    }

    private func runSearch() async {
        guard request.isReady else { return }
        recordHistory()      // 开始采集 = 用了一次这条提示词，记进历史
        searching = true
        statusText = nil
        candidates = []
        let kind = request.kind ?? "image"
        let filters = kind == "video" ? request.videoFilterParams() : request.imageFilterParams()
        var all: [CollectCandidate] = []
        for q in request.searchQueries().prefix(3) {
            if kind == "video" {
                all += await CollectorSearch.searchVideos(query: q, count: request.count,
                                                          filters: filters,
                                                          safeSearch: request.safeSearch)
            } else {
                all += await CollectorSearch.searchImages(query: q, count: request.count,
                                                          filters: filters,
                                                          safeSearch: request.safeSearch)
            }
        }
        var seen = Set<String>()
        candidates = Array(all
            .filter { seen.insert($0.id).inserted }
            .filter { request.accepts($0) }
            .prefix(request.count * 2))
        searching = false
        stage = .candidates
        if candidates.isEmpty {
            statusText = _L("没有搜到结果，回上一步换个说法试试", "No results — go back and rephrase")
        }
    }

    // MARK: - 提示词历史：写入与回填

    /// 记一条历史：手动输入的提示词 + 选项总结出来的提示词 + 实际搜索词 + 完整需求
    private func recordHistory() {
        let entry = CollectHistoryEntry(
            text: inputText.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: request.promptSummary(),
            queries: request.searchQueries(),
            request: request)
        history = CollectHistoryStore.adding(entry, to: history)
        currentEntryID = entry.id
        CollectHistoryStore.save(history, workspace: store.notesDir)
    }

    /// 采集结束后把结果回填到这条历史（显示「已入库 N」）
    private func updateHistoryResult(_ count: Int) {
        guard let id = currentEntryID,
              let i = history.firstIndex(where: { $0.id == id }) else { return }
        history[i].importedCount = count
        CollectHistoryStore.save(history, workspace: store.notesDir)
    }

    // MARK: - 第三步：候选网格（勾选才下载）

    private var selectedCount: Int { candidates.filter(\.selected).count }

    private var candidateStage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(_L("\(candidates.count) 个候选", "\(candidates.count) candidates"))
                    .font(.system(size: 12, weight: .medium))
                Text(request.kind == "video" ? _L("视频", "Video") : _L("图片", "Images"))
                    .font(.system(size: 10))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(appAppearance.accent.opacity(0.14)))
                    .foregroundStyle(appAppearance.accent)
                Spacer()
                Button(_L("全选", "All")) { setAll(true) }
                Button(_L("清空", "None")) { setAll(false) }
                Button {
                    Task { await runSearch() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(_L("重新搜索", "Search again"))
            }
            .font(.system(size: 11))
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                ForEach($candidates) { $c in
                    candidateCard(c)
                        .onTapGesture { c.selected.toggle() }
                        .simultaneousGesture(TapGesture(count: 2).onEnded { previewCandidate = c })
                }
                }
                .padding(16)
            }
            Divider()
            HStack {
                Button(_L("返回修改需求", "Back")) { stage = .review }
                Spacer()
                if !importingCountText.isEmpty {
                    Text(importingCountText).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Button {
                    Task { await importSelected() }
                } label: {
                    if importing {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text(_L("下载中…", "Downloading…")) }
                    } else {
                        Text(_L("采集选中（\(selectedCount)）", "Collect selected (\(selectedCount))"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCount == 0 || importing)
            }
            .padding(14)
        }
    }

    private var importingCountText: String {
        importedCount > 0 ? _L("已入库 \(importedCount) 个", "\(importedCount) imported") : ""
    }

    private func setAll(_ on: Bool) {
        for i in candidates.indices { candidates[i].selected = on }
    }

    private func candidateCard(_ c: CollectCandidate) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topLeading) {
                AsyncImage(url: c.thumbURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        ZStack {
                            Color(nsColor: appAppearance.surface ?? appAppearance.editorBackground)
                            Image(systemName: "photo").foregroundStyle(.tertiary)
                        }
                    default:
                        ZStack {
                            Color(nsColor: appAppearance.surface ?? appAppearance.editorBackground)
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .frame(height: 108)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Image(systemName: c.selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(c.selected ? appAppearance.accent : Color.white.opacity(0.9))
                    .shadow(radius: 2)
                    .padding(6)

                if let d = c.duration {
                    Text(d)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
                // 预览入口：图片=放大镜（可缩放看细节）；视频=播放（能直连就直接播放）
                Button {
                    previewCandidate = c
                } label: {
                    Image(systemName: c.kind == "video" ? "play.circle.fill" : "plus.magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .help(c.kind == "video"
                      ? (c.videoURL == nil ? _L("看封面 / 打开视频页", "Preview cover / open page")
                                           : _L("播放预览", "Play preview"))
                      : _L("放大预览（可缩放）", "Zoom preview"))
            }
            Text(c.title.isEmpty ? _L("未命名", "Untitled") : c.title)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundStyle(Color(nsColor: appAppearance.editorForeground))
            HStack(spacing: 5) {
                if let src = c.sourceLabel, !src.isEmpty {
                    Text(src)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(appAppearance.accent.opacity(0.14)))
                        .foregroundStyle(appAppearance.accent)
                } else {
                    Text(c.pageURL?.host ?? c.thumbURL.host ?? "")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                if c.kind == "video", c.videoURL != nil {
                    Text(_L("可播放", "Playable"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.green)
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            if let meta = c.metaLine, !meta.isEmpty {
                Text(meta)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(c.selected ? appAppearance.accent : Color.clear, lineWidth: 2))
    }

    private func importSelected() async {
        importing = true
        importedCount = 0
        statusText = nil
        var skipped = 0
        for c in candidates where c.selected {
            let name = Self.shortName(c.title)
            // 跳过重复：同一条链接本次已入库过就不再下
            let key = (c.fullURL ?? c.pageURL)?.absoluteString ?? c.id
            if request.skipDuplicates, importedURLs.contains(key) { skipped += 1; continue }
            if importedCount >= max(1, request.maxImport) { break }
            if c.kind == "image", let full = c.fullURL {
                if await store.downloadCollectedImage(from: full, preferredName: name, referer: c.pageURL) != nil {
                    importedCount += 1
                    importedURLs.insert(key)
                }
            } else if c.kind == "video", let page = c.pageURL {
                // 先试解析可播放直链：解析到就下载成真视频（source/mp4），否则只存「收藏条目」
                statusText = _L("正在解析视频地址…", "Resolving video source…")
                var resolved: CollectorVideoResolver.ResolvedVideo?
                if let direct = c.videoURL { resolved = .init(url: direct, quality: nil) }
                else { resolved = await CollectorVideoResolver.resolve(pageURL: page) }
                var localRel: String?
                if let r = resolved {
                    // 你要的清晰度达不到时，如实说清楚（多半是没登录 / 账号权限不够）
                    let asked = CollectVideoResolution(rawValue: request.videoResolution) ?? .any
                    if asked != .any, CollectVideoResolution.rank(of: r.quality) < asked.requiredRank {
                        statusText = _L("注意：该视频只能取到 \(r.quality ?? "未知画质")（你要求 \(asked.label)）——登录 B 站可提升",
                                        "Note: only \(r.quality ?? "unknown") available (asked \(asked.label)) — sign in to Bilibili")
                    } else {
                        statusText = _L("正在下载视频…", "Downloading video…")
                    }
                    localRel = await store.downloadCollectedVideo(from: r.url, preferredName: name, referer: page)
                }
                var coverRel: String?
                if let rel = await store.downloadCollectedImage(from: c.thumbURL, preferredName: name + "-封面", referer: nil) {
                    coverRel = rel
                }
                if store.appendVideoFavorite(title: c.title, pageURL: page, duration: c.duration,
                                             coverRel: coverRel, localRel: localRel) {
                    importedCount += 1
                    importedURLs.insert(key)
                }
            }
        }
        importing = false
        NotificationCenter.default.post(name: .assetsChanged, object: nil)
        var note = _L("已入库 \(importedCount) 个", "\(importedCount) imported")
        if skipped > 0 { note += _L("（跳过重复 \(skipped)）", " (\(skipped) duplicates skipped)") }
        statusText = note
        updateHistoryResult(importedCount)
    }

    /// 候选标题 → 素材描述名（截断 + 去掉文件系统敏感字符；入库时还会加「日期-」前缀）
    static func shortName(_ title: String) -> String {
        var t = title.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count > 30 { t = String(t.prefix(30)) }
        for ch in ["/", ":", "|"] { t = t.replacingOccurrences(of: ch, with: "-") }
        // 去掉首尾标点（来源站标题常带「。」「-」等尾巴）
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "。．.！!？?、，,：:;；-—– ").union(.whitespaces))
        return t.isEmpty ? "采集" : t
    }
}

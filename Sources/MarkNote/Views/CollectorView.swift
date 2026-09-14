import SwiftUI

/// 素材采集面板（视图插件 `collector` 的内置渲染器）。
///
/// 流程（老规矩：先签合同再干活）：
/// 一句话需求 → AI 解析成需求卡片 → **AI 追问（没说清就接着问）** → 缺字段高亮 → 开工确认 →
/// 搜索 → 候选勾选 → 入库。
/// 结果不自动落地：用户勾选哪些、哪些才下载。
struct CollectorView: View {
    @Environment(NotesStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    enum Stage { case input, clarify, review, candidates }

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
    /// 下载进度：当前文件的字节进度（nil = 总长未知，显示流动条）
    @State private var downloadSample: DownloadProgressSample?
    /// 正在下载的候选 id（候选卡片上叠加同款细进度条）
    @State private var downloadingCandidateID: String?
    /// 进度条说明：「阶段 · 条目名」+「第几个/共几个」
    @State private var downloadPhase = ""
    @State private var downloadItemName = ""
    @State private var downloadIndex = 0
    @State private var downloadTotal = 0
    /// 本次没下下来的原因（逐条列出来，不让「选了 4 个只下来 2 个」变成糊涂账）
    @State private var importFailures: [String] = []
    @State private var showFailureAlert = false
    /// 小说抓章节的进度（章节数比条目数更有信息量）
    @State private var crawlBook = ""
    @State private var crawlIndex = 0
    @State private var crawlTotal = 0
    /// 本次入库的 Markdown 笔记（相对路径；用来「打开第一篇」）
    @State private var savedNotes: [String] = []
    /// AI 追问：当前这一轮的问题 + 回答 + 轮次
    @State private var clarifyQuestions: [CollectClarifyQuestion] = []
    @State private var clarifyAnswers: [String: String] = [:]
    @State private var clarifyReason: String?
    @State private var clarifyRound = 0
    @State private var clarifyBusy = false
    /// 已答过的追问（拼进后续解析的文本里，别让 AI 忘掉）
    @State private var clarifyTranscript = ""

    /// 供测试 / 预览直接进到某一步（默认从「一句话输入」开始）
    init(initialStage: Stage = .input, request: CollectRequest = CollectRequest(),
         clarifyQuestions: [CollectClarifyQuestion] = []) {
        _stage = State(initialValue: initialStage)
        _request = State(initialValue: request)
        _clarifyQuestions = State(initialValue: clarifyQuestions)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch stage {
                case .input: inputStage
                case .clarify: clarifyStage
                case .review: reviewStage
                case .candidates: candidateStage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 820, height: 660)
        .background(Color(nsColor: appAppearance.editorBackground))
        .alert(_L("有几条要跟你说清楚", "Some items need attention"), isPresented: $showFailureAlert) {
            Button(_L("知道了", "OK"), role: .cancel) {}
        } message: {
            Text(importFailureMessage)
        }
        .sheet(item: $previewCandidate) { c in
            MediaPreviewSheet(
                title: c.title.isEmpty ? _L("未命名", "Untitled") : c.title,
                subtitle: c.pageURL?.host ?? c.thumbURL?.host ?? "",
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
            Text(_L("AI 没听明白时会**接着追问**（最多 3 轮，可跳过）：问清了才会去搜。",
                    "If the AI isn't sure what you mean it **keeps asking** (up to 3 rounds, skippable)."))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
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
                        Text(_L("解析需求（可能追问）", "Parse (may ask follow-ups)"))
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
            // 解析完先让 AI 自审一遍：没说清就追问，问清（或问满轮次）才進需求卡
            clarifyRound = 0
            clarifyTranscript = ""
            if await askClarifyIfNeeded() { return }
        } else {
            statusText = LLM.configured
                ? _L("解析失败，手动补一下吧", "Parse failed — fill manually")
                : _L("未配置 API Key：手动填写", "No API key: fill manually")
        }
        stage = .review
    }

    // MARK: - AI 追问（需求没说清就接着问）

    /// 需要追问 → 切到追问页并返回 true；否则返回 false（继续走需求卡）
    private func askClarifyIfNeeded() async -> Bool {
        guard LLM.configured, CollectorClarify.canAskMore(round: clarifyRound) else { return false }
        clarifyBusy = true
        clarifyRound += 1
        let text = clarifyTranscript.isEmpty ? inputText : inputText + clarifyTranscript
        let review = await CollectorClarify.review(request, userText: text, round: clarifyRound)
        clarifyBusy = false
        guard let review, !review.ready, !review.questions.isEmpty else { return false }
        clarifyQuestions = review.questions
        clarifyAnswers = [:]
        clarifyReason = review.reason
        stage = .clarify
        return true
    }

    /// 提交这一轮回答：并进文本 → 重新解析 → 继续审（够了就进需求卡）
    private func submitClarify() async {
        let pairs = clarifyQuestions.map { (question: $0.question, answer: clarifyAnswers[$0.id] ?? "") }
        guard pairs.contains(where: { !$0.answer.trimmed.isEmpty }) else {
            stage = .review      // 一个都没答：别卡着，直接看需求卡
            return
        }
        clarifyBusy = true
        clarifyTranscript = "\n" + CollectorClarify.followUpText("", answers: pairs)
        if let r = await CollectorIntent.parse(inputText + clarifyTranscript, current: request) {
            request = r
        }
        clarifyBusy = false
        if await askClarifyIfNeeded() { return }
        stage = .review
    }

    /// 追问页：AI 的问题 + 可点选项 + 自由补充
    private var clarifyStage: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView { clarifyBody }
            Divider()
            HStack {
                Button(_L("不问了，直接看需求卡", "Skip to card")) { stage = .review }
                    .disabled(clarifyBusy)
                Button(_L("返回改一句话", "Back")) { stage = .input }
                    .disabled(clarifyBusy)
                Spacer()
                Button {
                    Task { await submitClarify() }
                } label: {
                    if clarifyBusy {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text(_L("理解中…", "Thinking…")) }
                    } else {
                        Text(_L("提交回答", "Submit"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(clarifyBusy)
            }
            .padding(14)
        }
    }

    /// 追问页的内容区（单独抽出来：渲染检查与复用）
    var clarifyBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.bubble")
                    .foregroundStyle(appAppearance.accent)
                Text(_L("AI 还想确认几点", "A few things to confirm"))
                    .font(.system(size: 13, weight: .semibold))
                Text(_L("第 \(max(clarifyRound, 1))/\(CollectorClarify.maxRounds) 轮",
                        "round \(max(clarifyRound, 1))/\(CollectorClarify.maxRounds)"))
                    .font(.system(size: 10))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(appAppearance.accent.opacity(0.14)))
                    .foregroundStyle(appAppearance.accent)
            }
            if let reason = clarifyReason, !reason.isEmpty {
                Text(reason)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: appAppearance.editorForeground).opacity(0.72))
            }
            Text(_L("答完这些才能少搜一堆不相干的；不想答也行，直接看需求卡。",
                    "Answering these keeps the search on target — or just skip to the card."))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            ForEach(clarifyQuestions) { q in
                clarifyCard(q)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func clarifyCard(_ q: CollectClarifyQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(q.question)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(nsColor: appAppearance.editorForeground))
            if !q.options.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)],
                          alignment: .leading, spacing: 6) {
                    ForEach(q.options, id: \.self) { opt in
                        chip(opt, on: clarifyAnswers[q.id] == opt) {
                            // 再点一次取消；选项与自由文本共用一个答案位
                            clarifyAnswers[q.id] = clarifyAnswers[q.id] == opt ? "" : opt
                        }
                    }
                }
            }
            TextField(_L("也可以自己写（可补充多项，逗号分隔）", "or type your own answer"),
                      text: Binding(get: { clarifyAnswers[q.id] ?? "" },
                                    set: { clarifyAnswers[q.id] = $0 }))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(Color(nsColor: appAppearance.surface ?? appAppearance.editorBackground)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color(nsColor: appAppearance.editorForeground.withAlphaComponent(0.08))))
    }

    // MARK: - 第二步：需求卡片（缺字段高亮追问）

    private var reviewStage: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    basicsSection
                    if request.isTextKind {
                        textSection
                    } else {
                        styleSection
                        visualSection
                        if request.kind == "video" { videoSection } else { imageSection }
                    }
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
                    chip(_L("文章", "Articles"), on: request.kind == "article") { request.kind = "article" }
                    chip(_L("小说", "Novels"), on: request.kind == "novel") { request.kind = "novel" }
                }
            }
            textRow(request.isTextKind ? _L("题材", "Topic") : _L("主题", "Subject"),
                    text: optionalStringBinding(\.subject),
                    required: (request.subject ?? "").isEmpty,
                    placeholder: request.kind == "novel"
                        ? _L("例如：三体（写好书名，目录会在入库时自己找）", "e.g. a book title")
                        : _L("例如：赛博朋克霓虹街道 / 城市更新长文",
                             "e.g. cyberpunk neon street / long-form article"))
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
                    Text(request.kind == "novel" ? _L("本（候选书）", "books (candidates)")
                                                 : (request.kind == "article" ? _L("篇候选", "articles")
                                                                              : _L("个候选", "candidates")))
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
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

    /// 文章 / 小说专属：直接转成工作台里的 .md 笔记
    var textSection: some View {
        section(request.kind == "novel" ? _L("小说专属", "Novels") : _L("文章专属", "Articles")) {
            Text(_L("正文会**直接转成 Markdown 笔记**存进当前工作台（不进 source 素材库）：标题成 # 一级标题，来源与采集时间写在开头。",
                    "The body is converted straight into a Markdown note in this workspace."))
                .font(.system(size: 11)).foregroundStyle(.tertiary)
            if request.kind == "novel" {
                labeled(_L("章节数", "Chapters")) {
                    HStack(spacing: 8) {
                        Stepper(value: $request.chapterLimit, in: 1...500, step: 5) {
                            Text("\(request.chapterLimit)").font(.system(size: 12)).monospacedDigit()
                        }
                        .frame(width: 120)
                        Text(_L("最多抓多少章（从第一章开始）", "how many chapters to fetch"))
                            .font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
                flagRow(_L("合并成一个文件", "Merge into one file"), isOn: $request.mergeChapters)
                Text(_L("关掉则一章一个 .md，统一放进以书名为名的文件夹。",
                        "Turn off to save one .md per chapter in a folder named after the book."))
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            } else {
                Text(_L("每篇一个 .md；正文提取用「容器启发式」（article / 正文 id-class 优先），广告、导航、页脚会清掉。",
                        "One .md per article; ads, nav and footers are stripped."))
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
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
            // 平台账号：登录后采集才能下载 1080P（不登录只有 360P）—— 文章 / 小说用不上
            if !request.isTextKind {
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
            let filters = request.isTextKind ? []
                : (request.kind == "video" ? request.videoFilterParams() : request.imageFilterParams())
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
        let filters = request.isTextKind ? []
            : (kind == "video" ? request.videoFilterParams() : request.imageFilterParams())
        var all: [CollectCandidate] = []
        for q in request.searchQueries().prefix(3) {
            if kind == "video" {
                all += await CollectorSearch.searchVideos(query: q, count: request.count,
                                                          filters: filters,
                                                          safeSearch: request.safeSearch)
            } else if request.isTextKind {
                var found = await CollectorSearch.searchWeb(query: q, count: max(request.count, 12),
                                                            safeSearch: request.safeSearch)
                if kind == "novel" {
                    // 小说：把「像目录页」的排前面（判定在解析阶段已经做过），并统一按小说入库
                    found.sort { ($0.kind == "novel" ? 0 : 1) < ($1.kind == "novel" ? 0 : 1) }
                }
                for i in found.indices { found[i].kind = kind }
                all += found
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
        guard let id = currentEntryID else { return }
        // 以**磁盘上的**历史为准：面板状态可能已被重建/刷新过，内存里那份找不到就静默丢结果
        var list = CollectHistoryStore.load(workspace: store.notesDir)
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].importedCount = count
        CollectHistoryStore.save(list, workspace: store.notesDir)
        history = list
    }

    // MARK: - 第三步：候选网格（勾选才下载）

    private var selectedCount: Int { candidates.filter(\.selected).count }

    private var candidateStage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(_L("\(candidates.count) 个候选", "\(candidates.count) candidates"))
                    .font(.system(size: 12, weight: .medium))
                Text(kindBadgeText)
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
                if request.isTextKind {
                    LazyVStack(spacing: 8) {
                        ForEach($candidates) { $c in
                            candidateRow(c)
                                .onTapGesture { c.selected.toggle() }
                        }
                    }
                    .padding(16)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                    ForEach($candidates) { $c in
                        candidateCard(c)
                            .onTapGesture { c.selected.toggle() }
                            .simultaneousGesture(TapGesture(count: 2).onEnded { previewCandidate = c })
                    }
                    }
                    .padding(16)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                if importing { downloadBar }
                HStack {
                    Button(_L("返回修改需求", "Back")) { stage = .review }
                        .disabled(importing)
                    Spacer()
                    if !importingCountText.isEmpty {
                        Text(importingCountText).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if !importing, let first = savedNotes.first {
                        Button(_L("打开刚采集的笔记", "Open collected note")) {
                            store.openNote(first)
                            dismiss()
                        }
                        .controlSize(.small)
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
            }
            .padding(14)
        }
    }

    /// 下载进度条：说明（阶段 · 条目）+ 「第几个/共几个 · 已下/总长」+ 百分比（主题化样式）
    private var downloadBar: some View {
        // 小说：进度按「第几章 / 共几章」走，比「第几个候选」有用得多
        if crawlTotal > 0 {
            return ThemeProgressBar(value: Double(crawlIndex) / Double(max(crawlTotal, 1)),
                                    label: _L("正在抓章节 · \(crawlBook)", "Fetching chapters · \(crawlBook)"),
                                    detail: "\(crawlIndex)/\(crawlTotal)",
                                    height: 6)
        }
        let phase = downloadPhase.isEmpty ? _L("正在下载", "Downloading") : downloadPhase
        let name = downloadItemName.isEmpty ? "" : " · \(downloadItemName)"
        var detail = downloadTotal > 0 ? "\(downloadIndex)/\(downloadTotal)" : ""
        if let s = downloadSample {
            detail += detail.isEmpty ? s.bytesText : " · \(s.bytesText)"
        }
        return ThemeProgressBar(value: downloadSample?.fraction,
                                label: phase + name,
                                detail: detail,
                                height: 6)
    }

    private var importingCountText: String {
        importedCount > 0 ? _L("已入库 \(importedCount) 个", "\(importedCount) imported") : ""
    }

    private var kindBadgeText: String {
        switch request.kind {
        case "video": return _L("视频", "Video")
        case "article": return _L("文章", "Article")
        case "novel": return _L("小说", "Novel")
        default: return _L("图片", "Images")
        }
    }

    /// 文章 / 小说候选：一行一条（标题 + 摘要 + 来源），点一下勾选
    private func candidateRow(_ c: CollectCandidate) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: c.selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(c.selected ? appAppearance.accent
                                            : Color(nsColor: appAppearance.editorForeground.withAlphaComponent(0.35)))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 5) {
                Text(c.title.isEmpty ? _L("未命名", "Untitled") : c.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(nsColor: appAppearance.editorForeground))
                    .lineLimit(2)
                if let e = c.excerpt, !e.isEmpty {
                    Text(e)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: appAppearance.editorForeground).opacity(0.72))
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    if let src = c.sourceLabel ?? c.pageURL?.host, !src.isEmpty {
                        Text(src)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(appAppearance.accent.opacity(0.14)))
                            .foregroundStyle(appAppearance.accent)
                            .lineLimit(1)
                    }
                    if let meta = c.metaLine, !meta.isEmpty {
                        Text(meta).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let page = c.pageURL {
                        Button(_L("打开来源", "Open source")) { NSWorkspace.shared.open(page) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10))
                            .foregroundStyle(appAppearance.accent)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(Color(nsColor: appAppearance.surface ?? appAppearance.editorBackground)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(c.selected ? appAppearance.accent
                               : Color(nsColor: appAppearance.editorForeground.withAlphaComponent(0.08)),
                    lineWidth: c.selected ? 1.5 : 1))
        .contentShape(Rectangle())
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
                // 正在下载这一条：缩略图底部叠一条主题化细进度条（垫半透明底保证压得住图）
                if c.id == downloadingCandidateID {
                    HStack(spacing: 5) {
                        ThemeProgressBar(value: downloadSample?.fraction, height: 4, showsPercent: false)
                        Text(downloadSample?.fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "…")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                        .padding(.horizontal, 6).padding(.bottom, 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
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
                    Text(c.pageURL?.host ?? c.thumbURL?.host ?? "")
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
        importFailures = []
        var skipped = 0
        var failures: [String] = []
        let queue = candidates.filter(\.selected)
        downloadTotal = min(queue.count, max(1, request.maxImport))
        downloadIndex = 0
        downloadSample = nil
        downloadPhase = ""
        downloadItemName = ""
        // 下载回调在后台线程 → 切回主线程刷进度（@State 只能在主线程改）
        let sink: (DownloadProgressSample) -> Void = { s in
            Task { @MainActor in downloadSample = s }
        }
        for c in queue {
            // 序号按「候选队列里的位置」走：跳过重复时也不会出现「5/7 就结束」
            downloadIndex = min(downloadIndex + 1, max(downloadTotal, 1))
            downloadItemName = Self.shortName(c.title)
            downloadingCandidateID = c.id
            downloadSample = nil
            // 跳过重复：同一条链接本次已入库过就不再下
            let key = (c.fullURL ?? c.pageURL)?.absoluteString ?? c.id
            if request.skipDuplicates, importedURLs.contains(key) {
                downloadPhase = _L("跳过重复", "Skipping duplicate")
                skipped += 1
                continue
            }
            if importedCount >= max(1, request.maxImport) {
                failures.append(_L("还有 \(queue.count - downloadIndex + 1) 个没下：本次入库上限是 \(request.maxImport) 个（可在需求卡里调大）",
                                   "\(queue.count - downloadIndex + 1) left: import limit is \(request.maxImport)"))
                break
            }
            let name = downloadItemName
            if c.kind == "article" || c.kind == "novel" {
                // 文章 / 小说：抓正文 → 转 Markdown → 存成工作台里的 .md 笔记
                downloadPhase = c.kind == "novel" ? _L("正在抓小说", "Fetching novel")
                                                  : _L("正在抓正文", "Fetching article")
                let outcome = await importTextCandidate(c)
                if outcome.ok {
                    importedCount += 1
                    importedURLs.insert(key)
                }
                if let note = outcome.note { failures.append("\(name)：\(note)") }
            } else if c.kind == "image" {
                downloadPhase = _L("正在下载图片", "Downloading image")
                guard let src = c.fullURL ?? c.thumbURL else {
                    failures.append(_L("\(name)：这条没有图片地址", "\(name): no image URL"))
                    continue
                }
                switch await store.downloadCollectedImage(from: src, preferredName: name, referer: c.pageURL) {
                case .saved:
                    importedCount += 1
                    importedURLs.insert(key)
                case .failed(let why):
                    // 原图被防盗链/签名拦下 → 退到搜索缩略图（Bing 缓存一般能取到）：
                    // 宁可小一档也别空手，但必须在账上写清楚
                    if let thumb = c.thumbURL, c.fullURL != nil, thumb != src,
                       case .saved = await store.downloadCollectedImage(from: thumb,
                                                                        preferredName: name + "-缩略图",
                                                                        referer: nil) {
                        importedCount += 1
                        importedURLs.insert(key)
                        failures.append(_L("\(name)：原图取不到（\(why)），已退到缩略图（分辨率低一档）",
                                           "\(name): origin blocked (\(why)) — Bing thumbnail saved instead"))
                    } else {
                        failures.append("\(name)：\(why)")
                    }
                }
            } else if c.kind == "video", let page = c.pageURL {
                // 先试解析可播放直链：解析到就下载成真视频（source/mp4），否则只存「收藏条目」
                downloadPhase = _L("正在解析视频地址", "Resolving video source")
                statusText = _L("正在解析视频地址…", "Resolving video source…")
                var resolved: CollectorVideoResolver.ResolvedVideo?
                if let direct = c.videoURL { resolved = .init(url: direct, quality: nil) }
                else { resolved = await CollectorVideoResolver.resolve(pageURL: page) }
                var localRel: String?
                var videoNote: String?
                if let r = resolved {
                    downloadPhase = _L("正在下载视频", "Downloading video")
                    // 你要的清晰度达不到时，如实说清楚（多半是没登录 / 账号权限不够）
                    let asked = CollectVideoResolution(rawValue: request.videoResolution) ?? .any
                    if asked != .any, CollectVideoResolution.rank(of: r.quality) < asked.requiredRank {
                        statusText = _L("注意：该视频只能取到 \(r.quality ?? "未知画质")（你要求 \(asked.label)）——登录 B 站可提升",
                                        "Note: only \(r.quality ?? "unknown") available (asked \(asked.label)) — sign in to Bilibili")
                    } else {
                        statusText = _L("正在下载视频…", "Downloading video…")
                    }
                    switch await store.downloadCollectedVideo(from: r.url, preferredName: name,
                                                              referer: page, onProgress: sink) {
                    case .saved(let rel):
                        localRel = rel
                    case .failed(let why):
                        videoNote = why           // 文件没下来，但收藏条目照存（含链接/封面）
                    }
                } else {
                    videoNote = _L("没解析出可下载直链", "no downloadable direct URL")
                }
                var coverRel: String?
                downloadPhase = _L("正在下载封面", "Downloading cover")
                downloadSample = nil
                if let thumb = c.thumbURL,
                   case .saved(let rel) = await store.downloadCollectedImage(from: thumb,
                                                                            preferredName: name + "-封面",
                                                                            referer: nil) {
                    coverRel = rel
                }
                if store.appendVideoFavorite(title: c.title, pageURL: page, duration: c.duration,
                                             coverRel: coverRel, localRel: localRel) {
                    importedCount += 1
                    importedURLs.insert(key)
                    if let videoNote {
                        failures.append(_L("\(name)：视频没下下来（\(videoNote)），只存了收藏条目",
                                           "\(name): video not downloaded (\(videoNote)) — entry saved"))
                    }
                } else {
                    failures.append("\(name)：收藏条目写入失败")
                }
            } else {
                failures.append(_L("\(name)：这条没有可下载的地址", "\(name): no downloadable URL"))
            }
        }
        importing = false
        downloadingCandidateID = nil
        downloadSample = nil
        downloadPhase = ""
        downloadItemName = ""
        crawlTotal = 0
        crawlIndex = 0
        crawlBook = ""
        NotificationCenter.default.post(name: .assetsChanged, object: nil)
        // 失败如实汇总：弹窗列原因（候选保持勾选，可以再点一次重试）
        importFailures = failures
        if !failures.isEmpty { showFailureAlert = true }
        var note = _L("已入库 \(importedCount) 个", "\(importedCount) imported")
        if skipped > 0 { note += _L("（跳过重复 \(skipped)）", " (\(skipped) duplicates skipped)") }
        if !failures.isEmpty { note += _L(" · 失败 \(failures.count) 个", " · \(failures.count) failed") }
        statusText = note
        updateHistoryResult(importedCount)
    }

    // MARK: - 文章 / 小说入库（正文 → Markdown 笔记）

    private struct TextImport {
        var ok: Bool
        /// 非致命说明（例：第 3 章没抓到 / 原图被拦）；nil = 一切顺利
        var note: String?
    }

    private func importTextCandidate(_ c: CollectCandidate) async -> TextImport {
        guard var page = c.pageURL else { return TextImport(ok: false, note: _L("没有来源链接", "no source URL")) }
        // 搜索引擎跳转没解开（或解失败）时，入库前再解一次
        if let host = page.host?.lowercased(), host.contains("so.com") || host.contains("sogou.com"),
           let jump = await CollectorSearch.fetch(page),
           let real = CollectorSearch.redirectTarget(inHTML: jump),
           let url = URL(string: real) {
            page = url
        }
        guard let html = await CollectorSearch.fetch(page) else {
            return TextImport(ok: false, note: _L("打不开页面（反爬 / 需要登录 / 已失效）",
                                                 "cannot open page (anti-bot / login / dead link)"))
        }
        if c.kind == "novel" {
            return await importNovel(html: html, page: page, candidateID: c.id, fallbackTitle: c.title)
        }
        let body = HTMLToMarkdown.convert(html, baseURL: page)
        let words = HTMLToMarkdown.wordCount(body)
        guard words >= 200 else {
            return TextImport(ok: false, note: _L("正文只有 \(words) 字（多半是列表页 / 反爬页）",
                                                  "body only \(words) chars (list page / blocked)"))
        }
        let linkRatio = HTMLToMarkdown.linkTextRatio(body)
        guard linkRatio <= 0.5 else {
            return TextImport(ok: false,
                              note: _L("这页的「正文」\(Int(linkRatio * 100))% 是链接文字（导航/评论页，正文多半是动态加载的）",
                                       "page is \(Int(linkRatio * 100))% link text (nav/comment page)"))
        }
        let title = HTMLToMarkdown.pageTitle(inHTML: html) ?? c.title
        let note = NovelCollector.articleNote(title: title, source: page, markdown: body)
        guard let rel = store.saveCollectedMarkdown(note, title: title) else {
            return TextImport(ok: false, note: _L("写入笔记失败", "failed to write note"))
        }
        savedNotes.append(rel)
        if let i = candidates.firstIndex(where: { $0.id == c.id }) {
            candidates[i].metaLine = _L("\(words) 字 → \(rel)", "\(words) chars → \(rel)")
        }
        return TextImport(ok: true, note: nil)
    }

    private func importNovel(html: String, page: URL, candidateID: String,
                             fallbackTitle: String) async -> TextImport {
        let bookTitle = HTMLToMarkdown.pageTitle(inHTML: html) ?? fallbackTitle
        var chapters = NovelCollector.chapters(inHTML: html, base: page)
        guard !chapters.isEmpty else {
            return TextImport(ok: false,
                              note: _L("这页没有章节目录（可能要先打开「目录」页，或该站要求登录）",
                                       "no chapter list on this page (try the index/catalog page)"))
        }
        let total = chapters.count
        if chapters.count > max(1, request.chapterLimit) {
            chapters = Array(chapters.prefix(request.chapterLimit))
        }
        crawlBook = bookTitle
        crawlTotal = chapters.count
        crawlIndex = 0
        var collected: [(title: String, markdown: String)] = []
        var failed = 0
        for ch in chapters {
            crawlIndex += 1
            guard let chHTML = await CollectorSearch.fetch(ch.url) else { failed += 1; continue }
            let body = HTMLToMarkdown.convert(chHTML, baseURL: ch.url)
            guard HTMLToMarkdown.wordCount(body) >= 100,
                  HTMLToMarkdown.linkTextRatio(body) <= 0.5 else { failed += 1; continue }
            collected.append((ch.title, body))
        }
        crawlTotal = 0
        crawlIndex = 0
        guard !collected.isEmpty else {
            return TextImport(ok: false, note: _L("章节正文一页都没抓到（反爬 / 需要登录）",
                                                  "no chapter text could be fetched"))
        }
        let words = collected.reduce(0) { $0 + HTMLToMarkdown.wordCount($1.markdown) }
        var notes: [String] = []
        if request.mergeChapters {
            let note = NovelCollector.bookNote(bookTitle: bookTitle, source: page, chapters: collected)
            if let rel = store.saveCollectedMarkdown(note, title: bookTitle) { notes.append(rel) }
        } else {
            for ch in collected {
                let note = NovelCollector.articleNote(title: ch.title, source: page, markdown: ch.markdown)
                if let rel = store.saveCollectedMarkdown(note, title: ch.title, folder: bookTitle) {
                    notes.append(rel)
                }
            }
        }
        guard !notes.isEmpty else {
            return TextImport(ok: false, note: _L("写入笔记失败", "failed to write note"))
        }
        savedNotes.append(contentsOf: notes)
        if let i = candidates.firstIndex(where: { $0.id == candidateID }) {
            let done = collected.count
            candidates[i].metaLine = _L("\(done)/\(total) 章 · \(words) 字 → \(notes.first ?? "")",
                                        "\(done)/\(total) chapters · \(words) chars → \(notes.first ?? "")")
        }
        var note: String?
        if failed > 0 {
            note = _L("有 \(failed) 章没抓到（其余已存好）", "\(failed) chapters failed (rest saved)")
        }
        if chapters.count < total {
            let rest = _L("按设定只抓了前 \(chapters.count) 章（共 \(total) 章）",
                          "fetched first \(chapters.count) of \(total) chapters per setting")
            note = note.map { "\($0)；\(rest)" } ?? rest
        }
        return TextImport(ok: true, note: note)
    }

    /// 失败弹窗正文：最多列 8 条（其余折叠成一句），并提示可以直接重试
    private var importFailureMessage: String {
        let head = _L("有 \(importFailures.count) 条没进库：", "\(importFailures.count) item(s) failed:")
        let lines = importFailures.prefix(8).joined(separator: "\n")
        let more = importFailures.count > 8 ? _L("\n…还有 \(importFailures.count - 8) 条", "\n…and \(importFailures.count - 8) more") : ""
        let tail = _L("\n\n这些候选还保持勾选：可以直接再点一次「采集选中」重试（例如换个来源页 / 重新登录 B 站）。",
                      "\n\nThey stay selected — click Collect again to retry.")
        return "\(head)\n\(lines)\(more)\(tail)"
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

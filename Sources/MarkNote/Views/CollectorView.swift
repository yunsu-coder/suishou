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
    @State private var importing = false
    @State private var importedCount = 0
    @State private var statusText: String?

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
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                VStack(alignment: .leading, spacing: 12) {
                    requiredRow(_L("类型", "Type"), missing: request.kind == nil)
                    Picker("", selection: Binding(
                        get: { request.kind ?? "" },
                        set: { request.kind = $0.isEmpty ? nil : $0 })) {
                        Text(_L("请选择", "Choose")).tag("")
                        Text(_L("图片", "Images")).tag("image")
                        Text(_L("视频", "Videos")).tag("video")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 260)

                    textRow(_L("主题", "Subject"), text: Binding(
                        get: { request.subject ?? "" },
                        set: { request.subject = $0.isEmpty ? nil : $0 }),
                             required: (request.subject ?? "").isEmpty,
                             placeholder: _L("例如：赛博朋克霓虹街道", "e.g. cyberpunk neon street"))
                    textRow(_L("用途", "Usage"), text: Binding(
                        get: { request.usage ?? "" },
                        set: { request.usage = $0.isEmpty ? nil : $0 }),
                             required: false,
                             placeholder: _L("封面 / 配图 / 参考（可选）", "cover / illustration / reference (optional)"))
                    textRow(_L("风格", "Style"), text: Binding(
                        get: { request.style ?? "" },
                        set: { request.style = $0.isEmpty ? nil : $0 }),
                             required: false,
                             placeholder: _L("极简 / 写实 / 手绘（可选）", "minimal / realistic / hand-drawn (optional)"))
                    textRow(_L("不要", "Avoid"), text: Binding(
                        get: { request.avoid ?? "" },
                        set: { request.avoid = $0.isEmpty ? nil : $0 }),
                             required: false,
                             placeholder: _L("水印 / 文字 / 真人（可选）", "watermarks / text / people (optional)"))
                    HStack(spacing: 10) {
                        Text(_L("数量", "Count"))
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 64, alignment: .leading)
                        Stepper(value: $request.count, in: 1...40) {
                            Text("\(request.count)")
                                .font(.system(size: 12))
                                .monospacedDigit()
                        }
                        .frame(width: 120)
                    }

                    // 开工单：搜索词预览
                    VStack(alignment: .leading, spacing: 6) {
                        Text(_L("计划搜索词", "Search queries"))
                            .font(.system(size: 12, weight: .medium))
                        let qs = request.composedQueries()
                        if qs.isEmpty {
                            Text(_L("（填好主题后自动生成，或用 AI 解析生成中英关键词）",
                                    "(auto-generated once the subject is filled)"))
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(qs, id: \.self) { q in
                                Text("· \(q)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(_L("来源：公开图片/视频站点；结果以候选呈现，勾选后才下载。图片入库 source/image（命名「日期-描述」）；视频保存为收藏条目（含封面与链接）。",
                                "Sources: public image/video sites. Results appear as candidates — only checked items are downloaded."))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 4)
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
        searching = true
        statusText = nil
        candidates = []
        let kind = request.kind ?? "image"
        var all: [CollectCandidate] = []
        for q in request.composedQueries().prefix(3) {
            if kind == "video" {
                all += await CollectorSearch.searchVideos(query: q, count: request.count)
            } else {
                all += await CollectorSearch.searchImages(query: q, count: request.count)
            }
        }
        var seen = Set<String>()
        candidates = Array(all.filter { seen.insert($0.id).inserted }.prefix(request.count * 2))
        searching = false
        stage = .candidates
        if candidates.isEmpty {
            statusText = _L("没有搜到结果，回上一步换个说法试试", "No results — go back and rephrase")
        }
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
            }
            Text(c.title.isEmpty ? _L("未命名", "Untitled") : c.title)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundStyle(Color(nsColor: appAppearance.editorForeground))
            Text(c.pageURL?.host ?? c.thumbURL.host ?? "")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(c.selected ? appAppearance.accent : Color.clear, lineWidth: 2))
    }

    private func importSelected() async {
        importing = true
        importedCount = 0
        statusText = nil
        for c in candidates where c.selected {
            let name = Self.shortName(c.title)
            if c.kind == "image", let full = c.fullURL {
                if await store.downloadCollectedImage(from: full, preferredName: name, referer: c.pageURL) != nil {
                    importedCount += 1
                }
            } else if c.kind == "video", let page = c.pageURL {
                var coverRel: String?
                if let rel = await store.downloadCollectedImage(from: c.thumbURL, preferredName: name + "-封面", referer: nil) {
                    coverRel = rel
                }
                if store.appendVideoFavorite(title: c.title, pageURL: page, duration: c.duration, coverRel: coverRel) {
                    importedCount += 1
                }
            }
        }
        importing = false
        NotificationCenter.default.post(name: .assetsChanged, object: nil)
        statusText = _L("已入库 \(importedCount) 个", "\(importedCount) imported")
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

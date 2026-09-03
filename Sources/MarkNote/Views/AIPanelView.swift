import SwiftUI
import Observation

// ═══════════ AIChatModel：流式 + 文件代理链 + @引用 + 历史 + 总结 ═══════════
@MainActor
@Observable
final class AIChatModel {
    struct ChatMsg: Identifiable {
        let id = UUID()
        let role: String                    // "user" / "assistant" / "tool"
        var content: String
        var isStreaming = false
        var toolCalls: [FileTools.ParsedCall]?
        var toolCallID: String?
        var toolEvent: FileTools.Event?
        var pendingConfirm: FileTools.PendingConfirm?
        var referenced: [String] = []

        init(role: String, content: String = "", isStreaming: Bool = false,
             toolCalls: [FileTools.ParsedCall]? = nil, toolCallID: String? = nil,
             toolEvent: FileTools.Event? = nil, pendingConfirm: FileTools.PendingConfirm? = nil,
             referenced: [String] = []) {
            self.role = role
            self.content = content
            self.isStreaming = isStreaming
            self.toolCalls = toolCalls
            self.toolCallID = toolCallID
            self.toolEvent = toolEvent
            self.pendingConfirm = pendingConfirm
            self.referenced = referenced
        }
    }

    // MARK: 会话状态
    var messages: [ChatMsg] = []
    var expertID = AIExperts.all[0].id
    var input = ""
    var busy = false
    /// 会话/历史
    struct ConversationMeta: Identifiable, Equatable {
        let id: String
        var title: String
        var updatedAt: Date
        var count: Int
        var expertID: String
    }
    private(set) var conversations: [ConversationMeta] = []
    var currentConversationID: String?

    // MARK: 注入
    var fileContext: (() -> String)?
    var agent: WorkspaceAgent?
    var indexProvider: (() -> [NoteIndexItem])?
    var historyBaseDir: (() -> URL)?

    // MARK: 内部
    private var streamTask: Task<Void, Never>?
    private var toolRound = 0
    private let maxRounds = 6
    private static let maxHistory = 20
    private static let maxPersistChars = 400 * 1024

    var expert: AIExpert { AIExperts.byID(expertID) }

    // MARK: - 发送 / 工具链

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        input = ""
        beginConversationIfNeeded(title: text)
        var context = text
        if let ctx = fileContext?(), !ctx.isEmpty {
            context = "当前工作文件内容（节选）：\n\n\(String(ctx.prefix(8000)))\n\n---\n\n用户：\(text)"
        }
        let refs = extractReferences(from: text)
        for (_, id) in refs.prefix(3) {
            if let content = agent?.readReference(id) {
                let name = (id as NSString).lastPathComponent
                context.append("\n\n【引用文件 \(name)（\(id)）】\n\(content)")
            }
        }
        messages.append(ChatMsg(role: "user", content: text, referenced: refs.prefix(3).map(\.1)))
        toolRound = 0
        runRound([LLM.Message(role: "user", content: context)])
    }

    private func runRound(_ history: [LLM.Message]) {
        guard toolRound < maxRounds else {
            appendSystemNote(_L("（工具调用轮数已达上限，已停止）", "(Tool-call rounds reached the limit; stopped)"))
            finishRound()
            return
        }
        toolRound += 1
        busy = true
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                // 文件代理开关：关闭 = 纯问答（不注入 tools，AI 无法操作工作台）
                let agentTools = FeatureModules.isEnabled(FeatureModules.aiFileAgent) ? FileTools.specs : nil
                let stream = LLM.chatStreamTools(system: expert.system, messages: history, tools: agentTools)
                var text = ""
                var calls: [FileTools.ParsedCall] = []
                let stub = ChatMsg(role: "assistant", content: "", isStreaming: true)
                messages.append(stub)
                let idx = messages.count - 1
                for try await ev in stream {
                    switch ev {
                    case .text(let t):
                        text += t
                        if idx < messages.count {
                            var m = messages[idx]
                            m.content = text
                            messages[idx] = m
                        }
                    case .toolCall(let c):
                        calls.append(c)
                    }
                }
                if idx < messages.count && !text.isEmpty {
                    var m = messages[idx]
                    m.content = text
                    messages[idx] = m
                }
                if text.isEmpty && calls.isEmpty {
                    if idx < messages.count {
                        var m = messages[idx]
                        m.content = _L("（模型未返回内容，请重试或换个说法）", "(The model returned nothing — please retry or rephrase)")
                        messages[idx] = m
                    }
                    finishRound()
                    return
                }
                if idx < messages.count {
                    var m = messages[idx]
                    m.isStreaming = false
                    m.toolCalls = calls.isEmpty ? nil : calls
                    messages[idx] = m
                }
                guard !calls.isEmpty else { finishRound(); return }

                var next = history + [LLM.Message(role: "assistant", content: text, toolCalls: calls)]
                for call in calls {
                    guard let agent else {
                        appendSystemNote(_L("（文件代理未就绪）", "(File agent not ready)"))
                        finishRound()
                        return
                    }
                    let outcome = agent.handle(call)
                    switch outcome {
                    case .result(let r):
                        next.append(LLM.Message(role: "tool", content: r, toolCallID: call.id))
                        messages.append(ChatMsg(role: "tool", content: r, toolCallID: call.id,
                                                toolEvent: toolEvent(for: call.name, result: r)))
                    case .confirm(let pending):
                        messages.append(ChatMsg(role: "tool", content: pending.title,
                                                toolCallID: call.id, pendingConfirm: pending))
                        pendingChain = next
                        persistCurrentConversation()
                        busy = false
                        return
                    }
                }
                runRound(next)
            } catch is CancellationError {
                // 用户主动中断：静默结束（气泡已有内容）
                if !messages.isEmpty {
                    var m = messages[messages.count - 1]
                    m.isStreaming = false
                    messages[messages.count - 1] = m
                }
                finishRound()
            } catch {
                appendSystemNote(_L("⚠️ 连接失败：\(error.localizedDescription)", "⚠️ Connection failed: \(error.localizedDescription)"))
                finishRound()
            }
        }
    }

    /// 用户确认（允许/拒绝）破坏性操作 → 继续工具链
    func respondToConfirm(_ pending: FileTools.PendingConfirm, allow: Bool) {
        guard let agent, let chain = pendingChain else { finishRound(); return }
        let call = pending.call
        let result: String
        if allow {
            result = agent.performDelete(call)
        } else {
            let refusedPath = call.argsDict["path"] as? String ?? ""
            result = _L("用户拒绝了删除操作：\(refusedPath)", "User declined the delete: \(refusedPath)")
        }
        var updatedPending = false
        for i in messages.indices {
            if let p = messages[i].pendingConfirm, p.id == pending.id {
                messages[i].pendingConfirm = nil
                messages[i].content = result
                messages[i].toolEvent = toolEvent(for: call.name, result: result)
                updatedPending = true
                break
            }
        }
        if updatedPending {
            messages.append(ChatMsg(role: "tool", content: result,
                                    toolCallID: call.id, toolEvent: toolEvent(for: call.name, result: result)))
        }
        pendingChain = nil
        runRound(chain + [LLM.Message(role: "tool", content: result, toolCallID: call.id)])
    }

    // MARK: - 中断

    /// 中断当前对话（流式或工具链）；已生成内容保留
    func stop() {
        streamTask?.cancel()
        busy = false
        toolRound = maxRounds          // 后续链不再自动推进
        pendingChain = nil
        if let last = messages.last, last.isStreaming {
            var m = messages[messages.count - 1]
            m.isStreaming = false
            messages[messages.count - 1] = m
        }
        persistCurrentConversation()
    }

    // MARK: - 历史对话

    /// 首次消息时开新会话
    private func beginConversationIfNeeded(title: String) {
        if currentConversationID == nil || messages.isEmpty {
            let id = UUID().uuidString
            currentConversationID = id
            let meta = ConversationMeta(id: id, title: String(title.prefix(18)), updatedAt: Date(), count: 0, expertID: expertID)
            conversations.insert(meta, at: 0)
        }
    }

    private func historyDir() -> URL? {
        guard let base = historyBaseDir?() else { return nil }
        return base.appendingPathComponent(".ai-history", isDirectory: true)
    }

    private struct StoredMessage: Codable {
        let role: String
        var content: String
        var referenced: [String]
        var toolTitle: String?
    }

    private struct StoredConversation: Codable {
        let id: String
        var title: String
        var updatedAt: Date
        var expertID: String
        var messages: [StoredMessage]
    }

    /// 载入历史索引（面板出现/目录变化时调用）
    func loadHistory() {
        guard let dir = historyDir() else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        var metas: [ConversationMeta] = []
        for f in files where f.pathExtension == "json" {
            guard let data = try? Data(contentsOf: f),
                  let conv = try? JSONDecoder().decode(StoredConversation.self, from: data) else { continue }
            metas.append(ConversationMeta(id: conv.id, title: conv.title, updatedAt: conv.updatedAt,
                                          count: conv.messages.count, expertID: conv.expertID))
        }
        conversations = metas.sorted { $0.updatedAt > $1.updatedAt }
        while conversations.count > Self.maxHistory {
            let drop = conversations.removeLast()
            try? fm.removeItem(at: dir.appendingPathComponent(drop.id + ".json"))
        }
    }

    /// 落盘当前会话摘要（工具链结束时/中断/总结后调用）
    func persistCurrentConversation() {
        guard let id = currentConversationID, !messages.isEmpty else { return }
        guard let dir = historyDir() else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let stored = StoredConversation(
            id: id,
            title: (conversations.first { $0.id == id })?.title ?? String((messages.first?.content ?? _L("对话", "Conversation")).prefix(18)),
            updatedAt: Date(),
            expertID: expertID,
            messages: messages.prefix(200).map { m in
                StoredMessage(role: m.role, content: String(m.content.prefix(Self.maxPersistChars)),
                              referenced: m.referenced, toolTitle: m.toolEvent?.title.split(separator: "→").first.map(String.init))
            })
        if let data = try? JSONEncoder().encode(stored) {
            try? data.write(to: dir.appendingPathComponent(id + ".json"), options: .atomic)
        }
        updateMeta(id: id, count: messages.count)
    }

    private func updateMeta(id: String, count: Int) {
        let now = Date()
        var metaInfo: ConversationMeta? = nil
        var matched = false
        for i in conversations.indices {
            if conversations[i].id == id {
                conversations[i].updatedAt = now
                conversations[i].count = count
                matched = true
                break
            }
        }
        if !matched {
            metaInfo = ConversationMeta(id: id, title: messages.first.map { String($0.content.prefix(18)) } ?? _L("对话", "Conversation"), updatedAt: now, count: count, expertID: expertID)
        }
        if let info = metaInfo { conversations.insert(info, at: 0) }
        conversations.sort { $0.updatedAt > $1.updatedAt }
    }

    /// 打开历史会话（会话消息载入并继续旧专家）
    func loadConversation(_ targetID: String) {
        guard let dir = historyDir() else { return }
        let url = dir.appendingPathComponent(targetID + ".json")
        guard let data = try? Data(contentsOf: url),
              let conv = try? JSONDecoder().decode(StoredConversation.self, from: data) else { return }
        streamTask?.cancel()
        messages = conv.messages.map { m in
            let ev = m.toolTitle.map { FileTools.Event(id: UUID().uuidString, icon: "doc.text", title: _L($0 + " → 完成", $0 + " → Done")) }
            return ChatMsg(role: m.role, content: m.content, toolEvent: ev, referenced: m.referenced)
        }
        expertID = conv.expertID
        currentConversationID = conv.id
        toolRound = maxRounds
        busy = false
        pendingChain = nil
        updateMeta(id: conv.id, count: messages.count)
    }

    func deleteConversation(_ id: String) {
        guard let dir = historyDir() else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(id + ".json"))
        conversations.removeAll { $0.id == id }
        if currentConversationID == id {
            // 直接清空会话（不可再 persist —— 否则会立刻重建被删文件）
            streamTask?.cancel()
            messages = []
            currentConversationID = nil
            busy = false
            toolRound = 0
            pendingChain = nil
        }
    }

    func startNewConversation() {
        streamTask?.cancel()
        if !messages.isEmpty { persistCurrentConversation() }
        messages = []
        busy = false
        toolRound = 0
        pendingChain = nil
        currentConversationID = nil
    }

    // MARK: - AI 总结对话 → 写入笔记

    nonisolated static func buildTranscript(from msgs: [ChatMsg], limit: Int = 16_000) -> String {
        var out: [String] = []
        for m in msgs {
            let c = m.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if c.isEmpty { continue }
            switch m.role {
            case "user":
                out.append("用户：\(c)")
            case "assistant":
                out.append("AI：\(c)")
            case "tool":
                out.append("· 文件操作：\(c.prefix(80))")
            default: break
            }
        }
        var text = out.joined(separator: "\n\n")
        if text.count > limit { text = String(text.suffix(limit)) }
        return text
    }

    /// 一键总结：LLM 生成 Markdown 摘要 → 工作台新建「AI对话总结-时间.md」→ 留痕
    func summarizeToNote() {
        guard FeatureModules.isEnabled(FeatureModules.aiSummary) else { return }
        guard !messages.isEmpty, !busy else { return }
        busy = true
        let transcript = Self.buildTranscript(from: messages)
        let expert = AIExperts.byID("summarizer")
        let system = expert.system + "\n输出 Markdown：\n# 对话主题\n## 一句话概述\n## 关键要点（编号列表）\n## 行动项 / 后续（如有）\n## 时间与涉及文件"
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        let baseName = _L("AI对话总结-", "AI-Chat-Summary-") + df.string(from: Date())
        Task { [weak self] in
            guard let self else { return }
            do {
                let summary = try await LLM.complete(system: system, user: transcript, temperature: 0.3, maxTokens: 2048)
                let finalName: String?
                if let agent {
                    finalName = agent.createUniqueTextFile(baseName: baseName, content: summary)
                } else {
                    finalName = nil
                }
                let report = finalName.map { _L("已总结并写入：\($0)", "Summarized and written to: \($0)") } ?? _L("总结生成失败（文件代理未就绪）", "Summary failed (file agent not ready)")
                let icon = finalName == nil ? "exclamationmark.triangle" : "doc.badge.plus"
                messages.append(ChatMsg(role: "tool", content: report,
                                        toolEvent: FileTools.Event(id: UUID().uuidString, icon: icon, title: report)))
                persistCurrentConversation()
                busy = false
            } catch {
                appendSystemNote(_L("⚠️ 总结失败：\(error.localizedDescription)", "⚠️ Summary failed: \(error.localizedDescription)"))
                busy = false
            }
        }
    }

    // MARK: - 内部工具

    func selectReference(_ item: NoteIndexItem) {
        let display = item.id
        pendingRefs[display] = item.id
        if let at = input.lastIndex(of: "@") {
            input = String(input[..<at]) + "@" + display + " "
        }
    }

    private var pendingRefs: [String: String] = [:]
    private var pendingChain: [LLM.Message]?

    private func extractReferences(from text: String) -> [(String, String)] {
        let stop = CharacterSet(charactersIn: " \n，。！？、…；：“”（）[]<>\t")
        var out: [(String, String)] = []
        var scanner = text
        while let at = scanner.firstIndex(of: "@") {
            let rest = scanner[scanner.index(after: at)...]
            let cut = rest.rangeOfCharacter(from: stop)?.lowerBound ?? rest.endIndex
            let token = String(rest[..<cut]).trimmingCharacters(in: .whitespaces)
            if !token.isEmpty {
                if let id = pendingRefs[token] {
                    if !out.contains(where: { $0.1 == id }) { out.append((token, id)) }
                } else if let id = agent?.findReference(token) {
                    if !out.contains(where: { $0.1 == id }) { out.append((token, id)) }
                }
            }
            scanner = String(cut == rest.endIndex ? "" : String(rest[cut...]))
        }
        return out
    }

    private func toolEvent(for name: String, result: String) -> FileTools.Event {
        let icon: String
        switch name {
        case "list_files": icon = "folder"
        case "read_file": icon = "doc.text"
        case "write_file": icon = "pencil"
        case "rename_file": icon = "arrow.triangle.2.circlepath"
        case "move_file": icon = "folder.badge.arrow.right"
        case "delete_file": icon = "trash"
        default: icon = "wrench.and.screwdriver"
        }
        let firstLine = result.split(separator: "\n").first.map(String.init) ?? result
        return FileTools.Event(id: UUID().uuidString, icon: icon,
                               title: "\(name) → " + String(firstLine.prefix(80)))
    }

    private func appendSystemNote(_ note: String) {
        messages.append(ChatMsg(role: "tool", content: note,
                                toolEvent: FileTools.Event(id: UUID().uuidString, icon: "info.circle", title: note)))
    }

    private func finishRound() {
        busy = false
        persistCurrentConversation()
    }
}

// ═══════════ AIPanelView：停靠面板 UI ═══════════
struct AIPanelView: View {
    @Environment(NotesStore.self) private var store
    @Environment(AIChatModel.self) private var model
    @State private var showHistory = false
    @State private var pluginTick = 0

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if showHistory {
                historyList
            } else {
                header
                Divider()
                if model.messages.isEmpty {
                    emptyIntro
                } else {
                    conversation
                }
                Divider()
                inputBar
            }
        }
        .onAppear { model.loadHistory() }
        // 插件变更（专家包启用/禁用）→ 刷新专家下拉
        .onReceive(NotificationCenter.default.publisher(for: PluginManager.changedNotification)) { _ in
            pluginTick += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiInsertResult)) { note in
            if let text = note.object as? String {
                insertIntoEditor(text)
            }
        }
    }

    // MARK: 头部

    private var header: some View {
        @Bindable var model = model
        return HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(_LL("AI 问答", "AI Chat")).font(.headline)
                if let id = model.currentConversationID,
                   let meta = model.conversations.first(where: { $0.id == id }) {
                    Text(meta.title).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Picker(_LL("专家", "Expert"), selection: $model.expertID) {
                ForEach(AIExperts.allWithPlugins()) { e in
                    Label(e.name, systemImage: e.icon).tag(e.id)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 150)
            .id(pluginTick)
            Spacer()
            Button {
                model.summarizeToNote()
            } label: {
                Label(_LL("总结到笔记", "Summarize to Note"), systemImage: "doc.badge.plus")
            }
            .controlSize(.small)
            .disabled(model.messages.isEmpty || model.busy || !FeatureModules.isEnabled(FeatureModules.aiSummary))
            .help(_LL("把本次对话总结为 Markdown 写入工作台新文件", "Summarize this chat as Markdown into a new workspace file"))
            Button {
                showHistory = true
                model.loadHistory()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(_LL("历史对话记录", "Conversation history"))
            Button(_LL("新对话", "New Chat")) {
                model.startNewConversation(); showHistory = false
            }
            .controlSize(.small)
            Button {
                NotificationCenter.default.post(name: .aiPanelToggle, object: nil)
            } label: {
                Image(systemName: "chevron.right.2").help(_LL("折叠 AI 面板", "Collapse AI panel"))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(10)
    }

    // MARK: 历史列表

    private var historyList: some View {
        VStack(spacing: 0) {
            HStack {
                Label(_LL("对话历史", "History"), systemImage: "clock.arrow.circlepath").font(.headline)
                Spacer()
                Button(_LL("返回到对话", "Back to Chat")) { showHistory = false }.buttonStyle(.link).font(.caption)
            }
            .padding(10)
            Divider()
            if model.conversations.isEmpty {
                Spacer()
                Text(_LL("暂无历史对话\n（每次 AI 对话结束都会自动保存）", "No history yet\n(each chat auto-saves on finish)"))
                    .font(.callout).foregroundStyle(.tertiary)
                Spacer()
            } else {
                List {
                    ForEach(model.conversations) { c in
                        HStack(spacing: 8) {
                            Button {
                                model.loadConversation(c.id)
                                showHistory = false
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.title)
                                        .font(.callout.weight(.medium))
                                        .lineLimit(1)
                                    Text(_L("\(c.count) 条 · \(c.updatedAt.formatted(date: .abbreviated, time: .shortened))", "\(c.count) items · \(c.updatedAt.formatted(date: .abbreviated, time: .shortened))"))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Button(role: .destructive) {
                                model.deleteConversation(c.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tertiary)
                            .help(_LL("删除这条历史记录", "Delete this history record"))
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: 对话

    private var emptyIntro: some View {
        VStack(spacing: 12) {
            Image(systemName: model.expert.icon)
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(model.expert.name).font(.title3.weight(.semibold))
            Text(model.expert.desc).font(.callout).foregroundStyle(.secondary)
            Text(_LL("基于当前文件内容（节选前 8000 字符）问答；回答可一键插入光标处。\n输入 @ 可引用工作台文件；直接说「读 / 写 / 改名 / 删除 文件名」即可操作文件。", "Ask about the current file content (first 8,000 characters); answers can be inserted at the cursor with one click.\nType @ to reference workspace files, or say \"read / write / rename / delete <filename>\" to operate on files."))
                .font(.caption).foregroundStyle(.tertiary)
            Spacer().frame(height: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.messages) { m in
                        bubble(m)
                    }
                }
                .padding(12)
            }
            .onChange(of: model.messages.map(\.content).joined() + "|" + String(model.messages.count)) { _ in
                if let last = model.messages.last {
                    withAnimation(.none) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func bubble(_ m: AIChatModel.ChatMsg) -> some View {
        // 工具留痕 / 删除确认行
        if let confirm = m.pendingConfirm {
            return AnyView(
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(confirm.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button(_LL("删除（移入 .trash）", "Delete (move to .trash)")) { model.respondToConfirm(confirm, allow: true) }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .controlSize(.small)
                            Button(_LL("取消", "Cancel")) { model.respondToConfirm(confirm, allow: false) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    Spacer(minLength: 30)
                }
                .padding(.vertical, 2)
            )
        }
        if m.role == "tool" {
            return AnyView(
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: m.toolEvent?.icon ?? "wrench.and.screwdriver")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                    Text(m.content.isEmpty ? (m.toolEvent?.title ?? "") : m.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(.vertical, 2)
            )
        }
        return AnyView(
        HStack(alignment: .top, spacing: 8) {
            if m.role == "user" {
                Spacer(minLength: 60)
                Image(systemName: "person.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(m.content)
                        .font(.callout)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        .textSelection(.enabled)
                    if !m.referenced.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "paperclip")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            ForEach(m.referenced, id: \.self) { r in
                                Text("@" + ((r as NSString).lastPathComponent))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary.opacity(0.45), in: Capsule())
                            }
                        }
                    }
                }
            } else {
                Image(systemName: model.expert.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(m.content.isEmpty && m.isStreaming ? _L("思考中……", "Thinking…") : m.content)
                        .font(.callout)
                        .textSelection(.enabled)
                    if !m.isStreaming && !m.content.isEmpty && m.toolCalls == nil {
                        Button {
                            insertIntoEditor(m.content)
                        } label: {
                            Label(_LL("插入到光标处", "Insert at cursor"), systemImage: "arrow.down.to.line")
                                .font(.caption)
                        }
                        .buttonStyle(.link)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                Spacer(minLength: 40)
            }
        }
        )
    }

    /// @ 引用选择查询：输入停在「@xxx（无空格）」时出现
    private var mentionQuery: String? {
        let text = model.input
        guard let at = text.lastIndex(of: "@") else { return nil }
        let after = String(text[text.index(after: at)...])
        guard !after.contains(" "), !after.contains("\n") else { return nil }
        return after
    }

    /// 选择器数据源：工作台索引（含目录归属）
    private var mentionCandidates: [NoteIndexItem] {
        guard let provider = model.indexProvider else { return [] }
        let all = provider()
        guard let q = mentionQuery else { return [] }
        let lower = q.lowercased()
        if lower.isEmpty { return Array(all.prefix(8)) }
        let hits = all.filter { $0.id.lowercased().contains(lower) || $0.title.lowercased().contains(lower) }
        let exact = hits.first { $0.id.caseInsensitiveCompare(q) == .orderedSame }
        if let exact { return [exact] + hits.filter { $0.id != exact.id }.prefix(7) }
        return Array(hits.prefix(8))
    }

    private var inputBar: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            if mentionCandidates.isEmpty == false, let q = mentionQuery {
                mentionPanel(query: q)
            }
            HStack(spacing: 8) {
                TextField(_LL("输入问题……（⇧Enter 发送 · Enter 换行 · @ 引用文件）", "Ask a question… (⇧Enter to send · Enter for newline · @ to reference a file)"), text: $model.input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .lineLimit(1...8)
                    .onKeyPress(keys: [.return], phases: [.down]) { press in
                        // 发送 = ⇧Enter / ⌘Enter / ⌥Enter；裸 Enter 一律换行（防止误发送）
                        if press.modifiers.contains(.shift) || press.modifiers.contains(.command) || press.modifiers.contains(.option) {
                            model.send()
                            return .handled
                        }
                        return .ignored
                    }
                if model.busy {
                    Button {
                        model.stop()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .help(_LL("停止生成", "Stop generating"))
                }
                Button {
                    model.send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .disabled(model.input.trimmingCharacters(in: .whitespaces).isEmpty || model.busy)
            }
            .padding(10)
        }
    }

    /// @ 引用选择浮层（跟随输入栏）
    private func mentionPanel(query: String) -> some View {
        VStack(spacing: 0) {
            ForEach(mentionCandidates) { item in
                Button {
                    model.selectReference(item)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(item.title.isEmpty ? item.id : item.title)
                            .font(.callout)
                            .lineLimit(1)
                        Text(item.id.hasPrefix("/") ? item.id : "——")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    /// 把 AI 回答插入到编辑器光标处（经通知转发给 EditorView）
    private func insertIntoEditor(_ text: String) {
        NotificationCenter.default.post(name: .aiInsertResult, object: text)
    }
}

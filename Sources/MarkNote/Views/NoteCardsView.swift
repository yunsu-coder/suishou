import SwiftUI

/// 卡片墙 —— 视图插件 `noteCards` 的内置渲染器。
///
/// 规则（见 docs/05-内置插件库.md · 插件隔离规则 / 插件主题适配规范）：
/// · 作用域：只读**当前工作台**的笔记；不移动、不改名、不改内容；
/// · 主题适配：所有颜色与字体取主题变量（appAppearance），不写死色值；
/// · 星标属于「本机 UI 偏好」，存 UserDefaults，不进入笔记文件。
struct NoteCardsView: View {
    let spec: PluginView

    @Environment(NotesStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("cardWall.starred") private var starredRaw = ""
    @AppStorage("cardWall.previewLines") private var previewLines = 6
    /// 打开笔记（由 ContentView 注入：切回编辑器 + 选中该笔记）
    let onOpen: (String) -> Void

    private var starred: Set<String> {
        Set(starredRaw.split(separator: "\n").map(String.init))
    }

    private var lines: Int { max(1, min(20, spec.options.previewLines ?? previewLines)) }

    /// 按天分组（今天 / 昨天 / 更早），组内按修改时间倒序。
    private var groups: [(title: String, items: [NoteIndexItem])] {
        var buckets: [String: [NoteIndexItem]] = [:]
        var order: [String] = []
        let cal = Calendar.current
        let iso = ISO8601DateFormatter()
        // 卡片墙只收「笔记」：跳过图片/音视频/压缩包等素材文件（它们在素材面板里看）
        let sorted = store.index
            .filter { Self.isNoteFile($0.id) }
            .sorted { (iso.date(from: $0.updated) ?? .distantPast)
                > (iso.date(from: $1.updated) ?? .distantPast) }
        for note in sorted {
            let date = iso.date(from: note.updated) ?? Date()
            let key: String
            if cal.isDateInToday(date) { key = _L("今天", "Today") }
            else if cal.isDateInYesterday(date) { key = _L("昨天", "Yesterday") }
            else {
                let f = DateFormatter()
                f.dateFormat = _L("M 月 d 日", "MMM d")
                key = f.string(from: date)
            }
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(note)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(groups, id: \.title) { group in
                    Text(group.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)],
                              alignment: .leading, spacing: 16) {
                        ForEach(group.items) { note in
                            card(note)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: appAppearance.editorBackground))
    }

    private func card(_ note: NoteIndexItem) -> some View {
        let accent = Color(nsColor: appAppearance.accentNS)
        let isStarred = starred.contains(note.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Rectangle().fill(accent).frame(width: 4)
                VStack(alignment: .leading, spacing: 8) {
                    Text(note.title.isEmpty ? _L("无标题", "Untitled") : note.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(nsColor: appAppearance.editorForeground))
                        .lineLimit(1)
                    ForEach(Array(previewLines(note).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if previewLines(note).count >= lines {
                        Text(_L("…", "…"))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    HStack(spacing: 10) {
                        Text(Self.folderLabel(note.category))
                        Text(shortDate(note.updated))
                        Spacer()
                        Button {
                            toggleStar(note.id)
                        } label: {
                            Image(systemName: isStarred ? "star.fill" : "star")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(isStarred ? accent : Color.secondary)
                        Button(_L("继续写", "Write")) { onOpen(note.id) }
                            .buttonStyle(.borderless)
                            .foregroundStyle(accent)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
                .padding(14)
            }
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: appAppearance.surface ?? appAppearance.editorBackground)))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: appAppearance.editorForeground.withAlphaComponent(0.14)), lineWidth: 1))
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen(note.id) }
        .animation(reduceMotion ? nil : .easeOut(duration: appAppearance.motion?.duration ?? 0.22),
                   value: isStarred)
    }

    /// 正文前若干行 —— 直接用 store 已经算好的 preview（不读盘、不扫库）。
    private func previewLines(_ note: NoteIndexItem) -> [String] {
        let raw = note.preview.split(separator: "\n", omittingEmptySubsequences: false)
        var out: [String] = []
        for line in raw {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if t.hasPrefix("#") || t.hasPrefix("---") { continue }
            out.append(String(Self.plainText(t).prefix(60)))
            if out.count >= lines { break }
        }
        return out
    }

    /// 只收笔记类文件（与编辑器判定一致）：md / markdown / mdown / mdx / txt，以及无扩展名。
    static func isNoteFile(_ id: String) -> Bool {
        let ext = (id as NSString).pathExtension.lowercased()
        if ext.isEmpty { return true }
        return ["md", "markdown", "mdown", "mdx", "txt", "text"].contains(ext)
    }

    /// 分类标签：只显示最后一级目录名（`source/image` → `image`）。
    static func folderLabel(_ category: String) -> String {
        let parts = category.split(separator: "/").map(String.init)
        return parts.last ?? _L("根目录", "Root")
    }

    /// 预览用的「素文本」：去掉常见的 Markdown 标记，卡片才像摘要而不是源码。
    static func plainText(_ line: String) -> String {
        var s = line
        for token in ["**", "__", "~~", "==", "++", "`", "*", "_", ">", "[ ]", "[x]", "[X]"] {
            s = s.replacingOccurrences(of: token, with: "")
        }
        for prefix in ["-", "•", "1.", "2.", "3.", "4.", "5."] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        guard let d = f.date(from: iso) else { return "" }
        let out = DateFormatter()
        out.dateFormat = _L("M-d HH:mm", "MMM d HH:mm")
        return out.string(from: d)
    }

    private func toggleStar(_ id: String) {
        var set = starred
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        starredRaw = set.sorted().joined(separator: "\n")
    }
}

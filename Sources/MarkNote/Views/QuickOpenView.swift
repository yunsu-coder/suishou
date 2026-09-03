import SwiftUI

/// 快速打开（⌘P，VSCode Quick Open）：按标题模糊过滤文件，↑↓ + Enter 打开，Esc 关闭。
/// 排序沿用列表时间序（最近编辑在前，VSCode 式最近打开优先的近似）。
struct QuickOpenView: View {
    @Environment(NotesStore.self) private var store
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var inputFocused: Bool

    private var items: [NoteIndexItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return store.index }
        let lower = q.lowercased()
        return store.index.filter { item in
            item.title.lowercased().contains(lower) || item.category.lowercased().contains(lower)
        }
    }

    private func categoryName(_ cat: String) -> String {
        store.categories.first(where: { $0.id == cat })?.name ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                TextField(_LL("快速打开文件（标题 / 文件夹）", "Quick Open File (Title / Folder)"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($inputFocused)
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.return) { open(); return .handled }
                    .onKeyPress(.escape) { isPresented = false; return .handled }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if items.isEmpty {
                Text(_L("没有匹配文件", "No matching files"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else {
                List(selection: Binding<Int>(get: { selection }, set: { selection = $0 })) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        QuickOpenRow(
                            item: item,
                            folder: categoryName(item.category),
                            active: item.id == store.loadedNoteID,
                            isSelected: index == selection,
                            open: {
                                store.openNote(item.id)
                                isPresented = false
                            }
                        )
                        .tag(index)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: 340)
            }
        }
        .frame(width: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color(nsColor: .separatorColor), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 4)
        .onAppear { inputFocused = true }
    }

    private func move(_ d: Int) {
        guard !items.isEmpty else { return }
        selection = (selection + d + items.count) % items.count
    }

    private func open() {
        guard items.indices.contains(selection) else { return }
        store.openNote(items[selection].id)
        isPresented = false
    }
}

/// 快速打开行（拆出以缓解类型检查）
private struct QuickOpenRow: View {
    let item: NoteIndexItem
    let folder: String
    let active: Bool
    let isSelected: Bool
    let open: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 12))
                .foregroundStyle(active ? currentTheme.accent : Color.secondary)
            Text(item.title.isEmpty ? _L("无标题", "Untitled") : item.title)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer()
            if !folder.isEmpty {
                Text(folder)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
    }
}

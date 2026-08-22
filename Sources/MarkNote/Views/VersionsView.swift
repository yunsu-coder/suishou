import SwiftUI

/// 历史版本 Sheet —— 保存时自动快照（最多 10 份，与 start 一致）
struct VersionsView: View {
    @Environment(NotesStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let noteID: String

    @State private var versions: [NotesStore.VersionInfo] = []
    @State private var expanded: String? // 展开预览的版本 ts
    @State private var versionNotes: [String: Note] = [:]
    @State private var restoreTarget: NotesStore.VersionInfo?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if versions.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                    Text("暂无历史版本")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("每次保存前会自动快照当前内容，最多保留 10 份")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                List {
                    ForEach(versions) { v in
                        versionRow(v)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 560, height: 460)
        .onAppear { reload() }
        .confirmationDialog(
            "恢复该版本？",
            isPresented: .init(get: { restoreTarget != nil }, set: { if !$0 { restoreTarget = nil } }),
            presenting: restoreTarget
        ) { _ in
            Button("恢复", role: .destructive) {
                if let t = restoreTarget {
                    store.restoreVersion(noteID, t.ts)
                    dismiss()
                }
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("当前内容将被该版本替换（当前内容会先行保存为最新快照）")
        }
    }

    private var header: some View {
        HStack {
            Text("历史版本")
                .font(.headline)
            Spacer()
            Button("关闭") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func reload() {
        versions = store.listVersions(noteID)
        versionNotes = [:]
    }

    @ViewBuilder
    private func versionRow(_ v: NotesStore.VersionInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    expanded = expanded == v.ts ? nil : v.ts
                    if versionNotes[v.ts] == nil {
                        versionNotes[v.ts] = store.versionNote(noteID, v.ts)
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(timeText(v.updated))
                            .font(.callout.weight(.medium))
                        Text(v.updated)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(fmtSize(v.size))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Image(systemName: expanded == v.ts ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            if expanded == v.ts, let note = versionNotes[v.ts] {
                Divider()
                ScrollView {
                    Text(note.content)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 170)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                .padding(.vertical, 8)
                HStack {
                    Button("恢复此版本") { restoreTarget = v }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func timeText(_ iso: String) -> String {
        guard let d = ISO8601DateFormatter().date(from: iso) else { return iso }
        return d.formatted(date: .abbreviated, time: .shortened)
    }

    private func fmtSize(_ size: Int) -> String {
        if size < 1024 { return "\(size)B" }
        if size < 1024 * 1024 { return String(format: "%.1fK", Double(size) / 1024) }
        return String(format: "%.1fM", Double(size) / 1024 / 1024)
    }
}

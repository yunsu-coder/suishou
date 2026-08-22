import SwiftUI
import AppKit
import ImageIO

/// 附件面板 —— 当前笔记全部附件：图片（缩略图网格）+ 文件（列表）
/// 操作：复制引用 / 在 Finder 显示 / 打开 / 删除
struct AttachmentsView: View {
    @Environment(NotesStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let noteID: String
    @State private var items: [NotesStore.AttachmentItem] = []
    @State private var deleteTarget: NotesStore.AttachmentItem?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("附件")
                    .font(.headline)
                Text("\(items.count) 项")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("在 Finder 中显示") {
                    NSWorkspace.shared.open(store.attachmentsDir(noteID))
                }
                .font(.caption)
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()

            if items.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("暂无附件")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("粘贴（⌘V）图片或文件、或直接把文件拖进编辑器")
                        .font(.caption).foregroundStyle(.tertiary)
                    Text("图片 → images/<noteId>/ · 文件 → attachments/<noteId>/")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        imagesSection
                        filesSection
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 640, height: 500)
        .onAppear { reload() }
        .confirmationDialog(
            "删除这个附件？",
            isPresented: Binding<Bool>(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            presenting: deleteTarget
        ) { item in
            Button("删除（文件将从磁盘移除）", role: .destructive) {
                store.deleteAttachment(item.url)
                reload()
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("正文中的引用将保留，需手动删除")
        }
    }

    private func reload() {
        items = store.listAttachments(for: noteID)
    }

    // MARK: - 图片区

    @ViewBuilder
    private var imagesSection: some View {
        let images = items.filter(\.isImage)
        if !images.isEmpty {
            Text("图片 \(images.count)")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 12)], spacing: 12) {
                ForEach(images) { item in
                    imageTile(item)
                }
            }
        }
    }

    private func imageTile(_ item: NotesStore.AttachmentItem) -> some View {
        VStack(spacing: 4) {
            Group {
                if let img = ImageLoader.thumbnail(item.url, maxPixel: 256) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 92, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture { copyReference(item) }

            Text(item.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Button { copyReference(item) } label: {
                    Image(systemName: "doc.on.clipboard").font(.caption2)
                }
                .help("复制 Markdown 引用")
                .buttonStyle(.plain)
                Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                    Image(systemName: "magnifyingglass").font(.caption2)
                }
                .help("在 Finder 中显示")
                .buttonStyle(.plain)
                Button(role: .destructive) { deleteTarget = item } label: {
                    Image(systemName: "trash").font(.caption2)
                }
                .help("删除")
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 文件区

    @ViewBuilder
    private var filesSection: some View {
        let files = items.filter { !$0.isImage }
        if !files.isEmpty {
            Text("文件 \(files.count)")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(files) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "doc")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            Text("\(fmtSize(item.size)) · \(item.mtime.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button("打开") { NSWorkspace.shared.open(item.url) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button { copyReference(item) } label: {
                            Image(systemName: "doc.on.clipboard").font(.caption)
                        }
                        .help("复制 Markdown 引用")
                        .buttonStyle(.plain)
                        Button(role: .destructive) { deleteTarget = item } label: {
                            Image(systemName: "trash").font(.caption)
                        }
                        .help("删除")
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    if item.id != files.last?.id {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func copyReference(_ item: NotesStore.AttachmentItem) {
        let relative = item.isImage
            ? "images/\(noteID)/\(item.url.lastPathComponent)"
            : "attachments/\(noteID)/\(item.url.lastPathComponent)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.isImage ? "![图片](\(relative))" : "[\(item.name)](\(relative))", forType: .string)
    }

    private func fmtSize(_ size: Int) -> String {
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return String(format: "%.1f KB", Double(size) / 1024) }
        return String(format: "%.1f MB", Double(size) / 1024 / 1024)
    }
}

/// ImageIO 缩略图解码 —— 附件面板网格几十张图时不整图解码（内存大头）
enum ImageLoader {
    static func thumbnail(_ url: URL, maxPixel: Int) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

/// 预览内点击图片 → 大图查看
struct ImageZoomView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var rotate = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(url.lastPathComponent)
                    .font(.headline)
                Spacer()
                Button {
                    rotate = (rotate + 1) % 4
                } label: {
                    Image(systemName: "rotate.right")
                }
                .help("旋转 90°")
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            ZStack {
                Color.black.opacity(0.4)
                if let img = NSImage(contentsOf: url) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .rotationEffect(.degrees(Double(rotate) * 90))
                        .padding(16)
                } else {
                    Text("图片无法加载")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 520, minHeight: 400)
    }
}

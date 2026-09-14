import AppKit
import AVKit
import SwiftUI

/// AppKit AVPlayerView 封装（SwiftUI VideoPlayer 在 macOS 上不稳，这版是应用里验证过的做法）。
struct MediaPlayerBox: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = .inline
        v.player = AVPlayer(url: url)
        v.player?.play()
        return v
    }

    func updateNSView(_ v: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ v: AVPlayerView, coordinator: ()) {
        v.player?.pause()
        v.player = nil
    }
}

/// 通用媒体预览弹窗：图片可缩放（适应窗口 / 100% / 滑杆），视频可直接播放。
/// 采集候选（远程）与素材库（本地文件）共用。
struct MediaPreviewSheet: View {
    let title: String
    var subtitle: String?
    /// 图片地址（图片本身；视频候选传封面）
    var imageURL: URL?
    /// 可直接播放的视频地址（本地文件或直链 mp4/webm）
    var videoURL: URL?
    /// 原始页面（打开原图 / 看来源）
    var pageURL: URL?
    /// 额外操作按钮（例如采集里的「选中/取消」）
    var extra: AnyView?

    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var natural: CGSize?
    @State private var loaded: NSImage?
    @State private var fitScale: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 620, minHeight: 460)
        .background(Color(nsColor: appAppearance.editorBackground))
        .task { await loadImage() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if videoURL != nil {
                Text(_L("可直接播放", "Playable"))
                    .font(.system(size: 10))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(appAppearance.accent.opacity(0.16)))
                    .foregroundStyle(appAppearance.accent)
            }
            if let natural {
                Text("\(Int(natural.width))×\(Int(natural.height))")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            if let extra { extra }
            if let pageURL {
                Button(_L("打开来源", "Open source")) {
                    NSWorkspace.shared.open(pageURL)
                }
                .controlSize(.small)
            }
            Button(_L("关闭", "Close")) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if let videoURL {
            MediaPlayerBox(url: videoURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.92))
        } else if let loaded {
            ZStack {
                Color(nsColor: appAppearance.editorBackground)
                GeometryReader { geo in
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: loaded)
                            .resizable()
                            .frame(width: (natural?.width ?? loaded.size.width) * zoom,
                                   height: (natural?.height ?? loaded.size.height) * zoom)
                            .padding(12)
                    }
                    .onAppear { fitScale = fit(for: geo.size) ; zoom = fitScale }
                    .onChange(of: geo.size) { _, size in
                        fitScale = fit(for: size)
                        // 还没手动缩放过 → 一直保持「适应窗口」
                        if abs(zoom - fitScale) < 0.0001 || zoom == 1 { zoom = fitScale }
                    }
                }
            }
            Divider()
            zoomBar
        } else {
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(_L("正在加载…", "Loading…"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var zoomBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
            Slider(value: Binding(get: { Double(zoom) },
                                  set: { zoom = CGFloat($0) }), in: 0.2...4)
                .frame(width: 200)
            Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
            Text("\(Int((zoom * 100).rounded()))%")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
            Button(_L("适应窗口", "Fit")) { zoom = fitScale }
                .controlSize(.small)
            Button("100%") { zoom = 1 }
                .controlSize(.small)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func fit(for size: CGSize) -> CGFloat {
        guard let natural, natural.width > 1, natural.height > 1 else { return 1 }
        return min((size.width - 28) / natural.width, (size.height - 28) / natural.height)
    }

    private func loadImage() async {
        guard let imageURL else { return }
        if imageURL.isFileURL {
            guard let img = NSImage(contentsOf: imageURL) else { return }
            loaded = img
            natural = img.pixelSize ?? img.size
            return
        }
        // 远程（采集候选）：走 URLSession，失败时退回缩略图
        var req = URLRequest(url: imageURL)
        req.timeoutInterval = 25
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
                     + "(KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let img = NSImage(data: data) else { return }
        loaded = img
        natural = img.pixelSize ?? img.size
    }
}

extension NSImage {
    /// 真实像素尺寸（NSImage.size 可能被 DPI 缩放）
    var pixelSize: CGSize? {
        guard let rep = representations.first else { return nil }
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }
}

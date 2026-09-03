import SwiftUI
import AppKit
import ImageIO

/// 预览内点击图片 → 大图查看（原定义在 AttachmentsView.swift，附件面板移除后独立成文件）
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
                .help(_L("旋转 90°", "Rotate 90°"))
                Button(_LL("关闭", "Close")) { dismiss() }
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
                    Text(_LL("图片无法加载", "Cannot load image"))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 520, minHeight: 400)
    }
}

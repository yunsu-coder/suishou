import SwiftUI
import AppKit

/// 主题语义图标：插件主题声明 `icons` 映射时优先显示专属资源，否则回退 SF Symbol。
/// 像素图按原始尺寸等比放大并使用 nearest-neighbor，保证 16px 图标不糊。
struct ThemeIcon: View {
    let name: String
    let fallback: String
    var size: CGFloat = 16

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Group {
            if let image = themeIconImage(name) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: fallback)
                    .font(.system(size: size * 0.8, weight: .semibold))
            }
        }
        .scaleEffect(bounceEnabled && hovering ? 1.12 : 1)
        .animation(bounceEnabled ? .spring(response: appAppearance.motion?.duration ?? 0.28,
                                           dampingFraction: 0.68) : nil,
                   value: hovering)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
    }

    private var bounceEnabled: Bool {
        guard appAppearance.motion?.iconBounce == true else { return false }
        if reduceMotion && (appAppearance.motion?.respectReduceMotion ?? true) { return false }
        return true
    }
}

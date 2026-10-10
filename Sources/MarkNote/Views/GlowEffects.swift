import SwiftUI
import AppKit

/// 界面光效 —— 参考成熟桌面软件的"取景高光"做法（Linear / Raycast 的光标聚光、
/// macOS 焦点环的柔光），原则只有三条：
/// 1. **极低存在感**：透明度 4%–8%，只在深色/浅色底上都"刚好看得见"；
/// 2. **不抢注意力**：不闪、不循环、不做位移，只在"用户在操作的地方"亮一下；
/// 3. **可关 + 无障碍**：设置里一键关（FeatureModules.visualGlow），
///    系统"减少动态效果 / 降低透明度"时自动让路（静态或直接不画）。
enum GlowEffects {
    static let spotlightRadius: CGFloat = 260
    static let spotlightAlpha: Double = 0.07      // 深色主题
    static let spotlightAlphaLight: Double = 0.05 // 浅色主题（亮底上更克制）

    /// 拉条拖动中：暂停跟随光斑 —— 否则拖动时光斑在文字上带 0.18s 缓动滑动，观感很糟
    static var handleDragActive = false

    /// 现在该不该画光效
    static func isEnabled(reduceMotion: Bool, reduceTransparency: Bool) -> Bool {
        guard FeatureModules.isEnabled(FeatureModules.visualGlow) else { return false }
        if reduceTransparency { return false }     // 降低透明度：不叠加任何光
        return true
    }
}

/// 光标聚光：鼠标在工作区上移动时，落点周围有一团极淡的主题色光。
/// 只覆盖编辑/预览这一块，不铺满全窗（铺满会显得"脏"）。
struct SpotlightOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var point: CGPoint?

    var body: some View {
        GeometryReader { geo in
            if GlowEffects.isEnabled(reduceMotion: reduceMotion, reduceTransparency: reduceTransparency),
               !GlowEffects.handleDragActive,
               NSEvent.pressedMouseButtons == 0 {   // 任何按住拖动（拉条 / 划选文字）期间光斑让路
                let r = GlowEffects.spotlightRadius
                let alpha = appAppearance.dark ? GlowEffects.spotlightAlpha : GlowEffects.spotlightAlphaLight
                RadialGradient(
                    gradient: Gradient(colors: [
                        appAppearance.accent.opacity(alpha),
                        appAppearance.accent.opacity(alpha * 0.45),
                        .clear,
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: r
                )
                .frame(width: r * 2, height: r * 2)
                .position(point ?? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
                .opacity(point == nil ? 0 : 1)
                .animation(.easeOut(duration: 0.18), value: point)
                .blendMode(appAppearance.dark ? .plusLighter : .multiply)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p): point = p
                    case .ended: point = nil
                    }
                }
            }
        }
        .allowsHitTesting(false)   // 只做装饰，绝不能挡住鼠标与拖拽
    }
}

/// 面板接缝高光：面板与主区之间那条分隔线，用主题色做一段渐隐光带
/// （比纯 1px Divider 更有层次，但依然是一条线，不占视觉重量）。
struct SeamGlow: View {
    var edge: Edge = .top

    var body: some View {
        LinearGradient(
            colors: [appAppearance.accent.opacity(0.28),
                     appAppearance.accent.opacity(0.06),
                     .clear],
            startPoint: edge == .top ? .leading : .trailing,
            endPoint: edge == .top ? .trailing : .leading
        )
        .frame(height: 1)
    }
}

/// 保存脉冲：保存完成时给对勾罩一层柔光，400ms 淡出（不循环、不位移）
struct GlowPulse: ViewModifier {
    /// 触发值（每次保存变化）
    var trigger: Date?
    var color: Color
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .background {
                Circle()
                    .fill(color.opacity(on ? 0.0 : 0.35))
                    .scaleEffect(on ? 2.1 : 0.9)
                    .blur(radius: 3)
                    .allowsHitTesting(false)
            }
            .onChange(of: trigger) { _, _ in
                on = false
                withAnimation(.easeOut(duration: 0.4)) { on = true }
            }
    }
}

extension View {
    func glowPulse(trigger: Date?, color: Color) -> some View {
        modifier(GlowPulse(trigger: trigger, color: color))
    }
}

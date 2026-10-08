import SwiftUI

/// 全局动效系统 —— 参数不是拍脑袋来的，取自两份成熟规范 + 一处系统实测：
///
/// 1. **Material 3 motion tokens**（material-components-android/docs/theming/Motion.md）
///    · 时长：Short1 50ms / Short2 100ms / Short3 150ms / Short4 200ms /
///            Medium1 250ms / Medium2 300ms / Long1 450ms …
///    · 缓动：Standard `cubic-bezier(0.2, 0, 0, 1)`（起止都在屏幕内的动画）
///            Emphasized decelerate `cubic-bezier(0.05, 0.7, 0.1, 1)`（进场）
///            Emphasized accelerate `cubic-bezier(0.3, 0, 0.8, 0.15)`（退场）
///            Container transform：进场 300ms / 退场 250ms
/// 2. **macOS 原生节奏**：`NSAnimationContext` 默认时长 0.25s（实测取值），
///    所以面板这类结构动画落在 0.25–0.30s 才"像系统"。
/// 3. **Apple HIG**：减少动态效果时不要"没有反馈"，而是去掉位移/缩放、保留淡入淡出，
///    并把时长压短 —— 下面的 reduceMotion 分支就是这么做的（不再返回 nil）。
enum AppMotion {

    // MARK: - 结构变化（面板、侧栏、分栏）：M3 Standard + Medium2(300ms)
    static func panel(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.16)
                     : .timingCurve(0.2, 0, 0, 1, duration: 0.30)
    }

    /// 面板位移形态：减少动态效果 → 只淡，不滑（HIG 要求）
    static func panelTransition(_ reduceMotion: Bool, edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity
                     : .move(edge: edge).combined(with: .opacity)
    }

    // MARK: - 内容替换（换笔记、换素材、切视图模式）：M3 Standard + Short4(200ms)
    static func content(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.14)
                     : .timingCurve(0.2, 0, 0, 1, duration: 0.20)
    }

    static func contentTransition(_ reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity
                     : .opacity.combined(with: .offset(y: 8))
    }

    // MARK: - 列表项（标签页、素材条）：M3 Standard + Short3(150ms)/Short4(200ms)
    static func item(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12)
                     : .timingCurve(0.2, 0, 0, 1, duration: 0.18)
    }

    static func itemTransition(_ reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity
                     : .scale(scale: 0.92, anchor: .center).combined(with: .opacity)
    }

    // MARK: - 微交互（数字、状态点、选中态）：M3 Short2–Short3
    static func micro(_ reduceMotion: Bool) -> Animation {
        .easeOut(duration: reduceMotion ? 0.10 : 0.14)
    }
}

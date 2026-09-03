import SwiftUI
import AppKit

/// 桌面壁纸毛玻璃（设置「毛玻璃强度」windowGlass 0–1，默认 0 = 关闭）：
///
/// - `Glass.Window`：把承载窗口改为非不透明 + titlebar 透明 —— 壁纸从此可见；
/// - `Glass.Backdrop`：窗口内容底部垫一张 `behindWindow` NSVisualEffectView，
///   alphaValue = 强度 —— 壁纸先被模糊再与壁纸本体按强度混合（可读性有底、壁纸可辨）。
/// 两个视图挂载在 ContentView 根上即可；Settings 独立场景不挂载，保持不透明。
enum Glass {
    /// 设置键：毛玻璃强度 0–1（0 = 关闭毛玻璃，保持原有不透明观感）
    static let key = "windowGlass"

    /// 承载窗口改造（挂在 ContentView background；settings 窗口不挂）
    struct Window: NSViewRepresentable {
        var enabled: Bool

        final class Coordinator {
            weak var hostWindow: NSWindow?
        }

        /// 创建时窗口可能尚未 attach（updateNSView 拿到 v.window == nil 后无人重试）——
        /// 用 didMoveToWindow 兜住「挂上窗口」那一刻即时配置
        final class ConfiguringView: NSView {
            var apply: ((NSWindow?) -> Void)?
            override func viewDidMoveToWindow() {
                if !isHidden { apply?(window) } // isHidden 时可能还没挂载，退到 updateNSView 重试
            }
        }

        func makeCoordinator() -> Coordinator { Coordinator() }

        func makeNSView(context: Context) -> NSView {
            let v = ConfiguringView()
            v.apply = { [weak coordinator = context.coordinator] win in
                guard let win, enabled else { return }
                coordinator?.hostWindow = win
                Self.apply(win, enabled: true)
            }
            return v
        }

        func updateNSView(_ v: NSView, context: Context) {
            guard let win = context.coordinator.hostWindow ?? v.window else { return }
            context.coordinator.hostWindow = win
            Self.apply(win, enabled: enabled)
        }

        static func apply(_ win: NSWindow, enabled: Bool) {
            if enabled {
                win.isOpaque = false
                win.backgroundColor = .clear
                win.titlebarAppearsTransparent = true
            } else {
                win.isOpaque = true
                win.backgroundColor = .windowBackgroundColor
                win.titlebarAppearsTransparent = false
            }
        }
    }

    /// behindWindow 模糊垫层：alphaValue = 强度；0 时不可见
    struct Backdrop: NSViewRepresentable {
        var alpha: Double

        func makeNSView(context: Context) -> NSVisualEffectView {
            let v = NSVisualEffectView()
            v.material = .underWindowBackground // 轻度模糊：壁纸大体可辨
            v.blendingMode = .behindWindow
            v.state = .active
            return v
        }

        func updateNSView(_ v: NSVisualEffectView, context: Context) {
            v.alphaValue = alpha
        }
    }
}

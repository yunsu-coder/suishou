import SwiftUI
import AppKit

/// 可拖拽面板分隔条（素材面板在下方沿、终端面板在上方沿都用它）。
///
/// 之前每处各写一版、只给 8pt 命中区 + 默认 `DragGesture`（要移动几像素才触发），
/// 结果就是"很难拖到"。这里统一成：
/// - **整条线都是命中区**（12pt 高，全宽 `contentShape`）
/// - `minimumDistance: 0`：按下即开始跟手，不用先"蹭"几像素
/// - hover 时线变主题色、抓手变明显，并提供上下箭头光标
/// - **双击复位**到默认高度（macOS 分栏的惯例）
struct PanelResizeHandle: View {
    @Binding var height: Double
    var minHeight: Double = 240
    var maxHeight: Double = 900
    var defaultHeight: Double = 480
    /// 面板在下方（终端）时，向下拖应当是"变矮" → 取反
    var inverted = false
    /// 需要避让的红绿灯区域？素材面板在编辑区，不需要
    var help: String?

    @State private var base: Double?
    @State private var hovering = false

    var body: some View {
        ZStack {
            Rectangle().fill(Color.clear)
            Rectangle()
                .fill(hovering ? appAppearance.accent.opacity(0.55) : Color(nsColor: .separatorColor))
                .frame(height: hovering ? 2 : 1)
            Capsule()
                .fill(hovering ? appAppearance.accent.opacity(0.75) : Color.secondary.opacity(0.35))
                .frame(width: 56, height: 4)
                .opacity(hovering ? 1 : 0.7)
        }
        .frame(height: 12)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if base == nil { base = height }
                    let b = base ?? height
                    let delta = inverted ? -v.translation.height : v.translation.height
                    height = min(maxHeight, max(minHeight, b + delta))
                }
                .onEnded { _ in base = nil }
        )
        .onTapGesture(count: 2) { height = defaultHeight }   // 双击复位
        .help(help ?? _L("拖动调整高度，双击复位", "Drag to resize, double-click to reset"))
    }
}

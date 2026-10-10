import SwiftUI
import AppKit

/// 面板分隔条方向：vertical = 上下拖调「高度」；horizontal = 左右拖调「宽度」
enum PanelResizeAxis { case vertical, horizontal }

/// 可拖拽面板分隔条（侧栏、编辑｜预览分栏、素材面板、终端面板共用）。
///
/// 之前每处各写一版、只给 8pt 命中区 + 默认 `DragGesture`（要移动几像素才触发），
/// 结果就是"很难拖到"。这里统一成：
/// - **整条线都是命中区**（12pt 粗细，全宽 / 全高 `contentShape`）
/// - `minimumDistance: 0`：按下即开始跟手，不用先"蹭"几像素
/// - hover 时线变主题色、抓手变明显，并提供对应方向的光标
/// - **双击复位**到默认值（macOS 分栏的惯例）
/// - 拖动期间只写调用方的内存草稿，松手才触发 `onCommit` 落盘（防拖动抖动）
struct PanelResizeHandle: View {
    @Binding var value: Double
    var minValue: Double = 240
    var maxValue: Double = 900
    var defaultValue: Double = 480
    var axis: PanelResizeAxis = .vertical
    /// 面板在下方（终端）时，向下拖应当是"变矮" → 取反
    var inverted = false
    /// 拖动结束回调（把内存草稿一次落盘）
    var onCommit: (() -> Void)?
    /// 拖动开始 / 结束回调（终端用它挂起尺寸通知等）
    var onDragChange: ((Bool) -> Void)?
    var help: String?

    @State private var base: Double?
    @State private var hovering = false
    @State private var dragging = false

    private var vertical: Bool { axis == .vertical }
    /// 悬停或拖动中都算"活" —— 拖动过程手柄保持高亮，给出正在操作的反馈
    private var active: Bool { hovering || dragging }

    var body: some View {
        ZStack {
            Rectangle().fill(Color.clear)
            Rectangle()
                .fill(active ? appAppearance.accent.opacity(dragging ? 0.8 : 0.55) : Color(nsColor: .separatorColor))
                .frame(width: vertical ? nil : (active ? 2 : 1),
                       height: vertical ? (active ? 2 : 1) : nil)
            Capsule()
                .fill(active ? appAppearance.accent.opacity(0.75) : Color.secondary.opacity(0.35))
                .frame(width: vertical ? 56 : 4, height: vertical ? 4 : 56)
                .opacity(active ? 1 : 0.7)
        }
        .frame(width: vertical ? nil : 12, height: vertical ? 12 : nil)
        .frame(maxWidth: vertical ? .infinity : nil, maxHeight: vertical ? nil : .infinity)
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside { (vertical ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).push() } else { NSCursor.pop() }
        }
        .gesture(
            // 用**全局坐标系**：手柄在拖动中会随面板移动，若按 view 自身坐标系取平移量，
            // 每帧的值会互相抵消/回弹（表现为"拖不动的抖动/橡皮筋"）。全局坐标 = 纯鼠标位移。
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { v in
                    GlowEffects.handleDragActive = true
                    if base == nil {
                        base = value
                        dragging = true
                        onDragChange?(true)
                    }
                    let raw = vertical ? v.translation.height : v.translation.width
                    let delta = inverted ? -raw : raw
                    value = min(maxValue, max(minValue, (base ?? value) + delta))
                }
                .onEnded { _ in
                    base = nil
                    dragging = false
                    onDragChange?(false)
                    GlowEffects.handleDragActive = false
                    onCommit?()
                }
        )
        .onTapGesture(count: 2) {
            value = defaultValue
            onCommit?()
        }   // 双击复位
        .help(help ?? _L("拖动调整大小，双击复位", "Drag to resize, double-click to reset"))
    }
}

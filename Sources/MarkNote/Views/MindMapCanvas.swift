import AppKit
import SwiftUI

/// 思维导图画布：只负责「画」与「换算坐标」。
/// 颜色全部取自主题（`appAppearance`），分支色由主题 accent 派生，任何主题下都协调。
struct MindMapCanvas: View {
    let boxes: [MindMapBox]
    let edges: [MindMapEdge]
    let selectedID: String?
    let zoom: CGFloat
    let offset: CGSize
    /// 正在悬停 / 拖拽吸附的节点（高亮用）
    let dropTargetID: String?

    /// 画布坐标 → 屏幕坐标
    func screen(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * zoom + offset.width, y: p.y * zoom + offset.height)
    }

    /// 屏幕坐标 → 画布坐标
    func canvas(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - offset.width) / zoom, y: (p.y - offset.height) / zoom)
    }

    var body: some View {
        let bg = Color(nsColor: appAppearance.editorBackground)
        let text = Color(nsColor: appAppearance.editorForeground)
        let font = MindMapStyle.font(depth: 0)
        Canvas { ctx, size in
            // 背景
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bg))
            drawDots(&ctx, size: size)
            drawEdges(&ctx)
            drawNodes(&ctx)
        }
        .background(bg)
        .environment(\.font, Font(font))
    }

    // MARK: - 网格

    private func drawDots(_ ctx: inout GraphicsContext, size: CGSize) {
        let step: CGFloat = 24 * zoom
        guard step >= 7 else { return }
        let dot = Color(nsColor: appAppearance.editorForeground).opacity(0.10)
        let startX = offset.width.truncatingRemainder(dividingBy: step)
        let startY = offset.height.truncatingRemainder(dividingBy: step)
        var x = startX - step
        while x < size.width {
            var y = startY - step
            while y < size.height {
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.6, height: 1.6)), with: .color(dot))
                y += step
            }
            x += step
        }
    }

    // MARK: - 连线

    private func drawEdges(_ ctx: inout GraphicsContext) {
        for edge in edges {
            var path = Path()
            path.move(to: screen(edge.from))
            path.addCurve(to: screen(edge.to),
                          control1: screen(edge.control1),
                          control2: screen(edge.control2))
            let color = Color(nsColor: MindMapStyle.branchColor(edge.accent)).opacity(0.55)
            ctx.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: max(1.2, 2.4 * zoom), lineCap: .round))
        }
    }

    // MARK: - 节点

    private func drawNodes(_ ctx: inout GraphicsContext) {
        for box in boxes {
            let rect = CGRect(x: box.rect.minX * zoom + offset.width,
                              y: box.rect.minY * zoom + offset.height,
                              width: box.rect.width * zoom,
                              height: box.rect.height * zoom)
            let selected = box.id == selectedID
            let isDrop = box.id == dropTargetID
            MindMapStyle.drawNode(&ctx, box: box, rect: rect, zoom: zoom,
                                  selected: selected, isDropTarget: isDrop)
        }
    }
}

/// 画布样式（全部走主题变量；只有分支色是主题 accent 的派生色）
enum MindMapStyle {
    static func font(depth: Int) -> NSFont {
        let size: CGFloat = depth == 0 ? 15 : (depth == 1 ? 13.5 : 12.5)
        let weight: NSFont.Weight = depth == 0 ? .semibold : (depth == 1 ? .medium : .regular)
        if let family = appAppearance.uiFontFamily, !family.isEmpty,
           let f = NSFont(name: family, size: size) {
            return NSFontManager.shared.convert(f, toHaveTrait: weight == .regular ? [] : .boldFontMask)
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func branchColor(_ index: Int) -> NSColor {
        MindMapPalette.branch(index, base: appAppearance.accentNS, dark: appAppearance.dark)
    }

    /// 文本色：浅底深字、深底浅字由主题给
    static var textColor: NSColor { appAppearance.editorForeground }

    static func drawNode(_ ctx: inout GraphicsContext, box: MindMapBox, rect: CGRect,
                         zoom: CGFloat, selected: Bool, isDropTarget: Bool) {
        let color = branchColor(box.accent)
        let radius: CGFloat = box.depth == 0 ? 12 * zoom : 8 * zoom
        let path = Path(roundedRect: rect, cornerRadius: radius)

        // 底：根节点用实色，一级分支浅色，深层更浅
        let fillOpacity: Double = box.depth == 0 ? 1.0 : (box.depth == 1 ? 0.16 : 0.10)
        ctx.fill(path, with: .color(Color(nsColor: color).opacity(fillOpacity)))
        // 描边：一级分支用分支色，深层用低透明
        let strokeOpacity: Double = box.depth == 0 ? 1.0 : (box.depth == 1 ? 0.85 : 0.45)
        ctx.stroke(path, with: .color(Color(nsColor: color).opacity(strokeOpacity)),
                   style: StrokeStyle(lineWidth: max(1, (box.depth == 0 ? 1.6 : 1.2) * zoom)))

        // 文字：根节点在实色底上用白/黑（按对比度挑），其余用主题正文色
        let textNS: NSColor = box.depth == 0
            ? (PluginCSS.luminance(color) < 0.5 ? .white : .black)
            : textColor
        let font = font(depth: box.depth)
        let padX: CGFloat = (box.depth == 0 ? 20 : 14) * zoom
        let textRect = CGRect(x: rect.minX + padX, y: rect.minY,
                              width: max(rect.width - padX * 2, 1), height: rect.height)
        var text = ctx
        text.clip(to: Path(textRect))
        var attr = AttributedString(box.text.isEmpty ? " " : box.text)
        attr.font = Font(font)
        attr.foregroundColor = Color(nsColor: textNS)
        text.draw(text.resolve(Text(attr)),
                  in: CGRect(x: textRect.minX, y: rect.midY - font.pointSize * 0.75,
                             width: textRect.width, height: font.pointSize * 1.6))

        // 选中 / 拖拽落点高亮
        if selected || isDropTarget {
            let ring = Path(roundedRect: rect.insetBy(dx: -3 * zoom, dy: -3 * zoom),
                            cornerRadius: radius + 3 * zoom)
            ctx.stroke(ring, with: .color(Color(nsColor: appAppearance.accentNS)
                .opacity(isDropTarget ? 0.95 : 0.7)),
                       style: StrokeStyle(lineWidth: max(1.4, 2 * zoom),
                                          dash: isDropTarget ? [5, 3] : []))
        }

        // 折叠标记：有子节点但折叠了 → 外侧画个「+N」
        if box.collapsed, box.childCount > 0 {
            let r: CGFloat = 9 * zoom
            let center = CGPoint(x: box.side >= 0 ? rect.maxX + r + 4 * zoom
                                                   : rect.minX - r - 4 * zoom,
                                 y: rect.midY)
            let circle = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r,
                                                width: r * 2, height: r * 2))
            ctx.fill(circle, with: .color(Color(nsColor: appAppearance.accentNS).opacity(0.18)))
            ctx.stroke(circle, with: .color(Color(nsColor: appAppearance.accentNS).opacity(0.8)),
                       lineWidth: max(1, zoom))
            var badge = ctx
            var attr = AttributedString("+\(box.childCount)")
            attr.font = Font.system(size: 9 * zoom, weight: .semibold)
            attr.foregroundColor = Color(nsColor: appAppearance.accentNS)
            badge.draw(Text(attr), at: center, anchor: .center)
            _ = badge
        }
    }
}

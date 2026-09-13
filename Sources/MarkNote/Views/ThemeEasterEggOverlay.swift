import SwiftUI

/// 主题彩蛋：符号雨 + 中央提示；由主题包的 easterEgg 配置驱动。
struct ThemeEasterEggOverlay: View {
    let symbols: [String]
    let message: String?

    @State private var falling = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(appAppearance.accent, in: Capsule())
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                        .position(x: geo.size.width / 2,
                                  y: falling ? geo.size.height * 0.46 : geo.size.height * 0.32)
                        .opacity(falling ? 1 : 0)
                        .animation(.spring(response: 0.45, dampingFraction: 0.68), value: falling)
                }
                ForEach(0..<28, id: \.self) { i in
                    Text(symbols.isEmpty ? "✨" : symbols[i % symbols.count])
                        .font(.system(size: 18 + CGFloat(i % 4) * 5))
                        .position(x: geo.size.width * fraction(i),
                                  y: falling ? geo.size.height + 60 : -60)
                        .animation(.easeIn(duration: 1.15 + Double(i % 5) * 0.09)
                                    .delay(Double(i % 7) * 0.05), value: falling)
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { falling = true }
    }

    /// 确定性伪随机横坐标（每次彩蛋一致，避免重排闪烁）。
    private func fraction(_ i: Int) -> CGFloat {
        let v = sin(Double(i) * 12.9898) * 43758.5453
        return CGFloat(v - floor(v))
    }
}

// MARK: - 主题氛围层（单 Canvas + 低帧率；打字期间暂停）
//
// 血泪教训：这里原来是「每个粒子一个 .repeatForever 动画」——
// SwiftUI 必须为这些永不结束的动画持续 60fps 重渲染整窗，
// 应用**空闲时 CPU 就 100%**（实测），打字叠加每键重排 → 直接卡死。
// 现在：一个 Canvas 一次画完全部粒子（12fps），编辑器一有输入就整层暂停。

extension Notification.Name {
    /// 编辑器敲键（氛围动效据此暂停）
    static let marknoteEditorTyping = Notification.Name("marknote.editor.typing")
}

private enum AmbientParticle { case bubble, petal, ink, pixel }
private enum AmbientShape { case circle, square, petal }

/// 花瓣形状（雾青主题氛围粒子）
struct PetalShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY + h),
                       control: CGPoint(x: rect.minX + w * 1.25, y: rect.minY + h * 0.5))
        p.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY),
                       control: CGPoint(x: rect.minX - w * 0.25, y: rect.minY + h * 0.5))
        p.closeSubpath()
        return p
    }
}

struct ThemeAmbientLayer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var typing = false
    @State private var typingResetTask: Task<Void, Never>?

    var body: some View {
        let motion = appAppearance.motion
        let animated = motion != nil && !(reduceMotion && (motion?.respectReduceMotion ?? true))
        if animated {
            TimelineView(.periodic(from: .now, by: typing ? 1.5 : 1.0 / 12.0)) { timeline in
                Canvas { ctx, size in
                    draw(ctx: &ctx, size: size, t: timeline.date.timeIntervalSinceReferenceDate,
                         motion: motion)
                }
                .allowsHitTesting(false)
            }
            .onReceive(NotificationCenter.default.publisher(for: .marknoteEditorTyping)) { _ in
                typing = true
                typingResetTask?.cancel()
                typingResetTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    guard !Task.isCancelled else { return }
                    typing = false
                }
            }
            .onDisappear { typingResetTask?.cancel() }
        }
    }

    private func draw(ctx: inout GraphicsContext, size: CGSize, t: Double, motion: ThemeMotion?) {
        guard size.width > 1, size.height > 1, let motion else { return }
        if motion.scanlines { Self.drawScanlines(ctx: &ctx, size: size) }
        var counters: [Int: Int] = [:]
        func nextIndex(_ kind: AmbientParticle) -> Int {
            let key = kindKey(kind)
            let i = counters[key, default: 0]
            counters[key] = i + 1
            return i
        }
        if motion.ambientInk {
            for i in 0..<9 {
                rising(&ctx, size: size, t: t, index: i, seed: 41.117,
                       duration: 9.0 + Double(i % 4) * 1.6, delay: Double(i) * 0.6,
                       particle: 10 + CGFloat(i % 4) * 10,
                       opacity: 0.035 + Double(i % 3) * 0.012, shape: .circle)
            }
            _ = nextIndex(.ink)
        }
        if motion.ambientBubbles {
            for i in 0..<12 {
                rising(&ctx, size: size, t: t, index: i, seed: 37.719,
                       duration: 7.5 + Double(i % 5) * 1.1, delay: Double(i) * 0.35,
                       particle: 9 + CGFloat(i % 4) * 7,
                       opacity: 0.04 + Double(i % 3) * 0.018, shape: .circle)
            }
        }
        if motion.ambientPollen {
            for i in 0..<14 {
                rising(&ctx, size: size, t: t, index: i, seed: 27.331,
                       duration: 11.0 + Double(i % 5) * 1.8, delay: Double(i) * 0.45,
                       particle: 7 + CGFloat(i % 4) * 4,
                       opacity: 0.05 + Double(i % 3) * 0.016, shape: .petal)
            }
        }
        if motion.ambientPixels {
            for i in 0..<10 {
                rising(&ctx, size: size, t: t, index: i, seed: 19.913,
                       duration: 8.0 + Double(i % 4) * 1.4, delay: Double(i) * 0.5,
                       particle: 4 + CGFloat(i % 3) * 3,
                       opacity: 0.05 + Double(i % 3) * 0.02, shape: .square)
            }
        }
    }

    private func kindKey(_ kind: AmbientParticle) -> Int {
        switch kind {
        case .bubble: return 1
        case .petal: return 2
        case .ink: return 3
        case .pixel: return 4
        }
    }

    private static func fraction(_ i: Int, _ seed: Double) -> CGFloat {
        let v = sin(Double(i) * seed) * 43758.5453
        return CGFloat(v - floor(v))
    }

    private static func drawScanlines(ctx: inout GraphicsContext, size: CGSize) {
        let color = appAppearance.accent.opacity(0.05)
        var y: CGFloat = 0
        while y < size.height {
            ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(color))
            y += 3
        }
    }

    /// 一个粒子：从底部匀速上浮，到顶循环（对应旧版的 repeatForever + delay）
    private func rising(_ ctx: inout GraphicsContext, size: CGSize, t: Double,
                        index i: Int, seed: Double, duration: Double, delay: Double,
                        particle: CGFloat, opacity: Double, shape: AmbientShape) {
        let phase = ((t + delay).truncatingRemainder(dividingBy: duration)) / duration
        let margin = particle + 24
        let y = size.height + margin - (size.height + margin * 2) * phase
        let x = size.width * Self.fraction(i, seed)
        let w = particle
        let h = shape == .petal ? particle * 1.3 : particle
        let rect = CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)
        let paint = GraphicsContext.Shading.color(appAppearance.accent.opacity(opacity))
        switch shape {
        case .circle:
            ctx.fill(Path(ellipseIn: rect), with: paint)
        case .square:
            ctx.fill(Path(rect), with: paint)
        case .petal:
            var layer = ctx
            layer.translateBy(x: rect.midX, y: rect.midY)
            layer.rotate(by: .degrees(Double(i * 37 % 360)))
            layer.translateBy(x: -rect.midX, y: -rect.midY)
            layer.fill(PetalShape().path(in: rect), with: paint)
        }
    }
}

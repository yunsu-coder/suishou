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

/// 主题氛围特效：低透明度糖果气泡缓慢上浮。
/// 仅用 SwiftUI 动画（无定时器、无 Canvas 重绘），默认尊重系统“减少动态效果”。
struct ThemeAmbientBubbles: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rising = false

    var body: some View {
        if enabled {
            GeometryReader { geo in
                ZStack {
                    ForEach(0..<12, id: \.self) { i in
                        Circle()
                            .fill(appAppearance.accent.opacity(0.04 + Double(i % 3) * 0.018))
                            .frame(width: 9 + CGFloat(i % 4) * 7)
                            .position(x: geo.size.width * fraction(i),
                                      y: rising ? -24 : geo.size.height + 24)
                            .animation(.linear(duration: 7.5 + Double(i % 5) * 1.1)
                                        .repeatForever(autoreverses: false)
                                        .delay(Double(i) * 0.35),
                                       value: rising)
                    }
                }
                .onAppear { rising = true }
            }
            .allowsHitTesting(false)
        }
    }

    private var enabled: Bool {
        guard appAppearance.motion?.ambientBubbles == true else { return false }
        if reduceMotion && (appAppearance.motion?.respectReduceMotion ?? true) { return false }
        return true
    }

    private func fraction(_ i: Int) -> CGFloat {
        let v = sin(Double(i) * 37.719) * 27183.145
        return CGFloat(v - floor(v))
    }
}

/// 主题氛围层：按主题 motion 配置组合气泡 / 像素 / 扫描线，单次挂载。
struct ThemeAmbientLayer: View {
    var body: some View {
        ZStack {
            ThemeScanlines()
            ThemeAmbientPixels()
            ThemeAmbientBubbles()
            ThemeAmbientInk()
            ThemeAmbientPollen()
        }
    }
}

/// 雾青主题氛围：极淡的花粉光尘缓慢飘落，偶有叶片翻面。
/// 只用 SwiftUI 动画（无定时器、无 Canvas 重绘），尊重系统“减少动态效果”。
struct ThemeAmbientPollen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drifting = false

    private let count = 14

    var body: some View {
        if enabled {
            GeometryReader { geo in
                ZStack {
                    ForEach(0..<count, id: \.self) { i in
                        PetalShape()
                            .fill(appAppearance.accent.opacity(0.05 + Double(i % 3) * 0.016))
                            .frame(width: 7 + CGFloat(i % 4) * 4, height: 9 + CGFloat(i % 4) * 5)
                            .rotationEffect(.degrees(Double(i * 37 % 360)))
                            .position(x: geo.size.width * fraction(i),
                                      y: drifting ? geo.size.height + 40 : -40)
                            .animation(.linear(duration: 11.0 + Double(i % 5) * 1.8)
                                        .repeatForever(autoreverses: false)
                                        .delay(Double(i) * 0.5),
                                       value: drifting)
                    }
                }
                .onAppear { drifting = true }
            }
            .allowsHitTesting(false)
        }
    }

    private var enabled: Bool {
        guard appAppearance.motion?.ambientPollen == true else { return false }
        if reduceMotion && (appAppearance.motion?.respectReduceMotion ?? true) { return false }
        return true
    }

    private func fraction(_ i: Int) -> CGFloat {
        let v = sin(Double(i) * 27.613) * 5731.77
        return CGFloat(v - floor(v))
    }
}

/// 一枚叶片轮廓：两段对称弧线，用于花粉 / 叶片氛围。
struct PetalShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.5, y: 0))
        p.addQuadCurve(to: CGPoint(x: w * 0.5, y: h), control: CGPoint(x: w * 1.25, y: h * 0.5))
        p.addQuadCurve(to: CGPoint(x: w * 0.5, y: 0), control: CGPoint(x: -w * 0.25, y: h * 0.5))
        p.closeSubpath()
        return p
    }
}

/// 墨纸主题氛围：低透明度墨点缓慢晕开上浮。
struct ThemeAmbientInk: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rising = false

    var body: some View {
        if enabled {
            GeometryReader { geo in
                ZStack {
                    ForEach(0..<9, id: \.self) { i in
                        Circle()
                            .fill(appAppearance.accent.opacity(0.035 + Double(i % 3) * 0.012))
                            .frame(width: 10 + CGFloat(i % 4) * 10)
                            .blur(radius: 5)
                            .position(x: geo.size.width * fraction(i),
                                      y: rising ? -20 : geo.size.height + 20)
                            .animation(.linear(duration: 9.0 + Double(i % 4) * 1.6)
                                        .repeatForever(autoreverses: false)
                                        .delay(Double(i) * 0.6),
                                       value: rising)
                    }
                }
                .onAppear { rising = true }
            }
            .allowsHitTesting(false)
        }
    }

    private var enabled: Bool {
        guard appAppearance.motion?.ambientInk == true else { return false }
        if reduceMotion && (appAppearance.motion?.respectReduceMotion ?? true) { return false }
        return true
    }

    private func fraction(_ i: Int) -> CGFloat {
        let v = sin(Double(i) * 41.117) * 9137.31
        return CGFloat(v - floor(v))
    }
}

/// 街机主题氛围：像素方块缓慢上浮。
struct ThemeAmbientPixels: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rising = false

    var body: some View {
        if enabled {
            GeometryReader { geo in
                ZStack {
                    ForEach(0..<10, id: \.self) { i in
                        Rectangle()
                            .fill(appAppearance.accent.opacity(0.05 + Double(i % 3) * 0.02))
                            .frame(width: 4 + CGFloat(i % 3) * 3,
                                   height: 4 + CGFloat(i % 3) * 3)
                            .position(x: geo.size.width * fraction(i),
                                      y: rising ? -18 : geo.size.height + 18)
                            .animation(.linear(duration: 8.0 + Double(i % 4) * 1.4)
                                        .repeatForever(autoreverses: false)
                                        .delay(Double(i) * 0.5),
                                       value: rising)
                    }
                }
                .onAppear { rising = true }
            }
            .allowsHitTesting(false)
        }
    }

    private var enabled: Bool {
        guard appAppearance.motion?.ambientPixels == true else { return false }
        if reduceMotion && (appAppearance.motion?.respectReduceMotion ?? true) { return false }
        return true
    }

    private func fraction(_ i: Int) -> CGFloat {
        let v = sin(Double(i) * 19.913) * 17321.77
        return CGFloat(v - floor(v))
    }
}

/// 街机主题静态扫描线：一次绘制、零定时器；减少动态效果时关闭。
struct ThemeScanlines: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if enabled {
            Canvas { context, size in
                var y: CGFloat = 0
                while y < size.height {
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                                 with: .color(appAppearance.accent.opacity(0.05)))
                    y += 3
                }
            }
            .allowsHitTesting(false)
        }
    }

    private var enabled: Bool {
        guard appAppearance.motion?.scanlines == true else { return false }
        if reduceMotion && (appAppearance.motion?.respectReduceMotion ?? true) { return false }
        return true
    }
}

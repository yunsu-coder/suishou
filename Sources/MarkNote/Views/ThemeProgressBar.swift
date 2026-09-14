import SwiftUI

/// 主题化进度条（插件界面通用件；采集下载 / 预览本地化 / 任何耗时任务都能用）。
///
/// 规矩（见 docs/05-内置插件库.md「插件主题适配规范」）：
/// - 轨道 = 主题正文色低透明派生，填充 = 主题 `--accent`（禁止写死色值）；
/// - 说明文字走主题 `uiFont`，百分比 / 字节数走主题 `codeFont`；
/// - 动效时长取主题 `motion.duration`，并尊重系统「减少动态效果」（此时不动，只静态显示）；
/// - `value == nil`（拿不到总长）时用「流动光带」的不确定态，而不是假装一个百分比。
struct ThemeProgressBar: View {
    /// 0…1；nil = 总长未知（不确定态）
    var value: Double?
    /// 左侧说明（例如「正在下载视频 · 城市夜景」）
    var label: String?
    /// 右侧补充（例如「3/7 · 12.4 MB / 86.1 MB」）
    var detail: String?
    /// 条高（卡片上的细条用 4，面板里用 6）
    var height: CGFloat = 6
    /// 是否显示百分比（卡片上的细条一般不显示）
    var showsPercent: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glide = false

    private var accent: Color { appAppearance.accent }
    private var textColor: Color { Color(nsColor: appAppearance.editorForeground) }
    private var trackColor: Color { textColor.opacity(0.14) }
    private var animated: Bool {
        !(reduceMotion && (appAppearance.motion?.respectReduceMotion ?? true))
    }
    private var glideDuration: Double {
        max(0.6, (appAppearance.motion?.duration ?? 0.28) * 3.6)
    }
    private var clamped: Double { min(1, max(0, value ?? 0)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if hasCaption {
                HStack(spacing: 8) {
                    if let label, !label.isEmpty {
                        Text(label)
                            .font(uiFont(size: 11, weight: .medium))
                            .foregroundStyle(textColor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 6)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(numberFont)
                            // 次级文字必须由主题正文色现算（系统 .secondary 在自定义深底上看不清）
                            .foregroundStyle(textColor.opacity(0.72))
                            .lineLimit(1)
                    }
                    if showsPercent {
                        Text(percentText)
                            .font(numberFont)
                            .foregroundStyle(accent)
                            .lineLimit(1)
                    }
                }
            }
            bar
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "下载进度")
        .accessibilityValue(percentText)
    }

    private var hasCaption: Bool {
        showsPercent || !(label ?? "").isEmpty || !(detail ?? "").isEmpty
    }

    private var percentText: String {
        guard let value else { return "…" }
        return "\(Int((min(1, max(0, value)) * 100).rounded()))%"
    }

    private var bar: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(trackColor)
                if value == nil {
                    indeterminateBand(width: width)
                } else {
                    Capsule()
                        .fill(LinearGradient(colors: [accent.opacity(0.75), accent],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(height, width * CGFloat(clamped)))
                        .shadow(color: accent.opacity(0.35), radius: animated ? 3 : 0, y: 0)
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(textColor.opacity(0.10), lineWidth: 0.5))
    }

    /// 不确定态：一条主题强调色的光带来回流动（尊重「减少动态效果」时静态居中）
    private func indeterminateBand(width: CGFloat) -> some View {
        let band = max(height * 4, width * 0.32)
        let target = max(width - band, 0)
        return Capsule()
            .fill(LinearGradient(colors: [accent.opacity(0.10), accent.opacity(0.85), accent.opacity(0.10)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: band)
            .offset(x: animated ? (glide ? target : 0) : target / 2)
            .onAppear {
                guard animated else { return }
                glide = false
                withAnimation(.linear(duration: glideDuration).repeatForever(autoreverses: true)) {
                    glide = true
                }
            }
    }

    private func uiFont(size: CGFloat, weight: Font.Weight) -> Font {
        if let family = appAppearance.uiFontFamily, !family.isEmpty {
            return .custom(family, size: size)
        }
        return .system(size: size, weight: weight)
    }

    private var numberFont: Font {
        if let family = appAppearance.codeFontFamily, !family.isEmpty {
            return .custom(family, size: 10)
        }
        if let family = appAppearance.uiFontFamily, !family.isEmpty {
            return .custom(family, size: 10).monospacedDigit()
        }
        return .system(size: 10, design: .monospaced)
    }
}

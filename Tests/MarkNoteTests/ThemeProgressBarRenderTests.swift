import XCTest
import AppKit
import SwiftUI
@testable import MarkNote

/// 进度条主题化**真实渲染**（四主题对照）：
/// 同一组件 × 雾青 / 墨纸 / Bubble Pop / 深林夜，证明颜色、字体、动效确实跟着主题走。
/// 设置 `THEME_SHOT_DIR=docs/screenshots` 运行时，额外输出 `theme-progress-bar.png`（供人工审核）。
@MainActor
final class ThemeProgressBarRenderTests: XCTestCase {

    private static let packages = ["theme-misty-teal", "theme-sumi-paper",
                                   "theme-bubble-pop", "theme-forest-night"]

    func testRenderProgressBarAcrossFourThemes() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let market = root.appendingPathComponent("plugins-market", isDirectory: true)
        let (_, workspace) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let pluginsDir = workspace.appendingPathComponent(".plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)

        let previousTheme = UserDefaults.standard.string(forKey: "pluginThemeID")
        defer {
            if let previousTheme { UserDefaults.standard.set(previousTheme, forKey: "pluginThemeID") }
            else { UserDefaults.standard.removeObject(forKey: "pluginThemeID") }
            for name in Self.packages { UserDefaults.standard.removeObject(forKey: "pluginEnabled.\(name)") }
        }

        var copied = 0
        for name in Self.packages {
            let src = market.appendingPathComponent(name, isDirectory: true)
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            try FileManager.default.copyItem(at: src, to: pluginsDir.appendingPathComponent(name))
            UserDefaults.standard.set(true, forKey: "pluginEnabled.\(name)")
            copied += 1
        }
        try XCTSkipIf(copied == 0, "仓库里没有插件主题包：跳过渲染")

        let pm = PluginManager.shared
        pm.scan(workspaceDir: workspace)

        var shots: [(String, NSImage)] = []
        for name in Self.packages {
            guard let theme = pm.allThemes().first(where: { $0.id.contains(name) }) else { continue }
            UserDefaults.standard.set(theme.id, forKey: "pluginThemeID")
            guard let image = render(themeName: theme.name) else {
                XCTFail("\(theme.name) 渲染失败")
                continue
            }
            shots.append((theme.name, image))
        }
        XCTAssertEqual(shots.count, copied, "每个主题包都要渲染出一张")

        let width: CGFloat = 380 * 2   // renderer.scale = 2
        let rowHeight = shots.map { $0.1.size.height }.max() ?? 1
        let sheet = NSImage(size: NSSize(width: width, height: rowHeight * CGFloat(shots.count)))
        sheet.lockFocus()
        for (i, shot) in shots.enumerated() {
            let y = sheet.size.height - rowHeight * CGFloat(i + 1)
            shot.1.draw(in: NSRect(x: 0, y: y, width: width, height: rowHeight))
        }
        sheet.unlockFocus()

        guard let tiff = sheet.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("对照图编码失败")
        }
        let dir = ProcessInfo.processInfo.environment["THEME_SHOT_DIR"].map {
            root.appendingPathComponent($0, isDirectory: true)
        } ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("marknote-theme-shots", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appendingPathComponent("theme-progress-bar.png")
        try png.write(to: out)
        print("THEME_SHOT \(out.path)")
        XCTAssertGreaterThan(png.count, 8_000, "对照图不该是空白")
    }

    /// 一屏三种状态：进度中（带百分比/字节数）、接近完成、总长未知（流动条）
    private func render(themeName: String) -> NSImage? {
        let text = Color(nsColor: appAppearance.editorForeground)
        let view = VStack(alignment: .leading, spacing: 14) {
            Text(themeName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(text)
            ThemeProgressBar(value: 0.42,
                             label: "正在下载视频 · 城市夜景",
                             detail: "3/7 · 12.4 MB / 29.4 MB", height: 6)
            ThemeProgressBar(value: 0.88,
                             label: "正在下载图片 · 街角霓虹",
                             detail: "6/7 · 8.6 MB / 9.8 MB", height: 6)
            ThemeProgressBar(value: nil,
                             label: "正在解析视频地址 · 潮汐",
                             detail: "7/7", height: 6)
        }
        .padding(18)
        .frame(width: 380, alignment: .leading)
        .background(Color(nsColor: appAppearance.editorBackground))

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.nsImage
    }
}

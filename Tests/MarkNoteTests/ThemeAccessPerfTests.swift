import AppKit
import XCTest
@testable import MarkNote

/// `appAppearance` 是全局计算属性，SwiftUI 每次刷新会读很多次。
/// 曾经每次访问都去 stat + getxattr 主题 css（每击键数千次系统调用）→ 输入直接卡死。
final class ThemeAccessPerfTests: XCTestCase {

    /// 同一主题连续访问：1 秒内只允许真查一次文件（其余走缓存）
    func testThemeStatIsThrottled() {
        ThemeStatProbe.resetForTesting()
        let path = "/tmp/nonexistent-theme.css"
        let t0 = Date()
        for i in 0..<5_000 {
            _ = ThemeStatProbe.key(pluginID: "theme-x", cssPath: path,
                                   uiFont: nil, codeFont: nil, iconCount: 0,
                                   now: t0.addingTimeInterval(Double(i) * 0.0001))   // 0.5 秒内
        }
        XCTAssertEqual(ThemeStatProbe.statCount, 1, "0.5 秒内 5000 次访问只应真查 1 次文件")
        print("PERF themeStat 5000 次访问 → 真实 stat \(ThemeStatProbe.statCount) 次")
    }

    /// 换主题必须立刻重新探测；超过 1 秒也要重查（能看到主题文件改动）
    func testThemeStatRechecksOnChangeAndTimeout() {
        ThemeStatProbe.resetForTesting()
        let path = "/tmp/nonexistent-theme.css"
        let t0 = Date()
        _ = ThemeStatProbe.key(pluginID: "theme-a", cssPath: path, uiFont: nil, codeFont: nil,
                               iconCount: 0, now: t0)
        XCTAssertEqual(ThemeStatProbe.statCount, 1)
        _ = ThemeStatProbe.key(pluginID: "theme-b", cssPath: path, uiFont: nil, codeFont: nil,
                               iconCount: 0, now: t0.addingTimeInterval(0.05))
        XCTAssertEqual(ThemeStatProbe.statCount, 2, "换主题要立即重查")
        _ = ThemeStatProbe.key(pluginID: "theme-b", cssPath: path, uiFont: nil, codeFont: nil,
                               iconCount: 0, now: t0.addingTimeInterval(1.2))
        XCTAssertEqual(ThemeStatProbe.statCount, 3, "超过节流窗口要重查（主题文件改动能看到）")
        _ = ThemeStatProbe.key(pluginID: "theme-b", cssPath: path, uiFont: nil, codeFont: nil,
                               iconCount: 0, now: t0.addingTimeInterval(1.3))
        XCTAssertEqual(ThemeStatProbe.statCount, 3, "窗口内继续复用缓存")
    }

    /// 全局外观访问本身要便宜（不带插件主题时不碰文件系统）
    @MainActor
    func testAppAppearanceAccessIsCheap() throws {
        let rounds = 20_000
        _ = appAppearance
        let start = Date()
        var sink = 0
        for _ in 0..<rounds {
            sink &+= appAppearance.mdSyntax.count &+ (appAppearance.dark ? 1 : 0)
        }
        let totalMs = Date().timeIntervalSince(start) * 1000
        let perAccess = totalMs / Double(rounds) * 1000   // µs
        print("PERF appAppearance \(rounds) 次访问 = \(Int(totalMs)) ms（每次 \(String(format: "%.2f", perAccess)) µs）sink=\(sink % 7)")
        XCTAssertLessThan(perAccess, 30,
                          "单次访问 \(perAccess)µs 太慢：SwiftUI 刷新会读上千次，输入会卡")
    }
}

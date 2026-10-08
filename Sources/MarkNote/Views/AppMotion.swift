import SwiftUI

/// 全局动效：统一时长与曲线，避免每处各写一套（也避免"哪里都硬切"）。
/// 一律尊重系统「减少动态效果」——开启时返回 nil，调用方原样传进 .animation()。
enum AppMotion {
    /// 面板/侧栏这类结构变化：稍微带一点回弹，收放都要"有重量"
    static func panel(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86)
    }

    /// 内容替换（预览换图、模式切换）：快、不带回弹，避免晃眼
    static func content(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.18)
    }

    /// 列表项的增删（标签页、素材条）
    static func item(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82)
    }
}

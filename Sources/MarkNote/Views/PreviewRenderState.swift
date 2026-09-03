import Foundation

/// 预览渲染指纹仲裁 —— 纯逻辑（可脱离 WebKit 单测）。
/// 修复 C-01：旧实现只比较 md.count（+ 其余参数），
/// 「删除一个字符再打一个」这类同长度编辑会被误判为未变化而漏渲染。
struct PreviewRenderState {
    private(set) var lastMD = ""
    private(set) var lastMeta = ""
    private(set) var lastToken = ""

    /// 内容（md）或渲染参数（meta）或文件 token 任一变化 → 需要渲染；
    /// 返回值同时携带「是否重置滚动」（token 变化 = 切换文件 → 回顶部）。
    /// 强制作废指纹（插件/主题变更后无条件重渲）
    mutating func reset() {
        lastMD = ""
        lastMeta = ""
        lastToken = ""
    }

    mutating func shouldRender(md: String, meta: String, token: String) -> (render: Bool, resetScroll: Bool) {
        if md == lastMD && meta == lastMeta && token == lastToken {
            return (false, false)
        }
        let reset = token != lastToken
        lastMD = md
        lastMeta = meta
        lastToken = token
        return (true, reset)
    }
}

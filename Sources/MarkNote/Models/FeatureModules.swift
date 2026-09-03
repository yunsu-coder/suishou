import Foundation

/// 非渲染类能力开关（轻量设定）：导出器 / AI 子能力。
/// UserDefaults key: featureModule.<name>；缺省全开；设置页「插件」分组管理。
enum FeatureModules {
    static let exportPDF = "exportPDF"
    static let exportHTML = "exportHTML"
    static let editorLineNumbers = "editorLineNumbers"
    static let editorCurrentLine = "editorCurrentLine"
    static let editorBracketMatch = "editorBracketMatch"
    static let editorCodeSmart = "editorCodeSmart"
    static let aiQuickActions = "aiQuickActions"
    static let aiFileAgent = "aiFileAgent"
    static let aiSummary = "aiSummary"

    static func isEnabled(_ name: String) -> Bool {
        UserDefaults.standard.object(forKey: "featureModule.\(name)") as? Bool ?? true
    }

    static func setEnabled(_ name: String, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: "featureModule.\(name)")
    }

    /// 设置页展示列表
    static let all: [(id: String, title: String, hint: String)] = [
        ("editorLineNumbers", _L("行号标尺", "Line Numbers"), _L("显示/隐藏编辑器行号栏（宽度仍可拖拽）", "Show/hide the editor line-number gutter (width still draggable)")),
        ("editorCurrentLine", _L("当前行高亮", "Highlight Current Line"), _L("光标所在行底色高亮", "Highlight the current line with a background color")),
        ("editorBracketMatch", _L("括号匹配高亮", "Bracket Match Highlight"), _L("光标贴括号时高亮配对（含 ⌘⇧反斜杠 跳转）", "Highlight the matching bracket when the cursor is adjacent (incl. ⌘⇧ backslash to jump)")),
        ("editorCodeSmart", _L("代码智能编辑", "Code Smart Editing"), _L("代码语法着色 / 括号自动成对 / 智能缩进 / ⌘/ 注释（C 系语言）", "Syntax highlighting / auto-paired brackets / smart indent / ⌘/ comment (C-family)")),
        ("exportPDF", _L("导出 PDF", "Export PDF"), _L("离屏渲染导出；关闭后菜单/命令面板隐藏该项", "Offscreen render export; hides the item from menus/command palette when off")),
        ("exportHTML", _L("导出独立 HTML", "Export Standalone HTML"), _L("内联样式与 KaTeX 字体；关闭后隐藏", "Inline styles & KaTeX fonts; hidden when off")),
        ("aiQuickActions", _L("AI 快捷操作（翻译 / 改写 / 润色）", "AI Quick Actions (Translate / Rewrite / Polish)"), _L("关闭后右键菜单/快捷键/命令面板不再出现", "Hides from context menu / shortcuts / command palette when off")),
        ("aiFileAgent", _L("AI 文件代理（读写/改名/移动/删除文件）", "AI File Agent (read/write/rename/move/delete files)"), _L("关闭后 AI 仅纯问答，不可操作工作台文件（更严格）", "When off, AI is Q&A only and cannot touch workspace files (stricter)")),
        ("aiSummary", _L("AI 总结对话 → 笔记", "AI Summarize Chat → Note"), _L("关闭后「总结到笔记」按钮隐藏", "Hides the Summarize to Note button when off")),
    ]
}


extension Notification.Name {
    /// 强制预览重渲（插件/主题应用兜底）
    static let renderForceRefresh = Notification.Name("renderForceRefresh")
}

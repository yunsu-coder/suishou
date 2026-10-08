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
    /// 界面光效：光标聚光 / 面板接缝高光 / 保存脉冲
    static let visualGlow = "visualGlow"
    /// 代码文件的语法着色：独立开关 —— 关掉"智能编辑"（自动配对/缩进）不该连带把颜色也关掉
    static let editorSyntaxColor = "editorSyntaxColor"
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
        ("visualGlow", _L("界面光效", "Interface Glow"), _L("光标聚光、面板接缝高光、保存脉冲（极淡、可关；系统降低透明度时自动让路）", "Cursor spotlight, panel seam glow, save pulse (very subtle; yields to Reduce Transparency)")),
        ("editorSyntaxColor", _L("语法着色（代码文件）", "Syntax Colors (code files)"), _L("按语言给关键字/字符串/类型/注释上色（One Dark Pro / One Light 固定配色）", "Per-language colors for keywords, strings, types and comments (fixed One Dark Pro / One Light palettes)")),
        ("editorCodeSmart", _L("代码智能编辑", "Code Smart Editing"), _L("括号/引号自动成对、空对删除、选中包围、智能换行与缩进、⌘/ 注释", "Auto-paired brackets/quotes, empty-pair delete, wrap selection, smart newline and indent, ⌘/ comment")),
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

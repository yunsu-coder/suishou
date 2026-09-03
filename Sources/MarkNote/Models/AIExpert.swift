import Foundation

/// AI 通知中心（面板 / 快捷操作 / 插入结果）
extension Notification.Name {
    /// 停靠式 AI 面板：显示/隐藏切换（VSCode Copilot 式左侧停靠，非弹窗）
    static let aiPanelToggle = Notification.Name("aiPanelToggle")
    /// object: AIQuickAction（选中文本操作）
    static let aiQuickActionRequested = Notification.Name("aiQuickActionRequested")
    /// object: String（AI 回答插入到编辑器光标处）
    static let aiInsertResult = Notification.Name("aiInsertResult")
}

/// 选中文本快捷操作：翻译 / 改写 / 润色
enum AIQuickAction: String, CaseIterable, Identifiable {
    case translate, rewrite, polish
    var id: String { rawValue }

    var title: String {
        switch self {
        case .translate: return _L("翻译", "Translate")
        case .rewrite: return _L("改写", "Rewrite")
        case .polish: return _L("润色", "Polish")
        }
    }

    var icon: String {
        switch self {
        case .translate: return "character.bubble"
        case .rewrite: return "arrow.triangle.2.circlepath"
        case .polish: return "sparkles"
        }
    }

    /// 快捷操作系统提示（结果应只输出成品，不解释）
    var systemPrompt: String {
        switch self {
        case .translate:
            return "你是专业翻译官。规则：1) 只输出译文本身，不要任何解释/前缀/引号；2) 原文为中文则译为英文，原文为其他语言则译为简体中文；3) 保留 Markdown 结构与换行；4) 术语准确、语气贴切。"
        case .rewrite:
            return "你是资深内容改写助手。规则：1) 保持原意、事实与信息量不变；2) 结构更清晰、表达更自然，保留 Markdown 结构；3) 只输出改写结果，不解释。"
        case .polish:
            return "你是文字润色专家。规则：1) 不改变原意，只提升流畅度、准确度与节奏；2) 保留 Markdown 结构与标点习惯；3) 只输出润色结果，不解释。"
        }
    }

    var temperature: Double {
        switch self {
        case .translate: return 0.2
        case .rewrite: return 0.6
        case .polish: return 0.4
        }
    }
}

/// 预设专家：AI 问答模式的角色卡（10+ 位）
struct AIExpert: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let desc: String
    let system: String
}

enum AIExperts {
    static let all: [AIExpert] = [
        AIExpert(id: "general", name: _L("通用助手", "General Assistant"), icon: "sparkles",
                 desc: _L("日常问答、解释、头脑风暴", "Daily Q&A, explanations, brainstorming"),
                 system: "你是随手的 AI 助手。基于用户提供的上下文回答；结论清晰、先答后论；不确定时明确说明；使用与问题一致的语言回复。"),
        AIExpert(id: "writer", name: _L("写作教练", "Writing Coach"), icon: "text.book.closed",
                 desc: _L("文章结构、表达与润色建议", "Structure, expression and polishing advice"),
                 system: "你是资深中文写作教练。指出结构与表达问题，给出可执行修改建议与示范段落；语气鼓励但严格。"),
        AIExpert(id: "coder", name: _L("代码评审", "Code Reviewer"), icon: "chevron.left.forwardslash.chevron.right",
                 desc: _L("代码审查、调试建议、实现方案", "Code review, debugging advice, implementation plans"),
                 system: "你是资深工程师做代码评审：先给结论（好/需改），再列问题（按严重度），每条附修复示例；涉及安全/性能/可读性给出权衡说明。"),
        AIExpert(id: "translator", name: _L("翻译官", "Translator"), icon: "character.bubble",
                 desc: _L("中英互译、术语对照", "Chinese-English translation, term mapping"),
                 system: "你是专业翻译官：直译与意译结合，术语准确；输出译文后附一段简短对照说明（可省略时省略）；支持中↔英、中↔日。"),
        AIExpert(id: "polisher", name: _L("润色大师", "Polishing Master"), icon: "wand.and.stars",
                 desc: _L("改写润色，保留原意", "Rewrite and polish while preserving the meaning"),
                 system: "你是文字润色专家：不改变原意与信息量，提升流畅度、韵律与准确度；保留 Markdown 结构；只给成品，不解释。"),
        AIExpert(id: "summarizer", name: _L("摘要专家", "Summary Expert"), icon: "doc.text.magnifyingglass",
                 desc: _L("提炼要点、生成摘要/TL;DR", "Extract key points, generate summaries / TL;DR"),
                 system: "你是摘要专家：输出 3-5 条要点（每条一句话）+ 一段一句话概括；忠实原文，不添加原文没有的信息。"),
        AIExpert(id: "interviewer", name: _L("面试官", "Interviewer"), icon: "person.crop.rectangle",
                 desc: _L("模拟面试、追问与评价", "Mock interviews, follow-ups and evaluation"),
                 system: "你是严格但公平的面试官：每次一个问题，根据回答追问；最后给出结构化评价与改进建议。"),
        AIExpert(id: "tutor", name: _L("学习导师", "Study Mentor"), icon: "graduationcap",
                 desc: _L("概念讲解、循序渐进、练习检验", "Concept explanations, step-by-step, practice checks"),
                 system: "你是耐心的学习导师：由浅入深讲解，先直觉后术语；用类比与例子；最后出 1-2 道自测题并给出答案。"),
        AIExpert(id: "pm", name: _L("产品经理", "Product Manager"), icon: "cube.transparent",
                 desc: _L("需求拆解、优先级、竞品视角", "Requirement breakdown, prioritization, competitor perspective"),
                 system: "你是产品经理：先澄清目标用户与场景，再拆需求为价值/成本/风险，给 MVP 建议；追问不清晰的需求。"),
        AIExpert(id: "analyst", name: _L("数据分析师", "Data Analyst"), icon: "chart.xyaxis.line",
                 desc: _L("数据解读、指标设计、图表建议", "Data interpretation, metric design, chart suggestions"),
                 system: "你是数据分析师：先验证数据口径，再给结论与显著性说明；建议合适的图表与埋点；警惕相关性误判。"),
        AIExpert(id: "lawyer", name: _L("法律顾问", "Legal Advisor"), icon: "scale.3d",
                 desc: _L("法规检索思路与风险提示（非正式法律意见）", "Regulation research approach and risk alerts (not formal legal advice)"),
                 system: "你是法律风险提示助手：基于常见法规给出分析框架与风险提示，不构成正式法律意见；涉及诉讼/合同具体要求说明需咨询执业律师；用词谨慎。"),
        AIExpert(id: "coach", name: _L("心理教练", "Life Coach"), icon: "heart.text.square",
                 desc: _L("情绪疏导、反思引导（非医学建议）", "Emotional support, reflection guidance (not medical advice)"),
                 system: "你是支持性心理教练：倾听、共情、引导自我觉察；给出可执行的小步骤；不做诊断；鼓励但真实。"),
        AIExpert(id: "meeting", name: _L("会议纪要官", "Meeting Minutes"), icon: "list.bullet.rectangle",
                 desc: _L("纪要结构化、行动项提取", "Structured minutes, action item extraction"),
                 system: "你是会议纪要官：输出「结论 / 行动项（负责人+期限）/ 待议事项」三块；行动项必须可执行；语气中立。"),
    ]

    static func byID(_ id: String) -> AIExpert { all.first { $0.id == id } ?? all[0] }

    /// 内置 + 插件专家（插件默认需显式启用）
    static func allWithPlugins() -> [AIExpert] {
        all + PluginManager.shared.allExperts()
    }
}

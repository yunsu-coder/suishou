import Foundation

/// AI 追问：需求不够明确时，先问清楚再开工（「信息不足就追问，别硬猜」）。
struct CollectClarifyQuestion: Identifiable, Equatable {
    var id: String
    var question: String
    /// 关联字段（kind / subject / usage / count / orientation …），只用于展示与调试
    var field: String?
    /// 可直接点的建议选项（也可以自己打字）
    var options: [String]
}

struct CollectClarifyReview: Equatable {
    /// true = 理解够了，可以直接进需求卡
    var ready: Bool
    /// 不够明确时给用户看的一句话原因
    var reason: String?
    var questions: [CollectClarifyQuestion]
}

/// 关键项体检发现的一个缺口（硬规则用，不看模型脸色）
struct CollectClarifyGap: Equatable {
    var field: String
    var question: String
    var options: [String]
}

/// 需求审校（严格版）：把「一句话需求 + AI 已解析出的卡片」交给模型复查，
/// 只在**真正影响采集结果**的地方追问，最多 3 条，每条带可点选项。
enum CollectorClarify {

    /// 最多追问几轮（答完还能再问，但不会无限循环）
    static let maxRounds = 3
    /// 单轮最多几条问题
    static let maxQuestions = 3
    /// **最少**问几轮：选项答完也要再问一轮，别让「选了一个选项」当成已经理解
    static let minRounds = 2

    /// 还能不能再追问：超过轮次就放行（宁可让用户看需求卡，也不把人锁在问答里）
    static func canAskMore(round: Int) -> Bool { round < maxRounds }

    // MARK: - 硬规则（模型说「懂了」也要过这一关）

    /// 关键项体检：还不知道就必然影响采集结果的项。
    /// 注意「能安全默认的」不算缺口（数量、语言、是否合并文件…），别把人问烦。
    static func missingKeyFields(_ r: CollectRequest) -> [CollectClarifyGap] {
        var gaps: [CollectClarifyGap] = []
        if r.kind == nil {
            gaps.append(.init(field: "kind", question: "这次要找哪一类？",
                              options: ["图片", "视频", "文章", "小说"]))
        }
        if (r.subject ?? "").trimmed.isEmpty {
            gaps.append(.init(field: "subject",
                              question: r.kind == "novel" ? "要找哪本书（或哪类小说）？"
                                                          : "具体找什么？（主题越具体越好）",
                              options: []))
        }
        switch r.kind {
        case "image":
            if (r.usage ?? "").trimmed.isEmpty,
               (CollectOrientation(rawValue: r.orientation) ?? .any) == .any {
                gaps.append(.init(field: "usage", question: "这些图用在哪？（决定构图与留白）",
                                  options: ["笔记封面", "文章配图", "视频封面", "桌面壁纸", "只做参考"]))
            }
        case "video":
            if (CollectVideoDuration(rawValue: r.videoDuration) ?? .any) == .any, r.platforms.isEmpty {
                gaps.append(.init(field: "videoDuration", question: "视频要什么长度、主要在哪个平台找？",
                                  options: ["1 分钟内的短片", "1-5 分钟", "5 分钟以上",
                                            "主要在 B 站 / 抖音", "不限"]))
            }
        case "article":
            if (r.usage ?? "").trimmed.isEmpty, r.styles.isEmpty, (r.styleNote ?? "").trimmed.isEmpty {
                gaps.append(.init(field: "usage", question: "文章的范围或体裁？",
                                  options: ["深度长文", "简短科普", "案例复盘", "行业报告", "不限"]))
            }
        case "novel":
            if r.chapterLimit == 30 {          // 30 = 没被问过/没改过的默认值
                gaps.append(.init(field: "chapterLimit", question: "要抓多少章？",
                                  options: ["先抓前 20 章", "前 50 章", "前 100 章", "尽量全本（慢）"]))
            }
        default:
            break
        }
        return Array(gaps.prefix(maxQuestions))
    }

    /// 关键项都齐了、但还没问够轮次时的「收尾一问」（带「别问了」出口）
    static func refineQuestion(for r: CollectRequest) -> CollectClarifyQuestion {
        let stop = "没有了，就这样"
        switch r.kind {
        case "video":
            return .init(id: "refine", question: "清晰度或其它硬要求？（没有就选最后一项）",
                         field: "videoResolution",
                         options: ["必须 1080P 以上", "要有声音", "最好有字幕", stop])
        case "article":
            return .init(id: "refine", question: "来源或时间还要限定吗？",
                         field: "recency",
                         options: ["只要最近一个月的", "只要权威站点", "不限", stop])
        case "novel":
            return .init(id: "refine", question: "章节怎么存？（没有偏好就选最后一项）",
                         field: "mergeChapters",
                         options: ["合并成一个文件", "一章一个文件", "先抓前 20 章", stop])
        default:
            return .init(id: "refine", question: "风格、水印这类还有硬要求吗？",
                         field: "styles",
                         options: ["不要水印", "要能商用", "要留白放标题", stop])
        }
    }

    /// 这一轮**到底要不要继续问**：模型说 ready 也可能被硬规则拦下。
    /// 返回空数组 = 可以放行去需求卡。
    static func questionsForNextRound(review: CollectClarifyReview?, request: CollectRequest,
                                      round: Int) -> [CollectClarifyQuestion] {
        var questions: [CollectClarifyQuestion] = []
        // ① 关键项还缺 → 用体检出来的问题（模型没说也照样问）
        for gap in missingKeyFields(request) {
            questions.append(.init(id: "gap-\(gap.field)", question: gap.question,
                                   field: gap.field, options: gap.options))
        }
        // ② 模型自己的问题补在后面（去重）
        for q in review?.questions ?? [] where !questions.contains(where: { $0.question == q.question }) {
            questions.append(q)
        }
        // ③ 关键项齐了、但还没问够最少轮次 → 收尾再问一轮
        if questions.isEmpty, round < minRounds {
            questions.append(refineQuestion(for: request))
        }
        return Array(questions.prefix(maxQuestions))
    }

    /// 用户在选项里选了「没有了 / 不用了」这类出口 → 立刻停止追问（需求卡照旧会标红必填项）
    static func answerMeansStop(_ answer: String) -> Bool {
        let a = answer.trimmed.replacingOccurrences(of: " ", with: "")
        guard !a.isEmpty else { return false }
        // 注意：别把「不限 / 都行」当出口——那是「这一项我不挑」，不代表不想再被问
        let markers = ["没有了", "不用了", "别问了", "就这样", "没有别的", "没有其他",
                       "no more", "nomore", "thats it", "that is it"]
        return markers.contains { a.localizedCaseInsensitiveContains($0) }
    }

    /// 让模型审一遍需求。`complete` 可注入（测试用假模型）；失败返回 nil = 放行到需求卡。
    static func review(_ request: CollectRequest, userText: String, round: Int,
                       complete: ((String, String) async throws -> String)? = nil) async -> CollectClarifyReview? {
        let call: (String, String) async throws -> String
        if let complete {
            call = complete
        } else {
            guard LLM.configured else { return nil }
            call = { system, user in try await LLM.complete(system: system, user: user) }
        }
        let system = """
        你是「素材采集需求审校员」。判断用户的一句话需求是否**已经明确到可以直接开始采集**。
        严格，但不要过度追问：
        1. 必须能看出「找什么类型」（图片 / 视频 / 文章 / 小说）和「具体对象或题材」；
        2. 若某个**会明显影响结果质量**的关键项无法从原话或常识安全推断 → 必须追问
           （例：图片的用途与方向、视频的时长与平台、文章的范围与体裁、小说的书名与要抓多少章）；
        3. 只问影响采集结果的问题，**最多 \(maxQuestions) 条**，每条给 2-5 个贴合上下文、可直接点的选项
           （例如「横图 / 竖图 / 方图」「1500 字内的短评 / 3000 字以上的长文」），不要问泛泛的「你想要什么风格」；
        4. 用户已经说过的、或能用默认值安全兜底（数量、语言等）的，不要问；
        5. 有任何一条追问没问清前，`ready` 必须为 false；
        6. **用户选了选项、补了一部分信息，也不等于「完全理解」**：只要还有关键项没确认
           （图片的用途/方向、视频的时长/平台/清晰度、文章的体裁或范围、小说的书名与章节范围），
           必须继续追问下一件最重要的事——每轮只问「下一步最该确认的那一件」，
           不要一次把问题问完，也不要在信息还不够时草率给 ready=true；
        7. 只有当你自己觉得「拿着这张需求卡去搜，结果一定是用户想要的」时，才可以 ready=true。
        输出 JSON（只输出 JSON，不要解释）：
        {"ready":true/false,
         "reason":"不够明确的一句话原因（ready=true 时给空字符串）",
         "questions":[{"id":"q1","question":"要问用户的话","field":"kind|subject|usage|count|orientation|other",
                       "options":["选项一","选项二"]}]}
        """
        let user = """
        用户原话：\(userText.isEmpty ? "（无，用户是手填的卡片）" : userText)
        目前已解析出的需求：\(CollectorIntent.describe(request))
        这是第 \(round) 轮追问（最多 \(maxRounds) 轮）：若已足够明确请直接给 ready=true。
        """
        guard let reply = try? await call(system, user) else { return nil }
        return parseReview(reply)
    }

    /// 解析审校结果（容错：```json 包裹、字段缺失、类型不对）
    static func parseReview(_ reply: String) -> CollectClarifyReview? {
        guard let data = extractJSON(reply).data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        let ready: Bool
        if let b = obj["ready"] as? Bool { ready = b }
        else if let s = obj["ready"] as? String { ready = (s.trimmed.lowercased() == "true") }
        else { ready = false }
        let reason = (obj["reason"] as? String)?.trimmed
        var questions: [CollectClarifyQuestion] = []
        if let raw = obj["questions"] as? [[String: Any]] {
            for (i, q) in raw.enumerated() {
                let text = (q["question"] as? String)?.trimmed ?? ""
                guard !text.isEmpty else { continue }
                let options = (q["options"] as? [Any] ?? []).compactMap { $0 as? String }
                    .map { $0.trimmed }.filter { !$0.isEmpty }
                questions.append(CollectClarifyQuestion(
                    id: (q["id"] as? String)?.trimmed.nonEmpty ?? "q\(i + 1)",
                    question: text,
                    field: (q["field"] as? String)?.trimmed.nonEmpty,
                    options: Array(options.prefix(6))))
                if questions.count >= maxQuestions { break }
            }
        }
        // ready 与 questions 互相矛盾时：有追问就按「没问完」处理（宁可多问一句）
        let finalReady = ready && questions.isEmpty
        return CollectClarifyReview(ready: finalReady,
                                    reason: reason?.nonEmpty,
                                    questions: finalReady ? [] : questions)
    }

    /// 把「问题 + 回答」拼成补充描述，交给 `CollectorIntent.parse` 再解析一次
    static func followUpText(_ original: String, answers: [(question: String, answer: String)]) -> String {
        let pairs = answers
            .map { (q: $0.question.trimmed, a: $0.answer.trimmed) }
            .filter { !$0.a.isEmpty }
        guard !pairs.isEmpty else { return original.trimmed }
        let block = pairs.map { "Q：\($0.q)\nA：\($0.a)" }.joined(separator: "\n")
        return original.trimmed + "\n\n【追问补充】\n" + block
    }

    private static func extractJSON(_ reply: String) -> String {
        if let s = reply.firstIndex(of: "{"), let e = reply.lastIndex(of: "}") {
            return String(reply[s...e])
        }
        return reply
    }
}

private extension String {
    /// 空串 → nil（少写点 `isEmpty ? nil :`）
    var nonEmpty: String? { isEmpty ? nil : self }
}

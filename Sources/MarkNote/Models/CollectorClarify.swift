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

/// 需求审校（严格版）：把「一句话需求 + AI 已解析出的卡片」交给模型复查，
/// 只在**真正影响采集结果**的地方追问，最多 3 条，每条带可点选项。
enum CollectorClarify {

    /// 最多追问几轮（答完还能再问，但不会无限循环）
    static let maxRounds = 3
    /// 单轮最多几条问题
    static let maxQuestions = 3

    /// 还能不能再追问：超过轮次就放行（宁可让用户看需求卡，也不把人锁在问答里）
    static func canAskMore(round: Int) -> Bool { round < maxRounds }

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
        5. 有任何一条追问没问清前，`ready` 必须为 false。
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

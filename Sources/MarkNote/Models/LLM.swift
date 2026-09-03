import Foundation

/// 云端 LLM 客户端（OpenAI 兼容 /chat/completions 协议，DeepSeek/Qwen/Kimi/OpenAI 通用）。
/// 原则：只上送「当前文件」的选中/正文字段，绝不扫描全库；密钥存本机 UserDefaults。
nonisolated enum LLM {

    static let kModel = "llmModel"
    static let kAPIKey = "llmAPIKey"
    private static let baseURL = "https://api.deepseek.com/v1"
    /// 可选模型（设置页选择；默认视觉实验版 —— 可识图，纯文本能力与 Flash 持平）
    static let availableModels = ["deepseek-v4-flash-vision-exp", "deepseek-v4-flash", "deepseek-v4-pro"]

    /// API Key：不再硬编码进源码/仓库（安全）。
    /// 读取顺序：UserDefaults("llmAPIKey") → 环境变量 DEEPSEEK_API_KEY → 空。
    /// 用户可在设置里填自己的 key；发行版默认为空（AI 功能需先配置）。
    private static var apiKey: String {
        if let k = UserDefaults.standard.string(forKey: kAPIKey), !k.isEmpty { return k }
        if let env = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !env.isEmpty { return env }
        return ""
    }

    /// 首次启动：若环境变量注入，则写入 UserDefaults（本机持久化，不进 git）
    static func bootstrapAPIKeyIfNeeded() {
        guard UserDefaults.standard.string(forKey: kAPIKey) == nil,
              let env = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !env.isEmpty else { return }
        UserDefaults.standard.set(env, forKey: kAPIKey)
    }

    static var configured: Bool { !apiKey.isEmpty }

    /// 生成标题：系统提示 + 正文前 ~1500 字 → 返回一个短标题
    static func suggestTitle(content: String) async throws -> String? {
        guard configured else { return nil }
        let model = UserDefaults.standard.string(forKey: kModel) ?? "deepseek-v4-flash-vision-exp"
        let url = URL(string: baseURL.hasSuffix("/") ? baseURL + "chat/completions" : baseURL + "/chat/completions")!
        let excerpt = String(content.prefix(1500))
        let system = "你是笔记标题助理。规则：1) 只根据笔记实际内容抽象命名，绝不使用通用模板式标题（如「高效■技巧」「■指南」「■整理」）；2) **不超过 14 字**（8–14 最佳）、具体；3) 内容无法概括时只输出「无标题」；4) 只输出标题本身，不要引号/句号/序号/解释。"
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": "笔记内容：\n" + excerpt],
            ],
            "temperature": 0.4,
            "max_tokens": 64,
            "thinking": ["type": "disabled"], // V4 默认思考开启；自动命名要即时反馈 → 显式关闭
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: req)
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = dict["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let text = message["content"] as? String else { return nil }
        let title = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "：", with: "")
        // 最终校验统一走 isValidTitle（含 ≤14 字 + 模板词）；此处仅去空
        return title.isEmpty ? nil : title
    }

    /// 模板词黑名单：命中 = 视为 AI 水词输出（如「高效笔记整理技巧」）
    static let bannedTitleWords: [String] = ["高效", "技巧", "指南", "整理", "收藏", "值得", "看完", "模板", "教程", "大全", "建议", "干货", "必看", "宝典", "总结", "心得"]

    static func isValidTitle(_ t: String?) -> Bool {
        guard let t, !t.isEmpty else { return false }
        if t.count < 2 || t.count > 14 { return false }
        if bannedTitleWords.contains(where: { t.contains($0) }) { return false }
        return true
    }

    /// 严格版：上轮产出不合规（模板词/过泛）→ 强制"只复述内容要点"
    static func suggestTitleStrict(content: String) async throws -> String? {
        guard configured else { return nil }
        let url = URL(string: baseURL.hasSuffix("/") ? baseURL + "chat/completions" : baseURL + "/chat/completions")!
        let excerpt = String(content.prefix(1500))
        let body: [String: Any] = [
            "model": UserDefaults.standard.string(forKey: kModel) ?? "deepseek-v4-flash-vision-exp",
            "messages": [
                ["role": "system", "content": "严格规则：直接复述笔记内容的最核心对象/主题，输出一个具体名词短语（如「M1 Air 毛玻璃调试」），**不超过 14 字**；禁止建议性/总结性/体系性措辞；无法确定时输出 无标题"],
                ["role": "user", "content": "内容：\n" + excerpt],
            ],
            "temperature": 0.1,
            "max_tokens": 48,
            "thinking": ["type": "disabled"],
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = dict["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let text = message["content"] as? String else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
    }

    /// 视觉模型描述图片 → 文件名（≤20 字；不含扩展名）
    static func suggestImageName(data: Data, mime: String) async throws -> String? {
        let model = "deepseek-v4-flash-vision-exp" // 强制视觉模型（flash/pro 发图 400）
        let url = URL(string: baseURL.hasSuffix("/") ? baseURL + "chat/completions" : baseURL + "/chat/completions")!
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": [
                    ["type": "image_url", "image_url": ["url": "data:\(mime);base64,\(data.base64EncodedString())"]],
                    ["type": "text", "text": "用 3-14 个字概括这张图片的内容作为文件名（不含扩展名、不加引号、不要推荐语；无法识别输出「无标题」）"],
                ]],
            ],
            "temperature": 0.3,
            "max_tokens": 48,
            "thinking": ["type": "disabled"],
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 40
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data2, _) = try await URLSession.shared.data(for: req)
        guard let dict = try? JSONSerialization.jsonObject(with: data2) as? [String: Any],
              let choices = dict["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let text = message["content"] as? String else { return nil }
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        return isValidTitle(name) ? name : nil
    }

    // MARK: - AI 问答 / 快捷操作（流式 SSE / 单轮 complete）

    /// 对话消息（支持 tool 角色与 assistant 的 tool_calls）
    struct Message {
        let role: String                       // "user" / "assistant" / "tool"
        let content: String
        var toolCallID: String? = nil
        var toolCalls: [FileTools.ParsedCall]? = nil

        init(role: String, content: String, toolCallID: String? = nil, toolCalls: [FileTools.ParsedCall]? = nil) {
            self.role = role
            self.content = content
            self.toolCallID = toolCallID
            self.toolCalls = toolCalls
        }

        func toJSON() -> [String: Any] {
            var d: [String: Any] = ["role": role, "content": content]
            if let id = toolCallID { d["tool_call_id"] = id }
            if let calls = toolCalls {
                d["tool_calls"] = calls.map { c in
                    var f: [String: Any] = ["name": c.name, "arguments": c.arguments]
                    var dd: [String: Any] = ["function": f]
                    if c.id != "" { dd["id"] = c.id } else { dd["id"] = c.name }
                    dd["type"] = "function"
                    return dd
                }
            }
            return d
        }
    }

    private static func endpoint() -> URL {
        URL(string: baseURL.hasSuffix("/") ? baseURL + "chat/completions" : baseURL + "/chat/completions")!
    }

    private static var defaultModel: String {
        UserDefaults.standard.string(forKey: kModel) ?? "deepseek-v4-flash-vision-exp"
    }

    private static func request(model: String, system: String, messages: [Message],
                                temperature: Double, stream: Bool, maxTokens: Int = 1024,
                                tools: [[String: Any]]? = nil) -> URLRequest {
        var list: [[String: Any]] = [["role": "system", "content": system]]
        list += messages.map { $0.toJSON() }
        var body: [String: Any] = [
            "model": model,
            "messages": list,
            "temperature": temperature,
            "max_tokens": maxTokens,
            "stream": stream,
            // V4 默认思考开启；问答/改写要即时反馈 → 显式关闭（自动命名同此约定）
            "thinking": ["type": "disabled"],
        ]
        if let tools { body["tools"] = tools }
        var req = URLRequest(url: endpoint())
        req.httpMethod = "POST"
        req.timeoutInterval = stream ? 120 : 60
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// 流式问答（OpenAI 兼容 SSE；逐段 yield 文本增量）
    static func chatStream(model: String? = nil, system: String, messages: [Message],
                           temperature: Double = 0.6) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let req = request(model: model ?? defaultModel, system: system,
                              messages: messages, temperature: temperature, stream: true)
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw LLMError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
                    }
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choice = (obj["choices"] as? [[String: Any]])?.first,
                              let delta = (choice["delta"] as? [String: Any])?["content"] as? String else { continue }
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 单轮完整回答（快捷操作：翻译/改写/润色；无流 UI 则整体拼接）
    static func complete(model: String? = nil, system: String, user: String,
                         temperature: Double = 0.4, maxTokens: Int = 2048) async throws -> String {
        let req = request(model: model ?? defaultModel, system: system,
                          messages: [Message(role: "user", content: user)],
                          temperature: temperature, stream: false, maxTokens: maxTokens)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LLMError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = dict["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw LLMError.badResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 文件代理流式（text 增量 + tool_calls 累积）

    enum StreamEvent {
        case text(String)
        case toolCall(FileTools.ParsedCall)
    }

    /// 流式调用（支持 tools）：文本增量即时 yield；全部完成后按序 yield 累积的 tool_calls。
    static func chatStreamTools(model: String? = nil, system: String, messages: [Message],
                                tools: [[String: Any]]? = FileTools.specs,
                                temperature: Double = 0.4) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let req = request(model: model ?? defaultModel, system: system,
                              messages: messages, temperature: temperature, stream: true,
                              maxTokens: 4096, tools: tools)
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw LLMError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
                    }
                    // tool_calls 按 index 累积（id/name/arguments 分片到达）
                    var acc: [Int: (id: String, name: String, args: String)] = [:]
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choice = (obj["choices"] as? [[String: Any]])?.first,
                              let delta = choice["delta"] as? [String: Any] else { continue }
                        if let text = delta["content"] as? String, !text.isEmpty {
                            continuation.yield(.text(text))
                        }
                        if let calls = delta["tool_calls"] as? [[String: Any]] {
                            for c in calls {
                                let idx = (c["index"] as? Int) ?? 0
                                var item = acc[idx] ?? ("", "", "")
                                if let id = c["id"] as? String, !id.isEmpty { item.id = id }
                                if let fn = c["function"] as? [String: Any] {
                                    if let name = fn["name"] as? String, !name.isEmpty { item.name = name }
                                    if let args = fn["arguments"] as? String { item.args += args }
                                }
                                acc[idx] = item
                            }
                        }
                    }
                    for (_, item) in acc.sorted(by: { $0.key < $1.key }) where !item.name.isEmpty {
                        continuation.yield(.toolCall(FileTools.ParsedCall(id: item.id.isEmpty ? item.name : item.id,
                                                                         name: item.name, arguments: item.args)))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    enum LLMError: LocalizedError {
        case http(Int)
        case badResponse
        var errorDescription: String? {
            switch self {
            case .http(let code): return _L("模型服务返回 \(code)", "Model service returned \(code)")
            case .badResponse: return _L("模型响应格式异常", "Malformed model response")
            }
        }
    }

    /// 删除标题中的非法文件名字符
    static func sanitizeFileNameTitle(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "*", with: "*")
            .trimmingCharacters(in: .whitespaces)
    }
}

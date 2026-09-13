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

    // MARK: - Key 管理（设置页用；只存本机 UserDefaults，不进仓库）

    /// 写入 / 更新 API Key（会去掉首尾空白与换行——粘贴时最常见的问题）
    static func setAPIKey(_ raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { clearAPIKey() } else { UserDefaults.standard.set(key, forKey: kAPIKey) }
    }

    static func clearAPIKey() { UserDefaults.standard.removeObject(forKey: kAPIKey) }

    /// 当前 key 的掩码显示（设置页展示用，不泄露全量）
    static var maskedKey: String {
        let k = apiKey
        guard k.count > 10 else { return k.isEmpty ? "" : "••••" }
        return k.prefix(6) + "…" + k.suffix(4)
    }

    /// 连接测试：发一条最小请求，返回 nil = 成功，否则返回人话错误
    static func verifyConnection() async -> String? {
        guard configured else { return _L("未填写 API Key", "No API key") }
        let model = UserDefaults.standard.string(forKey: kModel) ?? availableModels[0]
        let url = URL(string: baseURL + "/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 4,
        ])
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return Self.httpError(http.statusCode, data).errorDescription
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// 把服务端返回体里的错误信息提取出来（401 时能看到「key 无效」这种确切原因）
    static func httpError(_ code: Int, _ data: Data) -> LLMError {
        var message: String?
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = dict["error"] as? [String: Any],
           let m = err["message"] as? String, !m.isEmpty {
            message = m
        }
        return .http(code, message)
    }

    /// 流式请求拿到非 200 时：把错误体读出来再解析（不然只剩一个状态码，用户看不懂）
    static func streamHTTPError(_ code: Int, _ bytes: URLSession.AsyncBytes) async -> LLMError {
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > 4096 { break }
            }
        } catch { /* 读不到就只报状态码 */ }
        return httpError(code, data)
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
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                    guard status == 200 else {
                        throw await Self.streamHTTPError(status, bytes)
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
            throw Self.httpError((response as? HTTPURLResponse)?.statusCode ?? -1, data)
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
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                    guard status == 200 else {
                        throw await Self.streamHTTPError(status, bytes)
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
        case http(Int, String?)
        case badResponse
        var errorDescription: String? {
            switch self {
            case .http(let code, let message):
                switch code {
                case 401, 403:
                    let tail = message.map { "（服务端：\($0)）" } ?? ""
                    return _L("API Key 无效或已过期，请在「设置 → 通用 → 模型服务」里更新\(tail)",
                              "Invalid or expired API key — update it in Settings → General → Model service")
                case 402:
                    return _L("账户余额不足，请到模型服务商后台充值", "Insufficient balance on your model provider account")
                case 429:
                    return _L("请求过于频繁或超出配额，稍后再试", "Rate limited or quota exceeded — try again later")
                default:
                    let tail = message.map { "：\($0)" } ?? ""
                    return _L("模型服务返回 \(code)\(tail)", "Model service returned \(code)")
                }
            case .badResponse: return _L("模型响应格式异常", "Malformed model response")
            }
        }
    }

}

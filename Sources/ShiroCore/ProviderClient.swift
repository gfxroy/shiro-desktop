import Foundation

public final class ProviderClient {
    private let session: URLSession
    public init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForResource = 180
        self.session = session ?? URLSession(configuration: configuration)
    }

    public func request(_ url: URL, method: String = "POST", body: JSON? = nil, headers: [String: String] = [:], timeout: TimeInterval = 120) async throws -> JSON {
        var request = URLRequest(url: url)
        request.httpMethod = method; request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if let body { request.httpBody = try body.data() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ShiroError("Invalid server response.") }
        guard (200..<300).contains(http.statusCode) else {
            let parsed = try? JSON.parse(data)
            var detail = parsed?["error"]["message"].string ?? parsed?["error"].string ?? String(data: data.prefix(12000), encoding: .utf8) ?? "Request failed"
            if parsed == nil && (http.value(forHTTPHeaderField: "Content-Type")?.contains("text/html") == true || detail.contains("<!DOCTYPE HTML>")) {
                detail = detail.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            }
            detail = detail.replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&lt;", with: "<")
            for (name, value) in headers where ["authorization", "x-api-key", "x-goog-api-key"].contains(name.lowercased()) && !value.isEmpty { detail = detail.replacingOccurrences(of: value, with: "[redacted]").replacingOccurrences(of: value.replacingOccurrences(of: "Bearer ", with: ""), with: "[redacted]") }
            throw ModelServiceError(status: http.statusCode, detail: detail)
        }
        return try JSON.parse(data)
    }

    public static func baseURL(_ config: ProviderConfig) throws -> URL {
        guard let url = URL(string: config.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)), let host = url.host, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw ShiroError("Enter a valid API endpoint.") }
        switch config.provider {
        case .local:
            guard ["localhost", "127.0.0.1", "::1"].contains(host), ["http", "https"].contains(url.scheme ?? "") else { throw ShiroError("Local model endpoints must use localhost or a loopback IP.") }
        default:
            guard host == URL(string: config.provider.endpoint)?.host, url.scheme == "https" else { throw ShiroError("Cloud API keys can only be sent to the provider's official HTTPS endpoint.") }
        }
        return url
    }

    private func headers(_ provider: Provider, _ key: String) throws -> [String: String] {
        if provider != .local && key.isEmpty { throw ShiroError("Add your \(provider.title) API key in Models & connections.") }
        switch provider {
        case .claude: return ["x-api-key": key, "anthropic-version": "2023-06-01"]
        case .gemini: return ["x-goog-api-key": key]
        default: return key.isEmpty ? [:] : ["Authorization": "Bearer \(key)"]
        }
    }

    public func models(config: ProviderConfig, key: String) async throws -> [String] {
        let base = try Self.baseURL(config)
        let result = try await request(base.appendingPathComponent("models"), method: "GET", headers: headers(config.provider, key), timeout: config.provider == .local ? 3 : 30)
        if config.provider == .gemini {
            return result["models"].array.filter { $0["supportedGenerationMethods"].array.contains(.string("generateContent")) }.compactMap { $0["name"].string?.replacingOccurrences(of: "models/", with: "") }.sorted()
        }
        return result["data"].array.compactMap { $0["id"].string }.sorted()
    }

    public func complete(config: ProviderConfig, key: String, system: String, history: [JSON], tools: [ToolDefinition] = ToolDefinition.all, maxOutputTokens: Int? = nil, progress: (@Sendable (Int) async -> Void)? = nil) async throws -> ModelReply {
        guard !config.model.trimmingCharacters(in: .whitespaces).isEmpty else { throw ShiroError("Choose a model in Models & connections first.") }
        let base = try Self.baseURL(config), auth = try headers(config.provider, key)
        let offered = ToolDefinition.offered(tools, for: config.provider)
        let schemas = offered.map { $0.wire(for: config.provider) }
        let body: JSON, url: URL
        switch config.provider {
        case .openAI:
            url = base.appendingPathComponent("responses")
            body = .object(["model": .string(config.model), "instructions": .string(system), "input": .array(history), "tools": .array(schemas), "store": .bool(false), "include": .array([.string("reasoning.encrypted_content")]), "max_output_tokens": .number(8192)])
        case .claude:
            url = base.appendingPathComponent("messages")
            body = .object(["model": .string(config.model), "system": .string(system), "messages": .array(Self.mergeClaude(history)), "tools": .array(schemas), "max_tokens": .number(8192)])
        case .gemini:
            guard config.model.range(of: #"^[a-zA-Z0-9._-]+$"#, options: .regularExpression) != nil else { throw ShiroError("Invalid Gemini model identifier.") }
            url = base.appendingPathComponent("models/\(config.model):generateContent")
            body = .object(["systemInstruction": .object(["parts": .array([.object(["text": .string(system)])])]), "contents": .array(Self.mergeGemini(history)), "tools": .array([.object(["functionDeclarations": .array(schemas)])]), "generationConfig": .object(["maxOutputTokens": .number(8192)])])
        case .local:
            guard !config.model.lowercased().contains("cloud") else { throw ShiroError("Choose a downloaded local model. Cloud-routed models are disabled in Shiro's Local provider.") }
            url = base.appendingPathComponent("chat/completions")
            var fields: [String: JSON] = ["model": .string(config.model), "messages": .array([.object(["role": .string("system"), "content": .string(system)])] + history), "stream": .bool(true)]
            if !schemas.isEmpty { fields["tools"] = .array(schemas) }
            if (config.localRuntime == .ollama || base.port == 11434), config.model.lowercased().hasPrefix("qwen") {
                fields["reasoning_effort"] = .string(config.localThinking == true ? "medium" : "none")
            }
            fields[config.localRuntime == .liteRT ? "max_completion_tokens" : "max_tokens"] = .number(Double(maxOutputTokens ?? (config.localRuntime == .liteRT ? 1536 : 4096)))
            body = .object(fields)
        }
        let response = config.provider == .local ? try await streamLocal(url, body: body, headers: auth, progress: progress) : try await request(url, body: body, headers: auth)
        return try Self.parseReply(response, provider: config.provider)
    }

    private func streamLocal(_ url: URL, body: JSON, headers: [String: String], progress: (@Sendable (Int) async -> Void)?) async throws -> JSON {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.httpBody = try body.data(); request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw ShiroError("Invalid local server response.") }
            var received = 0
            if !(200..<300).contains(http.statusCode) || !(http.value(forHTTPHeaderField: "Content-Type") ?? "").contains("text/event-stream") {
                var data = Data()
                for try await byte in bytes {
                    try Task.checkCancellation(); data.append(byte)
                    guard data.count <= 2_000_000 else { throw ShiroError("Local server response exceeded the size limit.") }
                }
                guard (200..<300).contains(http.statusCode) else {
                    let parsed = try? JSON.parse(data)
                    let detail = parsed?["error"]["message"].string ?? parsed?["error"].string ?? String(decoding: data.prefix(1200), as: UTF8.self).replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                    throw ModelServiceError(status: http.statusCode, detail: detail)
                }
                return try JSON.parse(data) // Compatible servers may return ordinary JSON despite stream:true.
            }
            var stream = LocalCompletionStream(), lastUpdate = Date.distantPast
            for try await line in bytes.lines {
                try Task.checkCancellation()
                received += line.utf8.count
                guard received <= 2_000_000 else { throw ShiroError("Local server response exceeded the size limit.") }
                if try stream.consume(line) { break }
                if Date().timeIntervalSince(lastUpdate) >= 0.25 {
                    await progress?(stream.chunks); lastUpdate = Date()
                }
            }
            return try stream.response()
        } catch let error as URLError where error.code == .timedOut {
            throw ShiroError("The local model did not finish within 3 minutes (or sent no data for 90 seconds). Stop other model jobs, reduce context or choose a smaller model, then retry. Check the runtime log in Debug & repair.")
        }
    }

    public static func parseReply(_ response: JSON, provider: Provider) throws -> ModelReply {
        var text: [String] = [], calls: [ToolCall] = [], native: [JSON] = []
        switch provider {
        case .openAI:
            native = response["output"].array
            for item in native {
                if item["type"].string == "function_call" {
                    guard let args = item["arguments"].string, let id = item["call_id"].string, let name = item["name"].string else { throw ShiroError("Malformed OpenAI function call.") }
                    calls.append(.init(id: id, name: name, arguments: try JSON.parse(args)))
                }
                for block in item["content"].array {
                    if let value = block["text"].string ?? block["refusal"].string { text.append(value) }
                }
            }
            if response["status"].string == "incomplete" { throw ShiroError("OpenAI reached its output limit. Use a shorter request or another model.") }
        case .claude:
            let content = response["content"].array
            native = [.object(["role": .string("assistant"), "content": .array(content)])]
            for block in content {
                if let value = block["text"].string { text.append(value) }
                if block["type"].string == "tool_use", let id = block["id"].string, let name = block["name"].string { calls.append(.init(id: id, name: name, arguments: block["input"])) }
            }
            if response["stop_reason"].string == "max_tokens" { throw ShiroError("Claude reached its output limit. Shorten the task or select another model.") }
        case .gemini:
            guard let candidate = response["candidates"].array.first else { throw ShiroError("Gemini returned no candidate: \(response["promptFeedback"].text)") }
            let content = candidate["content"]
            native = [content]
            for part in content["parts"].array {
                if let value = part["text"].string, part["thought"].bool != true { text.append(value) }
                if let name = part["functionCall"]["name"].string {
                    calls.append(.init(id: part["functionCall"]["id"].string ?? UUID().uuidString, name: name, arguments: part["functionCall"]["args"], nativeID: part["functionCall"]["id"].string))
                }
            }
            // Preserve original model parts, including thought signatures, in the next request.
            if candidate["finishReason"].string == "MAX_TOKENS" { throw ShiroError("Gemini reached its output limit. Try a shorter task.") }
        case .local:
            guard let choice = response["choices"].array.first else { throw ShiroError("Local server returned no completion.") }
            let message = choice["message"]
            // Only replay documented chat-completion fields; do not retain server-specific metadata.
            var fields: [String: JSON] = ["role": .string("assistant"), "content": message["content"]]
            if !message["tool_calls"].array.isEmpty { fields["tool_calls"] = message["tool_calls"] }
            native = [.object(fields)]
            if let value = message["content"].string { text.append(value) }
            for call in message["tool_calls"].array {
                guard let args = call["function"]["arguments"].string, let name = call["function"]["name"].string else { throw ShiroError("Malformed local tool call. Choose a model that supports tools.") }
                calls.append(.init(id: call["id"].string ?? UUID().uuidString, name: name, arguments: try JSON.parse(args)))
            }
            if choice["finish_reason"].string == "length" { throw ShiroError("Local model reached its output limit.") }
            guard !text.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !calls.isEmpty else { throw ShiroError("The local model returned an empty answer. Retry or select another model.") }
        }
        guard !native.isEmpty else { throw ShiroError("Provider returned an empty response.") }
        return ModelReply(text: text.joined(separator: "\n\n").replacingOccurrences(of: "\\/", with: "/"), calls: calls, native: native)
    }

    public static func user(_ text: String, provider: Provider, image: String? = nil) -> JSON {
        switch provider {
        case .openAI:
            var parts: [JSON] = [.object(["type": .string("input_text"), "text": .string(text)])]
            if let image { parts.append(.object(["type": .string("input_image"), "image_url": .string("data:image/png;base64,\(image)")])) }
            return .object(["role": .string("user"), "content": .array(parts)])
        case .claude:
            var parts: [JSON] = [.object(["type": .string("text"), "text": .string(text)])]
            if let image { parts.append(.object(["type": .string("image"), "source": .object(["type": .string("base64"), "media_type": .string("image/png"), "data": .string(image)])])) }
            return .object(["role": .string("user"), "content": .array(parts)])
        case .gemini:
            var parts: [JSON] = [.object(["text": .string(text)])]
            if let image { parts.append(.object(["inlineData": .object(["mimeType": .string("image/png"), "data": .string(image)])])) }
            return .object(["role": .string("user"), "parts": .array(parts)])
        case .local:
            if let image { return .object(["role": .string("user"), "content": .array([.object(["type": .string("text"), "text": .string(text)]), .object(["type": .string("image_url"), "image_url": .object(["url": .string("data:image/png;base64,\(image)")])])])]) }
            return .object(["role": .string("user"), "content": .string(text)])
        }
    }

    public static func toolResult(_ call: ToolCall, result: JSON, provider: Provider) -> JSON {
        switch provider {
        case .openAI: return .object(["type": .string("function_call_output"), "call_id": .string(call.id), "output": .string(result.text)])
        case .claude: return .object(["role": .string("user"), "content": .array([.object(["type": .string("tool_result"), "tool_use_id": .string(call.id), "content": .string(result.text)])])])
        case .gemini:
            var response: [String: JSON] = ["name": .string(call.name), "response": result]
            if let id = call.nativeID { response["id"] = .string(id) }
            return .object(["role": .string("user"), "parts": .array([.object(["functionResponse": .object(response)])])])
        case .local: return .object(["role": .string("tool"), "tool_call_id": .string(call.id), "content": .string(result.text)])
        }
    }

    public static func mergeClaude(_ history: [JSON]) -> [JSON] {
        var merged: [JSON] = []
        for message in history {
            if let last = merged.last, last["role"] == message["role"] {
                merged[merged.count - 1] = .object(["role": message["role"], "content": .array(last["content"].array + message["content"].array)])
            } else { merged.append(message) }
        }
        return merged
    }
    public static func mergeGemini(_ history: [JSON]) -> [JSON] {
        var merged: [JSON] = []
        for message in history {
            if let last = merged.last, last["role"] == message["role"] {
                merged[merged.count - 1] = .object(["role": message["role"], "parts": .array(last["parts"].array + message["parts"].array)])
            } else { merged.append(message) }
        }
        return merged
    }
}

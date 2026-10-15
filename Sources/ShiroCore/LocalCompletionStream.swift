import Foundation

/// Accumulates native deltas; tools are never released until a complete response arrives.
public struct LocalCompletionStream {
    private var content = ""
    private var calls: [Int: JSON] = [:]
    private var finish: String?
    public private(set) var chunks = 0
    public init() {}

    public mutating func consume(_ line: String) throws -> Bool {
        guard line.hasPrefix("data:") else { return false }
        let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        if data == "[DONE]" { return true }
        let value = try JSON.parse(data)
        if value["error"] != .null { throw ShiroError(value["error"]["message"].string ?? value["error"].string ?? "Local inference failed.") }
        guard let choice = value["choices"].array.first else { return false }
        let delta = choice["delta"]
        if let text = delta["content"].string { content += text }
        for call in delta["tool_calls"].array {
            guard let number = call["index"].number, number >= 0, number < 128, number.rounded() == number else { throw ShiroError("Malformed streamed tool index.") }
            let index = Int(number), old = calls[index] ?? .null
            calls[index] = .object([
                "id": .string(call["id"].string ?? old["id"].string ?? UUID().uuidString), "type": .string("function"),
                "function": .object(["name": .string((old["function"]["name"].string ?? "") + (call["function"]["name"].string ?? "")), "arguments": .string((old["function"]["arguments"].string ?? "") + (call["function"]["arguments"].string ?? ""))])
            ])
        }
        if let reason = choice["finish_reason"].string { finish = reason }
        if delta["content"].string != nil || !delta["tool_calls"].array.isEmpty || delta["reasoning_content"].string != nil { chunks += 1 }
        return finish != nil
    }

    public func response() throws -> JSON {
        guard let finish, ["stop", "tool_calls", "length"].contains(finish) else { throw ShiroError("The local model stream ended before a complete response. Retry or check the runtime.") }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !calls.isEmpty || finish == "length" else { throw ShiroError("The local model returned an empty answer. Retry or select another model.") }
        return .object(["choices": .array([.object(["message": .object(["role": .string("assistant"), "content": .string(content), "tool_calls": .array(calls.keys.sorted().compactMap { calls[$0] })]), "finish_reason": .string(finish)])])])
    }
}

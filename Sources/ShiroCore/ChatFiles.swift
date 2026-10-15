import Foundation

public struct ChatFile: Codable, Identifiable, Equatable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let bytes: Int
    public init(path: String, name: String? = nil, bytes: Int = 0) {
        self.path = path; self.name = name ?? URL(fileURLWithPath: path).lastPathComponent; self.bytes = bytes
    }
    public static func safePath(_ value: String) -> String? {
        let root = "/home/shiro-local/workspace/"
        let path = value.hasPrefix(root) ? String(value.dropFirst(root.count)) : value
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~"), !path.contains("\0"), !path.split(separator: "/").contains("..") else { return nil }
        return path
    }
    public static func references(in text: String) -> [ChatFile] {
        let regex = try! NSRegularExpression(pattern: #"(?:/home/shiro-local/workspace/)?(?:[\w.-]+/)*[\w.-]+\.(?:pdf|docx?|xlsx?|csv|pptx?|md|txt|html|json|png|jpe?g|webp|svg|zip|mp4|mp3|wav)\b"#, options: [.caseInsensitive])
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        return regex.matches(in: text, range: range).compactMap {
            guard let r = Range($0.range, in: text), let p = safePath(String(text[r])), seen.insert(p).inserted else { return nil }
            // URLs are web citations, not VM files.
            let before = String(text[..<r.lowerBound].suffix(8))
            guard !before.contains("://") else { return nil }
            return ChatFile(path: p)
        }
    }
}

public enum RunCheckpoint {
    public static func continuation(task: String) -> String {
        "Automatic checkpoint. Continue the original task: \(task). Work is still active; use tools to finish and verify. Do not repeat completed side effects, approvals or messages. A progress promise is not completion. If blocked, state the specific blocker honestly."
    }
    public static func promisesWork(_ text: String) -> Bool {
        let pattern = #"\b(?:i\s+will|i['’]ll|let\s+me|i(?:['’]m|\s+am)\s+going\s+to)\s+(?:(?:now|then|first|next|also|again)\s+)*(?:search|inspect|re[- ]?execute|check|read|open|browse|navigate|fetch|find|use|try|start|continue|fill|click|run|create|write|build|look|extract|list|verify|gather|collect|download|analy[sz]e|review|perform)\b"#
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
    public static func recoveryTools(task: String, provider: Provider, corrections: Int) -> [ToolDefinition] {
        guard provider == .local, corrections > 0, TaskCompletion.requestedJobCount(task) != nil else { return ToolDefinition.all }
        // Reduce choices for a stalled small model until one real observation succeeds.
        return ToolDefinition.all.filter { ["search", "context"].contains($0.name) }
            + ToolDefinition.localBrowser.filter { ["browser_open", "browser_read"].contains($0.name) }
            + [ToolDefinition.localFileRead]
    }
}

public enum RunTask {
    public static func isFollowUp(_ message: String) -> Bool {
        let first = message.components(separatedBy: "\nAttached files in your VM")[0]
        let value = first.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return ["", "continue", "go on", "resume", "keep going", "keep working", "do it", "finish it", "find the job", "find the jobs", "find jobs", "find me jobs"].contains(value)
    }
    public static func objective(latest: String, chat: Conversation) -> String {
        guard isFollowUp(latest) else { return latest }
        if let goal = chat.activeObjective, !goal.isEmpty { return goal }
        guard chat.lastRunOutcome != "completed" else { return latest }
        // Recover the original request in pre-upgrade chats, without pinning short nudges as new tasks.
        return chat.entries.reversed().first { $0.role == "user" && !isFollowUp($0.text) }?.text ?? latest
    }
    public static func prompt(latest: String, objective: String) -> String {
        guard latest != objective else { return latest }
        return "Original unfinished user task:\n\(objective)\nLatest user follow-up:\n\(latest)\nThe follow-up continues the original task and its requested result count. Earlier progress promises are not completed actions. Use actual tools and finish the original result, or state a concrete verified blocker."
    }
    public static func mayClearInterruptedRead(_ marker: String) -> Bool {
        let parts = marker.components(separatedBy: ": ")
        guard let name = parts.first else { return false }
        if name == "search" { return true }
        guard name == "browser", let json = try? JSON.parse(parts.dropFirst().joined(separator: ": ")) else { return false }
        return ["read", "navigate", "tabs"].contains(json["action"].string ?? "")
    }
    public static func recoveredBrowserRead(_ raw: JSON) -> JSON? {
        guard let url = raw["url"].string, !url.isEmpty else { return nil }
        let result = ToolRecovery.feedback(.init(id: "interruption_observation", name: "browser", arguments: .object(["action": .string("read"), "offset": .number(0)])), result: raw)
        return result["ok"].bool == true ? result : nil
    }
}

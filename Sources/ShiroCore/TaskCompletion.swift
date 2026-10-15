import Foundation

public enum TaskCompletion {
    public static func requestedJobCount(_ task: String) -> Int? {
        let request = task.lowercased().replacingOccurrences(of: #"\bten\b"#, with: "10", options: .regularExpression)
        let regex = try! NSRegularExpression(pattern: #"\b([1-9][0-9]?)\s+(?:jobs?|jibs?|openings?|roles?|listings?)\b"#)
        if let match = regex.firstMatch(in: request, range: NSRange(request.startIndex..., in: request)), let range = Range(match.range(at: 1), in: request), let count = Int(request[range]), count <= 30 { return count }
        if request.range(of: #"\b(?:find|search|look\s+for|list|get)\b[\s\S]{0,180}\b(?:jobs?|jibs?|openings?)\b"#, options: .regularExpression) != nil { return 1 }
        return nil
    }
    public static func jobLinkCount(_ answer: String) -> Int {
        let normalized = answer.replacingOccurrences(of: "\\/", with: "/")
        let urls = try! NSRegularExpression(pattern: #"https?://[^\s<>\)\]\"`]+"#)
        return Set(urls.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)).compactMap { Range($0.range, in: normalized).map { String(normalized[$0]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;")) } }).count
    }
    public static func disclosedJobShortfall(answer: String, task: String) -> Bool {
        guard let count = requestedJobCount(task), jobLinkCount(answer) < count else { return false }
        let lower = answer.lowercased()
        return ["could only verify", "only verified", "couldn't verify", "could not verify"].contains(where: lower.contains)
    }
    public static func missingJobResults(answer: String, task: String) -> String? {
        guard let count = requestedJobCount(task) else { return nil }
        let found = jobLinkCount(answer)
        guard found < count else { return nil }
        if disclosedJobShortfall(answer: answer, task: task) { return nil }
        return "The user asked for \(count) jobs with links; this answer contains only \(found) distinct URLs. A CV summary is not the requested result. Continue researching real job pages in the VM, verify openings, and return role, employer, location and direct links. If fewer can be verified, explicitly disclose the shortfall and concrete blocker. Do not finish with another plan or repeat the CV."
    }
}

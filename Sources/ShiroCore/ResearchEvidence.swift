import Foundation

public struct ResearchEvidence {
    public private(set) var opened: Set<String> = []
    private var researched = false
    private var titles: [String: String] = [:]
    public init() {}
    public mutating func observe(call: ToolCall, result: JSON) {
        if call.name == "search" { researched = true }
        guard call.name == "browser", result["ok"].bool == true, result["blocked"].bool != true,
              let url = result["url"].string, !(result["text"].string ?? "").isEmpty else { return }
        researched = true
        if let canonical = Self.canonical(url) {
            opened.insert(canonical)
            if let title = result["title"].string, !title.isEmpty { titles[canonical] = title }
        }
    }
    private static func canonical(_ text: String) -> String? {
        guard var c = URLComponents(string: text), ["http", "https"].contains(c.scheme ?? ""), let host = c.host else { return nil }
        guard !["google.com", "www.google.com", "bing.com", "www.bing.com", "duckduckgo.com", "html.duckduckgo.com"].contains(host.lowercased()) else { return nil }
        c.fragment = nil; c.host = host.lowercased()
        if c.path.hasSuffix("/") { c.path.removeLast() }
        return c.string
    }
    public func correction(answer: String, task: String) -> String? {
        let request = task.lowercased()
        let strictTitle = Self.wantsTitle(task)
        guard researched || strictTitle || ["jobs", "job openings", "research", "search"].contains(where: request.contains) else { return nil }
        let pattern = #"https?://[^\s<>\)\]\"`]+"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let normalized = answer.replacingOccurrences(of: "\\/", with: "/")
        let citations = regex.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)).compactMap { Range($0.range, in: normalized).map { String(normalized[$0]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;")) } }
        let unchecked = citations.filter { Self.canonical($0).map { !opened.contains($0) } ?? true }
        if !unchecked.isEmpty { return "These URLs have not been opened and verified in a successful browser result: \(unchecked.prefix(8).joined(separator: ", ")). Search links are leads, not confirmed listings. Open the original pages with browser navigate/read, verify the actual details, then cite them. If blocked, label the coverage limit rather than claiming verification." }
        if strictTitle && titles.isEmpty { return "The user asked for the actual page title, but no successful page title has been observed in this run. Read the real browser page and copy its title and URL exactly." }
        if strictTitle, !titles.isEmpty, !titles.values.contains(where: { answer.localizedCaseInsensitiveContains($0) }) {
            let expected = titles.sorted(by: { $0.key < $1.key }).map { "Title: \($0.value) · URL: \($0.key)" }.joined(separator: "\n")
            return "Exact title mismatch. The actual browser observations are:\n\(expected)\nCopy the observed title verbatim, including version numbers, rather than shortening or guessing it. Regenerate the answer with its exact observed URL."
        }
        if strictTitle && request.contains("url"), !titles.contains(where: { url, title in normalized.localizedCaseInsensitiveContains(title) && citations.contains(where: { Self.canonical($0) == url }) }) {
            let expected = titles.sorted(by: { $0.key < $1.key }).map { "Title: \($0.value) · URL: \($0.key)" }.joined(separator: "\n")
            return "The requested exact title and URL must both match the same real browser observation. Copy these fields verbatim:\n\(expected)"
        }
        let text = answer.lowercased()
        if ["jobs", "job openings", "research", "search"].contains(where: request.contains), opened.isEmpty,
           ["i found", "verified", "here are", "confirmed", "job listings"].contains(where: text.contains) {
            return "No successful primary-source page has been opened in this run. Verify your claimed findings using browser tools and provide exact URLs; security pages and search snippets are not verified evidence. Do not invent listings."
        }
        return nil
    }
    public func exactPageFacts(task: String) -> String? {
        guard Self.wantsTitle(task), titles.count == 1, let page = titles.first else { return nil }
        return "Observed browser page title: \(page.value)\nURL: \(page.key)"
    }
    private static func wantsTitle(_ task: String) -> Bool {
        let value = task.lowercased()
        return value.contains("page title") && ["actual", "exact", "verbatim"].contains(where: value.contains)
    }
}

import Foundation

public enum AttachmentPaths {
    public static func registeredPaths(_ attachments: [ChatFile]) -> [String] {
        Array(Set(attachments.compactMap { ChatFile.safePath($0.path) })).sorted()
    }
    public static func feedback(_ call: ToolCall, result: JSON, attachments: [ChatFile]) -> JSON {
        guard call.name == "files", ["read", "stat"].contains(call.arguments["action"].string ?? ""), result["error"].string != nil else { return result }
        let paths = Array(registeredPaths(attachments).prefix(8))
        guard !paths.isEmpty else { return result }
        var fields = result.object
        fields["available_attachments"] = .array(paths.map(JSON.string))
        fields["recovery"] = .string((result["recovery"].string ?? "") + " The user-selected files are listed in available_attachments. Copy an exact registered path into files_read(path: ..., offset: 0); do not invent CV.pdf.txt or guess another filename. A .pdf.txt companion contains extracted PDF text. No failed read has been completed.")
        return .object(fields)
    }
    public static func resolve(_ requested: String, attachments: [ChatFile]) throws -> String {
        guard !requested.contains("\0"), !requested.split(separator: "/").contains("..") else { throw ShiroError("Unsafe file path. Use the attachment filename.") }
        if let safe = ChatFile.safePath(requested), attachments.contains(where: { $0.path == safe }) { return safe }
        let filename = URL(fileURLWithPath: requested).lastPathComponent
        let matches = Array(Set(attachments.filter { ChatFile.safePath($0.path) != nil && URL(fileURLWithPath: $0.path).lastPathComponent == filename }.map(\.path)))
        if matches.count == 1 { return matches[0] }
        if matches.count > 1 { throw ShiroError("Two attachments have this filename. Use their exact registered paths; no file was guessed.") }
        guard let safe = ChatFile.safePath(requested) else { throw ShiroError("Use a registered attachment filename or workspace-relative path.") }
        return safe
    }
}

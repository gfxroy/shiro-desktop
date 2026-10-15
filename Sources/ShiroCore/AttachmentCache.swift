import Foundation

/// Private copies of explicitly selected attachments; never a host-folder mount.
public final class AttachmentCache {
    public let directory: URL
    public init(root: URL? = nil) {
        directory = (root ?? StateStore().directory.appendingPathComponent("AttachmentCache")).standardizedFileURL.resolvingSymlinksInPath()
    }
    public static func accepts(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 3 && parts[0] == "attachments" && UUID(uuidString: String(parts[1])) != nil && !["", ".", ".."].contains(String(parts[2])) && !path.contains("\0")
    }
    private func location(_ file: ChatFile, create: Bool) throws -> URL {
        guard Self.accepts(file.path) else { throw ShiroError("Only registered attachment paths can be cached.") }
        let parts = file.path.split(separator: "/")
        let folder = directory.appendingPathComponent(String(parts[1]), isDirectory: true)
        if (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { throw ShiroError("Attachment cache folders cannot be symbolic links.") }
        guard folder.resolvingSymlinksInPath().deletingLastPathComponent().path == directory.path else { throw ShiroError("Unsafe attachment cache folder.") }
        if create {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let target = folder.appendingPathComponent(String(parts[2]))
        if (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { throw ShiroError("Attachment cache files cannot be symbolic links.") }
        return target
    }
    public func store(_ data: Data, for file: ChatFile) throws {
        guard data.count <= 32 * 1024 * 1024 else { throw ShiroError("Attachment cache files must be under 32 MB.") }
        let target = try location(file, create: true)
        try data.write(to: target, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }
    public func store(_ source: URL, for file: ChatFile) throws {
        let info = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, let size = info.fileSize, size <= 32 * 1024 * 1024 else { throw ShiroError("Cache only a regular user-selected file under 32 MB.") }
        try store(Data(contentsOf: source), for: file)
    }
    public func cached(_ file: ChatFile) throws -> URL? {
        let target = try location(file, create: false)
        guard FileManager.default.fileExists(atPath: target.path) else { return nil }
        let info = try target.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? Int.max) <= 32 * 1024 * 1024 else { throw ShiroError("Invalid cached attachment.") }
        return target
    }
}

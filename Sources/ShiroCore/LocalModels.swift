import Foundation
import CryptoKit

public final class LocalModels {
    public init() {}
    public static func root(_ config: ProviderConfig) throws -> URL {
        var url = try ProviderClient.baseURL(config)
        if url.lastPathComponent == "v1" { url.deleteLastPathComponent() }
        return url
    }
    public func pull(_ model: String, config: ProviderConfig, progress: @escaping (String, Double?) async -> Void) async throws {
        guard model.range(of: #"^[a-zA-Z0-9][a-zA-Z0-9_./:-]{0,200}$"#, options: .regularExpression) != nil else { throw ShiroError("Enter a valid Ollama model name.") }
        guard !model.lowercased().contains("cloud") else { throw ShiroError("Use a downloadable local model, rather than an Ollama cloud model.") }
        let root = try Self.root(config)
        try await stream(root.appendingPathComponent("api/pull"), body: .object(["model": .string(model), "stream": .bool(true)]), progress: progress)
    }
    public func importGGUF(_ file: URL, name: String, config: ProviderConfig, progress: @escaping (String, Double?) async -> Void) async throws {
        guard file.pathExtension.lowercased() == "gguf" else { throw ShiroError("Import a GGUF file. MLX/safetensors folders require a compatible server such as LM Studio or an MLX server.") }
        guard name.range(of: #"^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,80}$"#, options: .regularExpression) != nil else { throw ShiroError("Use letters, digits, dots, underscores, or hyphens for the model name.") }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        guard try handle.read(upToCount: 4) == Data("GGUF".utf8) else { throw ShiroError("The selected file is not a valid GGUF model.") }
        try handle.seek(toOffset: 0)
        await progress("Checking model file…", nil)
        let hashTask = Task.detached(priority: .utility) {
            var hash = SHA256()
            while true {
                try Task.checkCancellation()
                let read = try autoreleasepool { () throws -> Bool in
                    guard let block = try handle.read(upToCount: 1024 * 1024), !block.isEmpty else { return false }
                    hash.update(data: block)
                    return true
                }
                if !read { break }
            }
            return hash.finalize().map { String(format: "%02x", $0) }.joined()
        }
        let digest = try await withTaskCancellationHandler(operation: { try await hashTask.value }, onCancel: { hashTask.cancel() })
        try Task.checkCancellation()
        let root = try Self.root(config), blob = "sha256:" + digest
        let blobURL = root.appendingPathComponent("api/blobs/" + blob)
        var probe = URLRequest(url: blobURL); probe.httpMethod = "HEAD"; probe.timeoutInterval = 30
        let (_, probeResponse) = try await URLSession.shared.data(for: probe)
        guard let probeHTTP = probeResponse as? HTTPURLResponse else { throw ShiroError("Invalid Ollama blob response.") }
        if probeHTTP.statusCode == 404 {
            var request = URLRequest(url: blobURL)
            request.httpMethod = "POST"; request.timeoutInterval = 3600
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            await progress("Importing model into Ollama…", nil)
            let (responseData, response) = try await URLSession.shared.upload(for: request, fromFile: file)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw ShiroError("Ollama could not import the model: \(String(decoding: responseData.prefix(400), as: UTF8.self))") }
        } else if !(200..<300).contains(probeHTTP.statusCode) {
            throw ShiroError("This local server does not support Ollama's model-import API (HTTP \(probeHTTP.statusCode)).")
        }
        try await stream(root.appendingPathComponent("api/create"), body: .object(["model": .string(name), "files": .object(["model.gguf": .string(blob)]), "stream": .bool(true)]), progress: progress)
    }
    private func stream(_ url: URL, body: JSON, progress: @escaping (String, Double?) async -> Void) async throws {
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.httpBody = try body.data()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.timeoutInterval = 3600
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw ShiroError("Ollama rejected the request. Check the server and model name.") }
        var succeeded = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard !line.isEmpty else { continue }
            let data = try JSON.parse(line)
            if let error = data["error"].string { throw ShiroError(error) }
            let total = data["total"].number ?? 0, completed = data["completed"].number ?? 0
            let status = data["status"].string ?? "Working…"
            await progress(status, total > 0 ? min(1, completed / total) : nil)
            succeeded = status == "success" || succeeded
        }
        guard succeeded else { throw ShiroError("The download ended before Ollama confirmed success. You can retry; Ollama resumes partial downloads.") }
    }
}

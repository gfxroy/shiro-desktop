import Foundation
import Darwin

public final class ModelRuntimes {
    public let directory: URL
    private var processes: [ModelLoader: Process] = [:]
    public init(directory: URL? = nil) { self.directory = directory ?? StateStore().directory }
    public func executable(_ loader: ModelLoader) -> String? {
        let environment = loader == .liteRT ? "litert-lm" : "mlx-lm"
        let binary = loader == .liteRT ? "litert-lm" : "mlx_lm.server"
        let managed = directory.appendingPathComponent("runtimes/\(environment)/bin/\(binary)").path
        if FileManager.default.isExecutableFile(atPath: managed) { return managed }
        return ProcessRunner.locate(binary)
    }
    public func install(_ loader: ModelLoader) async throws {
        guard loader == .liteRT || loader == .mlx else { throw ShiroError("This loader is managed by its own application.") }
        guard let uv = ProcessRunner.locate("uv") else { throw ShiroError("Install uv from https://docs.astral.sh/uv/getting-started/installation/ to install an isolated local runtime.") }
        let name = loader == .liteRT ? "litert-lm" : "mlx-lm"
        let env = directory.appendingPathComponent("runtimes/\(name)")
        if !FileManager.default.fileExists(atPath: env.appendingPathComponent("bin/python").path) {
            _ = try await ProcessRunner.checked(uv, ["--system-certs", "venv", "--python", "3.12", env.path], timeout: 300)
        }
        let package = loader == .liteRT ? "litert-lm==0.18.0" : "mlx-lm==0.32.0"
        _ = try await ProcessRunner.checked(uv, ["--system-certs", "pip", "install", "--python", env.appendingPathComponent("bin/python").path, package], timeout: 600)
    }
    public func linkLiteRT(_ asset: ModelAsset) throws -> URL {
        guard asset.modelID.range(of: #"^[a-zA-Z0-9][a-zA-Z0-9_-]{0,90}$"#, options: .regularExpression) != nil else { throw ShiroError("Invalid LiteRT model ID.") }
        var source = URL(fileURLWithPath: asset.path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory) else { throw ShiroError("The original model file is missing.") }
        if isDirectory.boolValue {
            let files = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil).filter { $0.pathExtension.lowercased() == "litertlm" }
            guard files.count == 1 else { throw ShiroError("Select a specific .litertlm file when a folder contains multiple models.") }
            source = files[0]
        }
        try ModelFormat.validateHeader(source, signature: Data("LITERTLM".utf8))
        let registry = directory.appendingPathComponent("litert-registry")
        let folder = registry.appendingPathComponent("models/\(asset.modelID)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let link = folder.appendingPathComponent("model.litertlm")
        if FileManager.default.fileExists(atPath: link.path) {
            guard link.resolvingSymlinksInPath().standardizedFileURL == source.resolvingSymlinksInPath().standardizedFileURL else { throw ShiroError("This model ID is already registered to another file.") }
        } else {
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        }
        let configURL = registry.appendingPathComponent("config.json")
        var config = FileManager.default.fileExists(atPath: configURL.path) ? try JSON.parse(Data(contentsOf: configURL)).object : [:]
        var defaults = config["default"]?.object ?? ["backend": .string("gpu"), "max_num_tokens": .number(8192), "thinking": .bool(false)]
        // Upgrade Shiro's old no-cache setting; preserve model-specific/user settings.
        if defaults["cache"] == nil || defaults["cache"] == .string("no") { defaults["cache"] = .string("disk") }
        config["default"] = .object(defaults)
        try JSON.object(config).data().write(to: configURL, options: .atomic)
        return registry
    }
    public func launch(_ asset: ModelAsset) async throws {
        guard asset.loader == .liteRT || asset.loader == .mlx else { throw ShiroError("Use Ollama import or connect your existing local server for this model.") }
        guard let executable = executable(asset.loader) else { throw ShiroError("Install the \(asset.loader.title) runtime using the model's Install runtime button.") }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin:/usr/bin:/bin"
        environment["HF_HUB_OFFLINE"] = "1"
        environment["TRANSFORMERS_OFFLINE"] = "1"
        let arguments: [String]
        if asset.loader == .liteRT {
            guard asset.format == .liteRT else { throw ShiroError("LiteRT-LM loads .litertlm bundles; other formats require conversion.") }
            environment["LITERT_LM_DIR"] = try linkLiteRT(asset).path
            arguments = ["serve", "--host", "127.0.0.1", "--port", "9379"]
        } else {
            guard asset.format == .safetensors else { throw ShiroError("MLX requires a compatible safetensors model folder.") }
            var folder = URL(fileURLWithPath: asset.path)
            var isDirectory: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory)
            if !isDirectory.boolValue { folder.deleteLastPathComponent() }
            guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("config.json").path) else { throw ShiroError("Choose the complete MLX model folder with config.json and tokenizer files.") }
            arguments = ["--model", folder.path, "--host", "127.0.0.1", "--port", "8081"]
        }
        try Task.checkCancellation()
        if let old = processes[asset.loader], old.isRunning {
            if asset.loader == .liteRT {
                let config = ProviderConfig(provider: .local, endpoint: asset.loader.endpoint)
                if (try? await ProviderClient().models(config: config, key: "")) != nil { return }
                try await restart(asset.loader)
            } else {
            old.terminate()
            for _ in 0..<30 { if !old.isRunning { break }; try await Task.sleep(nanoseconds: 100_000_000) }
            guard !old.isRunning else { throw ShiroError("The previous MLX server is still stopping. Retry shortly.") }
            }
        }
        // Never send model requests to an unrelated process that already owns the port.
        let config = ProviderConfig(provider: .local, endpoint: asset.loader.endpoint)
        if let models = try? await ProviderClient().models(config: config, key: "") {
            guard asset.loader == .liteRT && models.contains(asset.modelID) else { throw ShiroError("The runtime port is already in use by another server. Stop it or connect it explicitly.") }
            return
        }
        // A timed-out request can leave LiteRT's single HTTP server wedged. Only
        // recover a process whose exact CLI path and bind arguments belong to Shiro.
        if try await listener(asset.loader) != nil { try await restart(asset.loader) }
        let logURL = directory.appendingPathComponent("\(asset.loader.rawValue)-runtime.log")
        if !FileManager.default.fileExists(atPath: logURL.path) { _ = FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
        let log = try FileHandle(forWritingTo: logURL); try log.seekToEnd()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments; process.environment = environment
        process.standardOutput = log; process.standardError = log
        try process.run(); processes[asset.loader] = process
        try? log.close()
        let startupDeadline = Date().addingTimeInterval(20)
        while Date() < startupDeadline {
            try Task.checkCancellation()
            if !process.isRunning { throw ShiroError("\(asset.loader.title) exited during startup. See \(logURL.path).") }
            if (try? await ProviderClient().models(config: config, key: "")) != nil { return }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        throw ShiroError("The local runtime is not ready yet. Check \(logURL.path) and retry.")
    }
    public func stop(_ loader: ModelLoader) {
        if let process = processes[loader], process.isRunning { process.terminate() }
        processes.removeValue(forKey: loader)
    }
    private func listener(_ loader: ModelLoader) async throws -> Int32? {
        guard loader == .liteRT || loader == .mlx else { return nil }
        let port = loader == .liteRT ? "9379" : "8081"
        let result = try await ProcessRunner.run("/usr/sbin/lsof", ["-nP", "-t", "-iTCP:\(port)", "-sTCP:LISTEN"], timeout: 5)
        guard result.status == 0 || (result.status == 1 && result.stdout.isEmpty && result.stderr.isEmpty) else { throw ShiroError("Could not inspect the local runtime port. Retry after checking other model servers.") }
        let pids = Set(result.stdout.split(whereSeparator: \.isWhitespace).compactMap { Int32($0) })
        guard pids.count <= 1 else { throw ShiroError("Multiple processes hold the runtime port. Close them before loading this model.") }
        return pids.first
    }
    public func restart(_ loader: ModelLoader) async throws {
        guard let pid = try await listener(loader) else { stop(loader); return }
        let binary = loader == .liteRT ? "litert-lm" : "mlx_lm.server"
        let name = loader == .liteRT ? "litert-lm" : "mlx-lm"
        let managed = directory.appendingPathComponent("runtimes/\(name)/bin/\(binary)").path
        let port = loader == .liteRT ? "9379" : "8081"
        func fingerprint() async throws -> String {
            try await ProcessRunner.checked("/bin/ps", ["-p", String(pid), "-o", "lstart=", "-o", "command="], timeout: 5).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let original = try await fingerprint()
        guard original.contains(managed + " "), original.hasSuffix("--host 127.0.0.1 --port " + port) else {
            throw ShiroError("The runtime port is occupied by another application. Stop that server yourself or connect to it explicitly; Shiro only restarts its own managed runtime.")
        }
        guard try await fingerprint() == original else { throw ShiroError("The runtime process changed. Retry loading the model.") }
        kill(pid, SIGTERM)
        for _ in 0..<20 {
            try Task.checkCancellation()
            if try await listener(loader) == nil { processes.removeValue(forKey: loader); return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        if (try? await fingerprint()) == original { kill(pid, SIGKILL) }
        for _ in 0..<20 {
            try Task.checkCancellation()
            if try await listener(loader) == nil { processes.removeValue(forKey: loader); return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw ShiroError("The managed runtime did not stop. Quit its process and retry.")
    }
    public func importOllamaFolder(_ asset: ModelAsset) async throws {
        guard asset.loader == .ollama, [.gguf, .safetensors].contains(asset.format) else { throw ShiroError("Ollama imports GGUF and supported safetensors model folders.") }
        guard let ollama = ProcessRunner.locate("ollama") else { throw ShiroError("Install Ollama first.") }
        var folder = URL(fileURLWithPath: asset.path)
        var isDirectory: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory)
        if !isDirectory.boolValue { folder.deleteLastPathComponent() }
        var source = folder.path
        if asset.format == .gguf {
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension.lowercased() == "gguf" }
            guard !files.isEmpty else { throw ShiroError("No GGUF files found.") }
            if files.count == 1 { source = files[0].path }
            else {
                let prefixes = Set(files.map { $0.lastPathComponent.components(separatedBy: "-000")[0] })
                guard prefixes.count == 1, files.allSatisfy({ $0.lastPathComponent.contains("-of-") }) else { throw ShiroError("Choose one model file or a folder containing only its split GGUF shards.") }
                source = folder.appendingPathComponent(prefixes.first! + "-*.gguf").path
            }
        } else if !FileManager.default.fileExists(atPath: folder.appendingPathComponent("config.json").path) { throw ShiroError("Safetensors import needs the complete model folder, including config.json and tokenizer.") }
        guard !source.contains("\n"), !source.contains("\r"), asset.modelID.range(of: #"^[a-zA-Z0-9][a-zA-Z0-9_-]{0,90}$"#, options: .regularExpression) != nil else { throw ShiroError("Invalid model path or ID.") }
        let recipe = directory.appendingPathComponent("import-\(asset.id.uuidString).Modelfile")
        let escaped = source.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        try Data("FROM \"\(escaped)\"\n".utf8).write(to: recipe, options: .atomic)
        defer { try? FileManager.default.removeItem(at: recipe) }
        _ = try await ProcessRunner.checked("/usr/bin/env", ["OLLAMA_HOST=127.0.0.1:11434", "OLLAMA_NO_CLOUD=1", ollama, "create", asset.modelID, "--file", recipe.path], timeout: 600)
    }
}

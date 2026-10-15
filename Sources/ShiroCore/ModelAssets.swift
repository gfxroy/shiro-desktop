import Foundation

public enum ModelFormat: String, Codable, CaseIterable, Identifiable {
    case gguf, liteRT, safetensors, pytorch, onnx, coreML, tflite, ggml, tensorflow, flax, tensorRT, executorch, other
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .gguf: return "GGUF"
        case .liteRT: return "LiteRT-LM"
        case .safetensors: return "Safetensors / Hugging Face / MLX"
        case .pytorch: return "PyTorch checkpoint"
        case .onnx: return "ONNX"
        case .coreML: return "Core ML"
        case .tflite: return "TensorFlow Lite"
        case .ggml: return "Legacy GGML"
        case .tensorflow: return "TensorFlow / Keras"
        case .flax: return "Flax / NumPy weights"
        case .tensorRT: return "TensorRT engine"
        case .executorch: return "ExecuTorch"
        case .other: return "Other / custom runtime"
        }
    }
    public var extensions: String {
        switch self {
        case .gguf: return ".gguf · single or split model folder"
        case .liteRT: return ".litertlm"
        case .safetensors: return ".safetensors · complete model folders (including GPTQ/AWQ/EXL2)"
        case .pytorch: return ".bin · .pt · .pth · .ckpt"
        case .onnx: return ".onnx · ONNX GenAI folders"
        case .coreML: return ".mlmodel · .mlmodelc · .mlpackage"
        case .tflite: return ".tflite · .task"
        case .ggml: return ".ggml · legacy .bin files"
        case .tensorflow: return ".pb · .h5 · .keras · SavedModel folders"
        case .flax: return ".msgpack · .npz · .npy"
        case .tensorRT: return ".engine · .plan"
        case .executorch: return ".pte"
        case .other: return "Any file or model directory via a compatible inference server"
        }
    }
    public var guidance: String {
        switch self {
        case .gguf: return "Import into Ollama. Split models need all shards together."
        case .liteRT: return "Load with Google's LiteRT-LM runtime on this Mac. The original file stays in place."
        case .safetensors: return "Choose the complete model folder, including config and tokenizer. Use MLX for MLX-compatible weights, Ollama for supported architectures, or your existing inference server."
        case .pytorch: return "Requires an architecture-specific Transformers/PyTorch server, configuration, and tokenizer. Shiro does not deserialize pickle checkpoints itself."
        case .onnx: return "Requires an ONNX GenAI runtime/server and the model's tokenizer/configuration. A generic ONNX graph is not necessarily a language model."
        case .coreML: return "Requires a Core ML language-model runtime/server with its tokenizer and generation pipeline."
        case .tflite: return "Raw TFLite graphs and MediaPipe task bundles need their own generation runtime or conversion to a compatible LiteRT-LM bundle."
        case .ggml: return "Use a matching legacy runtime or convert to GGUF with the model's conversion tools."
        case .tensorflow, .flax, .executorch: return "Requires the matching model architecture, tokenizer, and a local inference server, or conversion with the model author's tools. Shiro registers these weights without executing model-provided code."
        case .tensorRT: return "TensorRT engines require a compatible NVIDIA CUDA system. They cannot run natively on this Mac; obtain Mac-compatible weights or convert from the original model."
        case .other: return "Choose an OpenAI-compatible local server that can load this format. Registration alone does not load or convert weights."
        }
    }
    public static func detect(_ url: URL) throws -> ModelFormat {
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else { throw ShiroError("The selected model no longer exists.") }
        let ext = url.pathExtension.lowercased()
        if ["mlpackage", "mlmodelc", "mlmodel"].contains(ext) { return .coreML }
        if directory.boolValue {
            let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            if children.contains(where: { $0.pathExtension.lowercased() == "litertlm" }) { return .liteRT }
            if children.contains(where: { $0.pathExtension.lowercased() == "gguf" }) { return .gguf }
            if children.contains(where: { $0.pathExtension.lowercased() == "safetensors" }) { return .safetensors }
            if children.contains(where: { $0.pathExtension.lowercased() == "onnx" }) { return .onnx }
            if children.contains(where: { ["bin", "pt", "pth", "ckpt"].contains($0.pathExtension.lowercased()) }) { return .pytorch }
            if children.contains(where: { ["pb", "h5", "keras"].contains($0.pathExtension.lowercased()) }) { return .tensorflow }
            if children.contains(where: { ["msgpack", "npz", "npy"].contains($0.pathExtension.lowercased()) }) { return .flax }
            return .other
        }
        switch ext {
        case "gguf":
            try validateHeader(url, signature: Data("GGUF".utf8)); return .gguf
        case "litertlm":
            try validateHeader(url, signature: Data("LITERTLM".utf8)); return .liteRT
        case "safetensors": return .safetensors
        case "bin", "pt", "pth", "ckpt": return .pytorch
        case "onnx": return .onnx
        case "tflite", "task": return .tflite
        case "ggml": return .ggml
        case "pb", "h5", "keras": return .tensorflow
        case "msgpack", "npz", "npy": return .flax
        case "engine", "plan": return .tensorRT
        case "pte": return .executorch
        default: return .other
        }
    }
    public static func validateHeader(_ url: URL, signature: Data) throws {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        guard try file.read(upToCount: signature.count) == signature else { throw ShiroError("The file header does not match .\(url.pathExtension). Renaming a model does not convert its format.") }
    }
}

public enum ModelLoader: String, Codable, CaseIterable, Identifiable {
    case ollama, liteRT, mlx, external
    public var id: String { rawValue }
    public var title: String { switch self { case .ollama: return "Ollama"; case .liteRT: return "LiteRT-LM"; case .mlx: return "MLX LM"; case .external: return "Existing local server" } }
    public var endpoint: String { switch self { case .ollama: return "http://127.0.0.1:11434/v1"; case .liteRT: return "http://127.0.0.1:9379/v1"; case .mlx: return "http://127.0.0.1:8081/v1"; case .external: return "http://127.0.0.1:1234/v1" } }
}

public struct ModelAsset: Codable, Identifiable {
    public var id = UUID()
    public var path: String
    public var format: ModelFormat
    public var loader: ModelLoader
    public var modelID: String
    public var endpoint: String
    public var added = Date()
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    public init(url: URL, format: ModelFormat) {
        self.path = url.standardizedFileURL.path; self.format = format
        self.loader = format == .liteRT ? .liteRT : format == .gguf ? .ollama : format == .safetensors ? .mlx : .external
        self.endpoint = loader.endpoint
        let clean = url.deletingPathExtension().lastPathComponent.lowercased().map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") ? $0 : "-" }
        self.modelID = "shiro-" + String(clean.prefix(60)) + "-" + id.uuidString.prefix(6).lowercased()
    }
}

public final class ModelLibrary {
    public let directory: URL
    public var url: URL { directory.appendingPathComponent("model-library.json") }
    public init(directory: URL? = nil) { self.directory = directory ?? StateStore().directory }
    public func load() throws -> [ModelAsset] {
        if !FileManager.default.fileExists(atPath: url.path) { return [] }
        return try JSONDecoder().decode([ModelAsset].self, from: Data(contentsOf: url)) }
    public func save(_ assets: [ModelAsset]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(assets).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

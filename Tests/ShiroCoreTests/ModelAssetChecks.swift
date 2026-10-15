import Foundation
import ShiroCore

func checkModelAssets() throws {
    let root = checkTemporaryDirectory.appendingPathComponent("shiro-assets-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    func fixture(_ name: String, _ data: String = "weights") throws -> URL {
        let url = root.appendingPathComponent(name); try Data(data.utf8).write(to: url); return url
    }
    let lite = try fixture("gemma4-e4b.litertlm", "LITERTLMfixture")
    try XCTAssertEqual(try ModelFormat.detect(lite), .liteRT)
    try XCTAssertEqual(try ModelFormat.detect(fixture("model.GGUF", "GGUFfixture")), .gguf)
    XCTAssertThrowsError(try ModelFormat.detect(fixture("renamed.litertlm", "GGUF")))
    XCTAssertThrowsError(try ModelFormat.detect(fixture("renamed.gguf")))
    XCTAssertThrowsError(try ModelFormat.detect(root.appendingPathComponent("missing")))
    let formats: [(String, ModelFormat)] = [("safetensors", .safetensors), ("onnx", .onnx), ("mlpackage", .coreML), ("pt", .pytorch), ("task", .tflite), ("ggml", .ggml), ("keras", .tensorflow), ("msgpack", .flax), ("engine", .tensorRT), ("pte", .executorch), ("custom", .other)]
    for (ext, expected) in formats { try XCTAssertEqual(try ModelFormat.detect(fixture("model." + ext)), expected) }
    let folder = root.appendingPathComponent("mlx-folder")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data().write(to: folder.appendingPathComponent("model.safetensors"))
    try XCTAssertEqual(try ModelFormat.detect(folder), .safetensors)
    var asset = ModelAsset(url: lite, format: .liteRT)
    XCTAssertEqual(asset.loader, .liteRT)
    let library = ModelLibrary(directory: root.appendingPathComponent("private"))
    try library.save([asset]); try XCTAssertEqual(try library.load().first?.path, lite.path)
    try XCTAssertEqual(try JSONDecoder().decode(ProviderConfig.self, from: Data(#"{"provider":"local","endpoint":"http://127.0.0.1:1234/v1","model":"old","vision":false}"#.utf8)).localRuntime, nil)
    let runtime = ModelRuntimes(directory: root.appendingPathComponent("private"))
    let registry = try runtime.linkLiteRT(asset)
    let link = registry.appendingPathComponent("models/\(asset.modelID)/model.litertlm")
    XCTAssertEqual(link.resolvingSymlinksInPath().path, lite.path)
    try XCTAssertEqual(try Data(contentsOf: lite), Data("LITERTLMfixture".utf8))
    XCTAssertNoThrow(try runtime.linkLiteRT(asset))
    let config = try JSON.parse(Data(contentsOf: registry.appendingPathComponent("config.json")))
    XCTAssertEqual(config["default"]["cache"].string, "disk")
    let old = JSON.object(["default": .object(["cache": .string("no"), "backend": .string("cpu")]), "custom": .object(["thinking": .bool(true)])])
    try old.data().write(to: registry.appendingPathComponent("config.json"))
    _ = try runtime.linkLiteRT(asset)
    let upgraded = try JSON.parse(Data(contentsOf: registry.appendingPathComponent("config.json")))
    XCTAssertEqual(upgraded["default"]["cache"].string, "disk")
    XCTAssertEqual(upgraded["default"]["backend"].string, "cpu")
    XCTAssertEqual(upgraded["custom"]["thinking"], .bool(true))
    asset.modelID = "../../escape"; XCTAssertThrowsError(try runtime.linkLiteRT(asset))
    print("PASS: format detection, header rejection, model library, old settings, and non-copying LiteRT registration")
}

// Opt-in real-model check. Registers the supplied original in Shiro's library,
// starts the production loader, then sends one local inference request.
func checkRealLiteRT(_ path: String) async throws {
    let url = URL(fileURLWithPath: path), format = try ModelFormat.detect(url)
    guard format == .liteRT else { throw ShiroError("This check needs a .litertlm bundle.") }
    let library = ModelLibrary(); var assets = try library.load()
    let asset = assets.first(where: { $0.path == url.standardizedFileURL.path }) ?? ModelAsset(url: url, format: format)
    if !assets.contains(where: { $0.id == asset.id }) { assets.append(asset); try library.save(assets) }
    let runtime = ModelRuntimes(); try await runtime.launch(asset)
    print("READY: \(asset.modelID) at \(asset.loader.endpoint)")
    let otherOwner = ModelRuntimes(directory: FileManager.default.temporaryDirectory.appendingPathComponent("shiro-other-runtime-owner"))
    do { try await otherOwner.restart(.liteRT); throw ShiroError("Runtime ownership check unexpectedly accepted another owner's process.") }
    catch let error as ShiroError { guard error.message.contains("another application") else { throw error } }
    print("PASS: restart refuses a runtime outside its own managed directory")
    let config = ProviderConfig(provider: .local, endpoint: asset.loader.endpoint, model: asset.modelID, localRuntime: .liteRT)
    let reply = try await ProviderClient().complete(config: config, key: "", system: "Answer briefly. Do not use tools.", history: [ProviderClient.user("Reply with: Shiro local Gemma works.", provider: .local)], tools: [])
    guard !reply.text.isEmpty else { throw ShiroError("The real model returned no text.") }
    print("REAL LOCAL RESPONSE: \(reply.text)")
}

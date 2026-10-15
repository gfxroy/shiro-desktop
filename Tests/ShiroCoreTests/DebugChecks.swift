import Foundation
import ShiroCore

func checkDiagnosticsAndRepair() async throws {
    let root = checkTemporaryDirectory.appendingPathComponent("shiro-debug-checks-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let log = DiagnosticLog(directory: root.appendingPathComponent("logs"), byteLimit: 700)
    let secret = "sk-abcdefghijklmnopqrstuvwxyz123456"
    let event = DiagnosticEvent(level: "error", category: "provider", summary: "failed", detail: "Bearer \(secret) person@example.com \(NSHomeDirectory())/private.txt https://example.com/?token=abc123")
    XCTAssertFalse(event.detail.contains(secret)); XCTAssertFalse(event.detail.contains("person@example.com")); XCTAssertFalse(event.detail.contains(NSHomeDirectory())); XCTAssertFalse(event.detail.contains("abc123"))
    try log.startSession(); try log.append(event)
    for index in 0..<18 { try log.append(DiagnosticEvent(level: "info", category: "run", summary: "event \(index)", detail: String(repeating: "x", count: 300))) }
    let files = try FileManager.default.contentsOfDirectory(at: log.directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "jsonl" }
    XCTAssertTrue(files.count <= 5); XCTAssertTrue(files.count >= 2)
    let attrs = try FileManager.default.attributesOfItem(atPath: log.directory.path)
    XCTAssertEqual((attrs[.posixPermissions] as? Int).map { $0 & 0o777 }, 0o700)
    let history = try log.history(); XCTAssertTrue(history.first?.summary == "event 17")
    let context = try log.context(for: event, provider: ProviderConfig(provider: .local, model: "fixture"))
    XCTAssertTrue(context.contains(event.id.uuidString)); XCTAssertFalse(context.contains(secret))
    try log.startSession(); let interruptedHistory = try log.history(); XCTAssertTrue(interruptedHistory.contains { $0.summary == "Previous session ended unexpectedly" })
    log.endSession(); try log.startSession(); let restartedHistory = try log.history(); XCTAssertEqual(restartedHistory.first?.summary, "App launched"); log.endSession()
    let file = log.directory.appendingPathComponent("events.jsonl"), handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd(); try handle.write(contentsOf: Data("{partial".utf8)); try handle.close()
    let recoveredHistory = try log.history(); XCTAssertTrue(recoveredHistory.contains { $0.summary == "App launched" })
    try log.append(DiagnosticEvent(level: "info", category: "run", summary: "after partial line"))
    let afterPartial = try log.history(); XCTAssertEqual(afterPartial.first?.summary, "after partial line")
    let snapshot = root.appendingPathComponent("snapshot")
    try FileManager.default.createDirectory(at: snapshot.appendingPathComponent("Sources/Shiro"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: snapshot.appendingPathComponent("Sources/ShiroCore"), withIntermediateDirectories: true)
    for (path, text) in ["Package.swift": "immutable package", "Sources/Shiro/ChatView.swift": "unique old text", "Sources/ShiroCore/Persistence.swift": "secret boundary", "Sources/ShiroCore/RepairWorkspace.swift": "protected repair"] { try text.write(to: snapshot.appendingPathComponent(path), atomically: true, encoding: .utf8) }
    let work = try RepairWorkspace(snapshot: snapshot, root: root.appendingPathComponent("cases"))
    XCTAssertFalse(RepairWorkspace.editable("../Sources/Shiro/ChatView.swift")); XCTAssertFalse(RepairWorkspace.editable("Sources/ShiroCore/ProviderClient.swift")); XCTAssertFalse(RepairWorkspace.editable("Sources/Shiro/DebugController.swift"))
    XCTAssertThrowsError(try work.read("../../state.json")); XCTAssertThrowsError(try work.replace("Package.swift", old: "immutable", new: "edited")); XCTAssertThrowsError(try work.replace("Sources/ShiroCore/Persistence.swift", old: "secret", new: "removed"))
    XCTAssertThrowsError(try work.replace("Sources/Shiro/ChatView.swift", old: "not found", new: "replacement"))
    XCTAssertThrowsError(try work.replace("Sources/Shiro/ChatView.swift", old: "unique old text", new: "FileManager.default.removeItem(at: url)"))
    XCTAssertThrowsError(try work.replace("Sources/Shiro/ChatView.swift", old: "unique old text", new: "askBeforeActions = false"))
    XCTAssertThrowsError(try work.replace("Sources/Shiro/ChatView.swift", old: "unique old text", new: "system(\"bad command\")"))
    _ = try work.replace("Sources/Shiro/ChatView.swift", old: "unique old text", new: "Font.system(size: 12)")
    _ = try work.replace("Sources/Shiro/ChatView.swift", old: "Font.system(size: 12)", new: "unique old text")
    XCTAssertTrue(work.changes.isEmpty)
    _ = try work.replace("Sources/Shiro/ChatView.swift", old: "unique old text", new: "small corrected text")
    let unchanged = try String(contentsOf: snapshot.appendingPathComponent("Sources/Shiro/ChatView.swift")); XCTAssertEqual(unchanged, "unique old text")
    XCTAssertEqual(work.changes.count, 1); XCTAssertFalse(work.validated)
    let fingerprint = try work.sourceFingerprint()
    for _ in 0..<8 { let repeated = try work.sourceFingerprint(); XCTAssertEqual(fingerprint, repeated) }
    let patch = try await work.reviewPatch(); XCTAssertTrue(patch.contains("-unique old text")); XCTAssertTrue(patch.contains("+small corrected text"))
    try "tampered".write(to: work.source.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    do { _ = try await work.reviewPatch(); XCTFail("Protected-file tampering accepted") } catch {}
    do { _ = try await work.perform(ToolCall(id: "x", name: "shell", arguments: .object([:]))); XCTFail("Shell repair tool accepted") } catch {}
    if ProcessInfo.processInfo.environment["SHIRO_RESTRICTED_VALIDATION"] != "1" {
    let allowed = try await work.restrictedRun("/bin/echo", ["restricted-ok"], timeout: 15)
    XCTAssertEqual(allowed.status, 0); XCTAssertTrue(allowed.stdout.contains("restricted-ok"))
    let forbidden = try await work.restrictedRun("/bin/cat", [NSHomeDirectory() + "/Library/Application Support/ShiroLocal/state.json"], timeout: 15)
    XCTAssertTrue(forbidden.status != 0); XCTAssertFalse(forbidden.stdout.contains("conversations"))
    let outside = root.appendingPathComponent("forbidden-write.txt")
    let write = try await work.restrictedRun("/usr/bin/touch", [outside.path], timeout: 15)
    XCTAssertTrue(write.status != 0); XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
    let network = try await work.restrictedRun("/usr/bin/curl", ["--max-time", "3", "http://127.0.0.1:9379/v1/models"], timeout: 15)
    XCTAssertTrue(network.status != 0)
    }
    do { _ = try await ProcessRunner.run("/usr/bin/yes", [], timeout: 10, outputLimit: 4096); XCTFail("Unbounded subprocess output accepted") }
    catch { XCTAssertTrue(error.localizedDescription.contains("output exceeded")) }
    print("PASS: persistent redacted logs, rotation, interruption markers, isolated repairs, protected paths, tamper detection and restricted validation boundaries")
}

func checkRealRepairValidation(_ snapshot: String) async throws {
    let work = try RepairWorkspace(snapshot: URL(fileURLWithPath: snapshot))
    _ = try work.replace("Sources/Shiro/ChatView.swift", old: "Progress shows actions and results, not private model reasoning.", new: "Progress shows observed actions and results, not private model reasoning.")
    let result = try await work.validate()
    print(work.checkReport)
    guard result["ok"].bool == true, work.validated else { throw ShiroError("Real restricted repair validation failed. Case: \(work.directory.path)") }
    let patch = try await work.reviewPatch(); XCTAssertTrue(patch.contains("+"))
    print("PASS: restricted native repair build and immutable regression checks. Case: \(work.directory.path)")
}

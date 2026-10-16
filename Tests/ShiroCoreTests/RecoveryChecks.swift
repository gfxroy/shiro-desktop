import Foundation
import ShiroCore

func checkRecovery() throws {
    XCTAssertEqual(ModelServiceError(status: 500, detail: "RuntimeError: INVALID_ARGUMENT: Input token ids are too long. Exceeding the maximum number of tokens allowed: 13033 > 8192").kind, .context)
    XCTAssertEqual(ModelServiceError(status: 400, detail: "The phrase did not match the expected tool format").kind, .format)
    XCTAssertEqual(ModelServiceError(status: 401, detail: "Invalid API key").kind, .terminal)
    let malformed = ToolCall(id: "t", name: "files", arguments: .object(["action": .string("write"), "text": .string("wrong field")]))
    XCTAssertThrowsError(try ToolRecovery.validate(malformed))
    let result = ToolRecovery.feedback(malformed, result: .object(["error": .string("Missing content")]))
    XCTAssertEqual(result["ok"], .bool(false)); XCTAssertTrue(result["recovery"].string!.contains("content")); XCTAssertTrue(result["expected_schema"] != .null)
    XCTAssertTrue(ToolRecovery.failureKey(.init(id: "a", name: "files", arguments: .object(["action": .string("write"), "path": .string("cv.md")]))) != ToolRecovery.failureKey(.init(id: "b", name: "files", arguments: .object(["action": .string("write"), "path": .string("notes.md")]))))
    let blocked = ToolRecovery.feedback(.init(id: "s", name: "search", arguments: .object(["query": .string("jobs")])), result: .object(["blocked": .bool(true), "error": .string("CAPTCHA")]))
    XCTAssertTrue(blocked["recovery"].string!.contains("public careers page")); XCTAssertEqual(blocked["ok"], .bool(false))
    let history: [JSON] = [.object(["role": .string("assistant"), "tool_calls": .array([.object(["id": .string("orphan")])])]), .object(["role": .string("tool"), "content": .string(String(repeating: "long page ", count: 5000))])]
    let compact = ContextBudget.compact(history, task: "Find verified jobs", provider: .local, limit: 6500)
    XCTAssertEqual(compact.count, 1); XCTAssertEqual(compact[0]["role"].string, "user")
    XCTAssertTrue(compact[0]["content"].string!.contains("Find verified jobs")); XCTAssertTrue(compact[0].text.count < 7500)
    XCTAssertEqual(compact[0]["tool_call_id"], .null)
    let image = ProviderClient.user("Latest screen", provider: .local, image: String(repeating: "A", count: 50000))
    XCTAssertTrue(ContextBudget.size([image]) < 1000)
    let visual = ContextBudget.compact(history + [image], task: "Inspect screen", provider: .local, limit: 6500)
    XCTAssertTrue(ContextBudget.hasImage(visual.last!))
    XCTAssertEqual(visual.last!["content"].array.count, 1)
    var evidence = ResearchEvidence()
    let navigation = ToolCall(id: "b", name: "browser", arguments: .object(["action": .string("navigate"), "url": .string("https://example.com/careers")]))
    evidence.observe(call: navigation, result: .object(["ok": .bool(false), "blocked": .bool(true), "url": .string("https://example.com/careers"), "text": .string("CAPTCHA")]))
    XCTAssertTrue(evidence.correction(answer: "I found verified jobs [here](https://example.com/careers).", task: "Find jobs") != nil)
    evidence.observe(call: navigation, result: .object(["ok": .bool(true), "url": .string("https://example.com/careers"), "text": .string("Actual careers page")]))
    XCTAssertEqual(evidence.correction(answer: "Verified [source](https://example.com/careers).", task: "Find jobs"), nil)
    evidence.observe(call: navigation, result: .object(["ok": .bool(true), "url": .string("https://example.com/careers"), "text": .string("Actual page"), "title": .string("3.15.0 Documentation")]))
    XCTAssertTrue(evidence.correction(answer: "3.15. Documentation https://example.com/careers", task: "Report the actual page title")!.contains("3.15.0 Documentation"))
    XCTAssertTrue(evidence.exactPageFacts(task: "Report the actual page title")!.contains("3.15.0 Documentation"))
    XCTAssertTrue(evidence.correction(answer: #"3.15.0 Documentation https:\/\/wrong.example.com\/careers"#, task: "Report the actual page title and exact URL") != nil)
    XCTAssertTrue(evidence.correction(answer: "3.15.0 Documentation", task: "Report the actual page title and exact URL") != nil)
    XCTAssertEqual(evidence.correction(answer: #"3.15.0 Documentation https:\/\/example.com\/careers"#, task: "Report the actual page title and exact URL"), nil)
    var state = SavedState(); state.conversations.append(Conversation())
    var old = try JSON.parse(JSONEncoder().encode(state)).object; old.removeValue(forKey: "bots"); old.removeValue(forKey: "projects")
    let migrated = try JSONDecoder().decode(SavedState.self, from: JSON.object(old).data())
    XCTAssertEqual(migrated.conversations.count, 2); XCTAssertEqual(migrated.bots.count, 1)
    XCTAssertTrue(migrated.conversations.allSatisfy { $0.botID == migrated.bots[0].id })
    var archived = SavedState(); let cv = Entry(role: "user", text: "CV details " + String(repeating: "x", count: 6000)); archived.conversations[0].entries = [cv]
    let recovered = try ChatArchive.read(state: archived, botID: archived.bots[0].id, arguments: .object(["action": .string("read"), "message_id": .string(cv.id.uuidString)]))
    XCTAssertTrue(recovered["content"].string!.hasPrefix("CV details")); XCTAssertTrue(recovered["nextOffset"].number != nil)
    XCTAssertThrowsError(try ChatArchive.read(state: archived, botID: UUID(), arguments: .object(["action": .string("read"), "message_id": .string(cv.id.uuidString)])))
    let split = ToolCall(id: "form", name: "browser_fill", arguments: .object(["selector": .string("#w"), "text": .string("website developer")]))
    let canonical = ToolDefinition.canonical(split)
    XCTAssertEqual(canonical.name, "browser"); XCTAssertEqual(canonical.arguments["action"].string, "fill")
    XCTAssertNoThrow(try ToolRecovery.validate(canonical))
    XCTAssertTrue(ToolDefinition.localBrowser.first { $0.name == "browser_fill" }!.parameters["required"].array.contains(.string("text")))
    let fading = (0..<10).map { ProviderClient.user("MESSAGE-\($0) " + String(repeating: "x", count: 2000), provider: .local) }
    let faded = ContextBudget.compact(fading, task: "PINNED TASK", provider: .local, limit: 8500)[0]["content"].string!
    XCTAssertTrue(faded.contains("PINNED TASK")); XCTAssertTrue(faded.contains("MESSAGE-9")); XCTAssertTrue(faded.count < 9000)
    XCTAssertTrue(RunCheckpoint.continuation(task: "Find ten jobs").contains("Find ten jobs"))
    XCTAssertTrue(RunCheckpoint.promisesWork("I will now fill the input")); XCTAssertFalse(RunCheckpoint.promisesWork("Here are ten jobs."))
    XCTAssertTrue(RunCheckpoint.promisesWork("I will inspect the current state and then I will re-execute the search."))
    XCTAssertTrue(RunCheckpoint.promisesWork("I'll inspect the current page."))
    XCTAssertTrue(RunCheckpoint.promisesWork("I will re-execute the search for WordPress jobs."))
    XCTAssertFalse(RunCheckpoint.promisesWork("I inspected the page and found the results."))
    let focusedTools = RunCheckpoint.recoveryTools(task: "Find ten jobs", provider: .local, corrections: 1)
    XCTAssertEqual(Set(focusedTools.map(\.name)), Set(["search", "context", "memory_search", "memory_read", "browser_open", "browser_read", "files_read"]))
    XCTAssertEqual(RunCheckpoint.recoveryTools(task: "Find ten jobs", provider: .local, corrections: 0).count, ToolDefinition.all.count)
    XCTAssertEqual(RunCheckpoint.recoveryTools(task: "Write a report", provider: .local, corrections: 1).count, ToolDefinition.all.count)
    XCTAssertEqual(RunCheckpoint.recoveryTools(task: "Find ten jobs", provider: .claude, corrections: 1).count, ToolDefinition.all.count)
    var unfinished = Conversation(); unfinished.entries = [Entry(role: "user", text: "find me jobs from this CV, find 10 jibs and give links"), Entry(role: "user", text: "continue"), Entry(role: "user", text: "?"), Entry(role: "user", text: "find the job")]
    for follow in ["continue", "?", "find the job"] { XCTAssertTrue(RunTask.objective(latest: follow, chat: unfinished).contains("10 jibs")) }
    unfinished.activeObjective = "Find ten jobs matching the CV"; unfinished.lastRunOutcome = "blocked"
    XCTAssertEqual(RunTask.objective(latest: "continue", chat: unfinished), "Find ten jobs matching the CV")
    XCTAssertEqual(RunTask.objective(latest: "Now write a README", chat: unfinished), "Now write a README")
    let objective = RunTask.objective(latest: "continue", chat: unfinished)
    XCTAssertTrue(TaskCompletion.missingJobResults(answer: "Skills: WordPress", task: RunTask.prompt(latest: "continue", objective: objective)) != nil)
    unfinished.activeObjective = nil; unfinished.lastRunOutcome = "completed"
    XCTAssertEqual(RunTask.objective(latest: "continue", chat: unfinished), "continue")
    XCTAssertTrue(RunTask.mayClearInterruptedRead(#"search: {"query":"WordPress jobs"}"#))
    XCTAssertEqual(RunTask.recoveredBrowserRead(.object(["url": .string("https://example.com"), "title": .string("Example Domain")]))?["ok"], .bool(true))
    XCTAssertEqual(RunTask.recoveredBrowserRead(.object(["url": .string("https://example.com"), "blocked": .bool(true)])), nil)
    XCTAssertEqual(RunTask.recoveredBrowserRead(.object(["error": .string("Browser unavailable")])), nil)
    XCTAssertFalse(RunTask.mayClearInterruptedRead(#"shell: {"command":"submit"}"#))
    XCTAssertFalse(RunTask.mayClearInterruptedRead(#"browser: {"action":"click","selector":"submit"}"#))
    XCTAssertEqual(ChatFile.safePath("/home/shiro-local/workspace/report.pdf"), "report.pdf")
    XCTAssertEqual(ChatFile.safePath("../escape.pdf"), nil)
    XCTAssertTrue(ChatFile.references(in: "Saved report.pdf").contains { $0.path == "report.pdf" })
    XCTAssertTrue(TaskCompletion.missingJobResults(answer: "CV read successfully. Skills: WordPress", task: "find 10 jibs and give links") != nil)
    XCTAssertEqual(TaskCompletion.missingJobResults(answer: "Done", task: "Write a file"), nil)
    XCTAssertTrue(TaskCompletion.missingJobResults(answer: "CV summary only", task: "find me jobs") != nil)
    XCTAssertTrue(TaskCompletion.disclosedJobShortfall(answer: "I could only verify two openings because other pages require login.", task: "Find ten jobs"))
    XCTAssertEqual(TaskCompletion.missingJobResults(answer: "I could only verify two openings because other pages require login.", task: "Find ten jobs"), nil)
    let selectedFile = ChatFile(path: "attachments/real-uuid/CV.pdf.txt")
    let realCV = ChatFile(path: "attachments/real-uuid/Person_CV.pdf.txt")
    let selection = try ObservationRecovery.parse(#"{"tool":"search","arguments":{"query":"WordPress developer Delhi jobs"}}"#, attachments: [])
    XCTAssertEqual(selection.calls.first?.name, "search")
    XCTAssertEqual(selection.native.first?["tool_calls"].array.first?["id"].string, selection.calls.first?.id)
    let readSelection = try ObservationRecovery.parse("```json\n{\"tool\":\"files_read\",\"arguments\":{\"path\":\"\(realCV.path)\",\"offset\":0}}\n```", attachments: [realCV])
    XCTAssertEqual(ToolDefinition.canonical(readSelection.calls[0]).arguments["path"].string, realCV.path)
    for invalid in [
        #"{"tool":"shell","arguments":{"command":"whoami"}}"#,
        ##"{"tool":"browser_click","arguments":{"selector":"#submit"}}"##,
        #"{"tool":"files_read","arguments":{"path":"secrets.txt","offset":0}}"#,
        #"{"tool":"browser_read","arguments":{"offset":-1}}"#,
        #"{"tool":"browser_read","arguments":{"offset":0.5}}"#,
        #"{"tool":"search","arguments":{"query":""}}"#,
        #"{"tool":"search","arguments":{"query":"jobs","command":"whoami"}}"#,
        #"{"tool":"search","arguments":{"query":"jobs"},"extra":true}"#,
        #"{"blocked":"Needs login"}"#,
        "I will search for jobs.", "[]"
    ] { XCTAssertThrowsError(try ObservationRecovery.parse(invalid, attachments: [realCV])) }
    XCTAssertFalse(RepairWorkspace.editable("Sources/ShiroCore/ObservationRecovery.swift"))
    let cacheRoot = checkTemporaryDirectory.appendingPathComponent("shiro-attachment-cache-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: cacheRoot) }
    let cache = AttachmentCache(root: cacheRoot)
    let cachedFile = ChatFile(path: "attachments/" + UUID().uuidString.lowercased() + "/selected.txt")
    try XCTAssertEqual(try cache.cached(cachedFile), nil)
    try cache.store(Data("Selected attachment".utf8), for: cachedFile)
    let cachedURL = try cache.cached(cachedFile)!
    try XCTAssertEqual(try Data(contentsOf: cachedURL), Data("Selected attachment".utf8))
    let permissions = try FileManager.default.attributesOfItem(atPath: cachedURL.path)[.posixPermissions] as? NSNumber
    XCTAssertEqual(permissions?.intValue, 0o600)
    for unsafe in ["../private.txt", "attachments/not-a-uuid/file.txt", "attachments/" + UUID().uuidString + "/../secret"] {
        XCTAssertThrowsError(try cache.store(Data(), for: ChatFile(path: unsafe)))
    }
    try FileManager.default.removeItem(at: cachedURL)
    try FileManager.default.createSymbolicLink(at: cachedURL, withDestinationURL: cacheRoot.appendingPathComponent("outside.txt"))
    XCTAssertThrowsError(try cache.store(Data(), for: cachedFile))
    XCTAssertThrowsError(try cache.cached(cachedFile))
    let linkedFolder = cacheRoot.appendingPathComponent(UUID().uuidString.lowercased())
    try FileManager.default.createSymbolicLink(at: linkedFolder, withDestinationURL: cacheRoot.deletingLastPathComponent())
    XCTAssertThrowsError(try cache.store(Data(), for: ChatFile(path: "attachments/" + linkedFolder.lastPathComponent + "/outside.txt")))
    XCTAssertFalse(RepairWorkspace.editable("Sources/ShiroCore/AttachmentCache.swift"))
    let failedRead = ToolCall(id: "missing", name: "files", arguments: .object(["action": .string("read"), "path": .string("CV.pdf.txt")]))
    let attachmentHint = AttachmentPaths.feedback(failedRead, result: .object(["error": .string("No such file"), "ok": .bool(false)]), attachments: [realCV, realCV, ChatFile(path: "../private.txt")])
    XCTAssertEqual(attachmentHint["available_attachments"].array, [.string(realCV.path)])
    XCTAssertEqual(attachmentHint["ok"], .bool(false)); XCTAssertTrue(attachmentHint["recovery"].string!.contains("exact registered path"))
    let hintHistory = [ProviderClient.toolResult(failedRead, result: attachmentHint, provider: .local)]
    let compactedHint = ContextBudget.compact(hintHistory, task: "Find ten jobs", provider: .local, limit: 2500)[0]["content"].string!.replacingOccurrences(of: "\\/", with: "/")
    XCTAssertTrue(compactedHint.contains(realCV.path))
    XCTAssertEqual(AttachmentPaths.feedback(failedRead, result: .object(["ok": .bool(true), "content": .string("Read")]), attachments: [realCV])["available_attachments"], .null)
    try XCTAssertEqual(try AttachmentPaths.resolve("attachments/wrong-id/CV.pdf.txt", attachments: [selectedFile]), selectedFile.path)
    try XCTAssertEqual(try AttachmentPaths.resolve("CV.pdf.txt", attachments: [selectedFile]), selectedFile.path)
    try XCTAssertEqual(try AttachmentPaths.resolve("/wrong-folder/CV.pdf.txt", attachments: [selectedFile]), selectedFile.path)
    XCTAssertThrowsError(try AttachmentPaths.resolve("../CV.pdf.txt", attachments: [selectedFile]))
    XCTAssertThrowsError(try AttachmentPaths.resolve("CV.pdf.txt", attachments: [selectedFile, ChatFile(path: "attachments/other/CV.pdf.txt")]))
    var character = Bot(name: "Custom"); character.avatarKind = "orb"; character.avatarEyeSize = 1.2; character.category = "Creative"
    let decodedCharacter = try JSONDecoder().decode(Bot.self, from: JSONEncoder().encode(character))
    XCTAssertEqual(decodedCharacter.avatarFamily, "orb"); XCTAssertEqual(decodedCharacter.avatarEyeSize, 1.2)
    let pageRecord: JSON = .object(["role": .string("tool"), "content": .string(JSON.object(["url": .string("https://example.com/current"), "title": .string("ACTIVE TITLE"), "text": .string(String(repeating: "long body", count: 5000)), "fields": .array([.object(["tag": .string("INPUT"), "selector": .string("#search"), "value": .string("asyncio")])])]).text)])
    let active = ContextBudget.compact([pageRecord], task: "Search", provider: .local, limit: 3000)[0]["content"].string!
    XCTAssertTrue(active.contains("ACTIVE TITLE")); XCTAssertTrue(active.contains("#search")); XCTAssertTrue(active.contains("asyncio"))
    var durable = SavedState(); durable.conversations[0].pendingTask = "Do work"; durable.conversations[0].pendingConfig = ProviderConfig(provider: .local, model: "test")
    durable.conversations[0].entries = [Entry(role: "assistant", text: "File ready")]; durable.conversations[0].entries[0].attachments = [ChatFile(path: "report.pdf")]
    let restored = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(durable))
    XCTAssertEqual(restored.conversations[0].pendingTask, "Do work"); XCTAssertEqual(restored.conversations[0].entries[0].attachments![0].path, "report.pdf")
    print("PASS: model failure classification, schema feedback, blocked-page guidance, context compaction and bot migration")
}

func checkProjectSync() async throws {
    let root = checkTemporaryDirectory.appendingPathComponent("shiro-sync-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source"), output = root.appendingPathComponent("output")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    try Data("new content".utf8).write(to: source.appendingPathComponent("report.md"))
    try Data("secret".utf8).write(to: source.appendingPathComponent(".env"))
    try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("escape"), withDestinationURL: root)
    let tar = root.appendingPathComponent("sync.tar")
    let count = try await ProjectSync.archive(folder: source, destination: tar)
    XCTAssertEqual(count, 1)
    try Data("original".utf8).write(to: output.appendingPathComponent("report.md"))
    try await ProjectSync.restore(archive: tar, folder: output)
    try XCTAssertEqual(String(contentsOf: output.appendingPathComponent("report.md")), "new content")
    XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent(".env").path))
    let backups = try FileManager.default.contentsOfDirectory(at: output.appendingPathComponent(".shiro-backups"), includingPropertiesForKeys: nil)
    try XCTAssertEqual(String(contentsOf: backups[0].appendingPathComponent("report.md")), "original")
    let unsafe = root.appendingPathComponent("unsafe")
    try FileManager.default.createDirectory(at: unsafe, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: unsafe.appendingPathComponent(".shiro-backups"), withDestinationURL: root)
    do { try await ProjectSync.restore(archive: tar, folder: unsafe); XCTFail("Unsafe backup symlink accepted") } catch {}
    print("PASS: project transfer, hidden-file/symlink exclusion, original backups and backup path protection")
}

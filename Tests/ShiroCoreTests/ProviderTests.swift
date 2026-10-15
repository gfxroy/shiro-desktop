import Foundation
import ShiroCore

final class ProviderTests {
    func testOpenAIKeepsReasoningAndMatchesCallID() throws {
        let response = try JSON.parse(#"{"output":[{"type":"reasoning","encrypted_content":"opaque"},{"type":"function_call","call_id":"call_42","name":"search","arguments":"{\"query\":\"local VM\"}"}] ,"status":"completed"}"#)
        let reply = try ProviderClient.parseReply(response, provider: .openAI)
        XCTAssertEqual(reply.calls.count, 1)
        XCTAssertEqual(reply.native[0]["encrypted_content"].string, "opaque")
        let result = ProviderClient.toolResult(reply.calls[0], result: .object(["ok": .bool(true)]), provider: .openAI)
        XCTAssertEqual(result["call_id"].string, "call_42")
        XCTAssertEqual(reply.calls[0].arguments["query"].string, "local VM")
    }
    func testClaudeCombinesParallelToolResultsIntoOneTurn() throws {
        let response = try JSON.parse(#"{"content":[{"type":"text","text":"Looking into it"},{"type":"tool_use","id":"a","name":"search","input":{"query":"one"}},{"type":"tool_use","id":"b","name":"search","input":{"query":"two"}}],"stop_reason":"tool_use"}"#)
        let reply = try ProviderClient.parseReply(response, provider: .claude)
        let results = reply.calls.map { ProviderClient.toolResult($0, result: .object(["ok": .bool(true)]), provider: .claude) }
        let history = ProviderClient.mergeClaude(reply.native + results)
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[1]["content"].array.count, 2)
        XCTAssertEqual(history[1]["content"].array[1]["tool_use_id"].string, "b")
    }
    func testGeminiPreservesThoughtSignature() throws {
        let response = try JSON.parse(#"{"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"id":"native_123","name":"browser","args":{"action":"read"}},"thoughtSignature":"do-not-drop-me"}]},"finishReason":"STOP"}]}"#)
        let reply = try ProviderClient.parseReply(response, provider: .gemini)
        XCTAssertEqual(reply.native[0]["parts"].array[0]["thoughtSignature"].string, "do-not-drop-me")
        XCTAssertEqual(reply.calls[0].arguments["action"].string, "read")
        let result = ProviderClient.toolResult(reply.calls[0], result: .object(["ok": .bool(true)]), provider: .gemini)
        XCTAssertEqual(result["parts"].array[0]["functionResponse"]["id"].string, "native_123")
        let merged = ProviderClient.mergeGemini(reply.native + [result, result])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[1]["parts"].array.count, 2)
    }
    func testLocalToolArgumentsAreParsedAndUnknownMetadataIsDropped() throws {
        let response = try JSON.parse(#"{"choices":[{"message":{"role":"assistant","content":null,"thinking":"private","tool_calls":[{"id":"t","type":"function","function":{"name":"files","arguments":"{\"action\":\"list\"}"}}]},"finish_reason":"tool_calls"}]}"#)
        let reply = try ProviderClient.parseReply(response, provider: .local)
        XCTAssertEqual(reply.calls[0].arguments["action"].string, "list")
        XCTAssertEqual(reply.native[0]["thinking"], .null)
    }
    func testMalformedToolArgumentsAreRejected() throws {
        let response = try JSON.parse(#"{"output":[{"type":"function_call","call_id":"x","name":"shell","arguments":"not JSON"}],"status":"completed"}"#)
        XCTAssertThrowsError(try ProviderClient.parseReply(response, provider: .openAI))
    }
    func testProviderErrorsDoNotBecomeSuccessfulReplies() throws {
        let incomplete = try JSON.parse(#"{"status":"incomplete","output":[{"type":"message","content":[{"type":"output_text","text":"partial"}]}]}"#)
        XCTAssertThrowsError(try ProviderClient.parseReply(incomplete, provider: .openAI))
        XCTAssertThrowsError(try ProviderClient.parseReply(.object([:]), provider: .gemini))
        XCTAssertThrowsError(try ProviderClient.parseReply(.object([:]), provider: .local))
    }
    func testScreenshotShapesForEveryProvider() {
        for provider in Provider.allCases {
            let user = ProviderClient.user("Observe", provider: provider, image: "abc")
            XCTAssertTrue(user.text.contains("abc"))
            XCTAssertEqual(user["role"].string, "user")
        }
    }
    func testOfficialCloudAndLoopbackEndpointBoundaries() throws {
        XCTAssertNoThrow(try ProviderClient.baseURL(.init(provider: .openAI)))
        XCTAssertNoThrow(try ProviderClient.baseURL(.init(provider: .local, endpoint: "http://127.0.0.1:1234/v1")))
        XCTAssertThrowsError(try ProviderClient.baseURL(.init(provider: .openAI, endpoint: "https://evil.example/v1")))
        XCTAssertThrowsError(try ProviderClient.baseURL(.init(provider: .claude, endpoint: "http://api.anthropic.com/v1")))
        XCTAssertThrowsError(try ProviderClient.baseURL(.init(provider: .local, endpoint: "http://192.168.1.2:11434/v1")))
        XCTAssertThrowsError(try ProviderClient.baseURL(.init(provider: .local, endpoint: "http://user:pass@localhost/v1")))
    }
    func testExactActionsNeedApproval() {
        XCTAssertTrue(ToolCall(id: "1", name: "shell", arguments: .object([:])).needsApproval)
        XCTAssertTrue(ToolCall(id: "2", name: "browser", arguments: .object(["action": .string("click")])).needsApproval)
        XCTAssertFalse(ToolCall(id: "3", name: "browser", arguments: .object(["action": .string("read")])).needsApproval)
        XCTAssertFalse(ToolCall(id: "4", name: "computer", arguments: .object(["action": .string("screenshot")])).needsApproval)
    }
    func testVMNameDoesNotAcceptOptionsOrShellSyntax() {
        let vm = VirtualMachine()
        XCTAssertNoThrow(try vm.validate("shiro-local"))
        XCTAssertThrowsError(try vm.validate("--help"))
        XCTAssertThrowsError(try vm.validate("$(touch /tmp/x)"))
        XCTAssertThrowsError(try vm.validate("../other"))
    }
    func testPersistenceRoundTripAndCorruptionPreserved() throws {
        let folder = checkTemporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = StateStore(directory: folder)
        var state = SavedState(); state.memory = "Prefer primary sources"; state.routines = [Routine(title: "Research", prompt: "Read papers", minutes: 60)]
        state.conversations[0].entries.append(Entry(role: "user", text: "Remember me"))
        try store.save(state)
        let loaded = try store.load()
        XCTAssertEqual(loaded.memory, state.memory)
        XCTAssertEqual(loaded.routines.count, 1)
        XCTAssertEqual(loaded.conversations[0].entries[0].text, "Remember me")
        let permissions = try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        try Data("corrupted".utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load())
        let preserved = try String(contentsOf: store.url)
        XCTAssertEqual(preserved, "corrupted")
    }
    func testProcessRunnerCapturesStreamsAndExitStatus() async throws {
        let result = try await ProcessRunner.run("/bin/sh", ["-c", "printf 'hello'; printf 'problem' >&2; exit 7"])
        XCTAssertEqual(result.stdout, "hello"); XCTAssertEqual(result.stderr, "problem"); XCTAssertEqual(result.status, 7)
    }
    func testProcessRunnerTimeout() async {
        do { _ = try await ProcessRunner.run("/bin/sleep", ["10"], timeout: 0.1); XCTFail("Expected timeout") }
        catch { XCTAssertTrue(error.localizedDescription.contains("stopped")) }
    }
}

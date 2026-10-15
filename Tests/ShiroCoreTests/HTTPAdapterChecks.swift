import Foundation
import ShiroCore

final class FixtureProtocol: URLProtocol {
    static var response = JSON.null
    static var lastRequest: URLRequest?
    static var stream: String?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": Self.stream == nil ? "application/json" : "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.stream.map { Data($0.utf8) } ?? (try? Self.response.data()) ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

func checkHTTPAdapters() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FixtureProtocol.self]
    let client = ProviderClient(session: URLSession(configuration: config))
    let fixtures: [(Provider, String, String)] = [
        (.openAI, #"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"ok"}]}]}"#, "/v1/responses"),
        (.claude, #"{"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn"}"#, "/v1/messages"),
        (.gemini, #"{"candidates":[{"content":{"role":"model","parts":[{"text":"ok"}]},"finishReason":"STOP"}]}"#, "/v1beta/models/test-model:generateContent"),
        (.local, #"{"choices":[{"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}]}"#, "/v1/chat/completions")
    ]
    for (provider, fixture, path) in fixtures {
        FixtureProtocol.response = try JSON.parse(fixture)
        let result = try await client.complete(config: .init(provider: provider, model: "test-model"), key: provider == .local ? "" : "fake-test-key", system: "Test harness", history: [ProviderClient.user("Hello", provider: provider)])
        XCTAssertEqual(result.text, "ok")
        XCTAssertEqual(FixtureProtocol.lastRequest?.url?.path, path)
        XCTAssertEqual(FixtureProtocol.lastRequest?.httpMethod, "POST")
        if provider == .claude { XCTAssertEqual(FixtureProtocol.lastRequest?.value(forHTTPHeaderField: "x-api-key"), "fake-test-key") }
        if provider == .gemini { XCTAssertEqual(FixtureProtocol.lastRequest?.value(forHTTPHeaderField: "x-goog-api-key"), "fake-test-key") }
        if provider == .openAI { XCTAssertEqual(FixtureProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer fake-test-key") }
    }
    print("PASS: HTTP request/response adapters for all four providers (fixtures, no paid calls)")
    FixtureProtocol.response = try JSON.parse(fixtures[3].1)
    _ = try await client.complete(config: .init(provider: .local, model: "gemma", localRuntime: .liteRT), key: "", system: "test", history: [], tools: [])
    let request = FixtureProtocol.lastRequest!
    let requestData = request.httpBody ?? request.httpBodyStream.map { stream -> Data in
        stream.open(); defer { stream.close() }
        var data = Data(), bytes = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable { let count = stream.read(&bytes, maxLength: bytes.count); if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count)) }
        return data
    } ?? Data()
    let body = try JSON.parse(requestData)
    XCTAssertEqual(body["max_completion_tokens"], .number(1536))
    XCTAssertEqual(body["max_tokens"], .null)
    XCTAssertEqual(body["tools"], .null)
    XCTAssertEqual(body["stream"], .bool(true))
    print("PASS: LiteRT token parameter and plain-chat request format")
    FixtureProtocol.response = .object(["choices": .array([.object(["message": .object(["role": .string("assistant"), "content": .string(#"{"tool":"search","arguments":{"query":"WordPress developer jobs Delhi"}}"#)]), "finish_reason": .string("stop")])])])
    let recovered = try await client.recoverObservation(config: .init(provider: .local, model: "gemma", localRuntime: .liteRT), task: "Find ten jobs", history: [ProviderClient.user("Actual page data: search results", provider: .local)], attachments: [])
    XCTAssertEqual(recovered.calls.first?.name, "search")
    XCTAssertEqual(recovered.native[0]["tool_calls"].array[0]["id"].string, recovered.calls.first?.id)
    let result = ProviderClient.toolResult(recovered.calls[0], result: .object(["ok": .bool(true)]), provider: .local)
    XCTAssertEqual(result["tool_call_id"].string, recovered.calls[0].id)
    do {
        _ = try await client.recoverObservation(config: .init(provider: .claude, model: "test"), task: "Find jobs", history: [], attachments: [])
        XCTFail("Observation recovery must not call a cloud provider")
    } catch {}
    print("PASS: structured local recovery and native tool-result transaction")
    FixtureProtocol.stream = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\" world\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
    defer { FixtureProtocol.stream = nil }
    let streamed = try await client.complete(config: .init(provider: .local, model: "fixture"), key: "", system: "test", history: [], tools: [])
    XCTAssertEqual(streamed.text, "Hello world")
    var accumulator = LocalCompletionStream()
    let fragments = [
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call-1","function":{"name":"files_read","arguments":"{\"pa"}}]},"finish_reason":null}]}"#,
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"th\":\"x.txt\"}"}}]},"finish_reason":null}]}"#
    ]
    for fragment in fragments { _ = try accumulator.consume(fragment) }
    XCTAssertThrowsError(try accumulator.response()) // Never act on truncated tools.
    _ = try accumulator.consume(#"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#)
    let assembled = try ProviderClient.parseReply(accumulator.response(), provider: .local)
    XCTAssertEqual(assembled.calls.first?.name, "files_read")
    XCTAssertEqual(assembled.calls.first?.arguments["path"].string, "x.txt")
    var empty = LocalCompletionStream()
    _ = try empty.consume(#"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#)
    XCTAssertThrowsError(try empty.response())
    var limited = LocalCompletionStream()
    _ = try limited.consume(#"data: {"choices":[{"delta":{"content":"unfinished"},"finish_reason":"length"}]}"#)
    XCTAssertThrowsError(try ProviderClient.parseReply(limited.response(), provider: .local))
    print("PASS: streamed HTTP replies, fragmented tools, empty/truncated streams and output limits")
}

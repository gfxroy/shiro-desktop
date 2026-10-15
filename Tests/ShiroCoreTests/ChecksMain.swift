import Foundation

// This machine has Command Line Tools rather than Xcode/XCTest. Keep the checks
// runnable with the standard Swift toolchain, without a test-library dependency.
var failures: [String] = []
// Confine fixtures during the app's restricted repair validation; assertions are unchanged.
var checkTemporaryDirectory: URL {
    if let path = ProcessInfo.processInfo.environment["SHIRO_CHECKS_TMPDIR"] { return URL(fileURLWithPath: path) }
    return FileManager.default.temporaryDirectory
}
func XCTFail(_ message: String) { failures.append(message) }
func XCTAssertTrue(_ value: @autoclosure () -> Bool) { if !value() { XCTFail("Expected true") } }
func XCTAssertFalse(_ value: @autoclosure () -> Bool) { if value() { XCTFail("Expected false") } }
func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T) rethrows {
    let first = try a(), second = try b()
    if first != second { XCTFail("Expected \(first) to equal \(second)") }
}
func XCTAssertNoThrow<T>(_ value: @autoclosure () throws -> T) { do { _ = try value() } catch { XCTFail("Unexpected error: \(error)") } }
func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T) { do { _ = try value(); XCTFail("Expected an error") } catch {} }

@main struct ChecksMain {
    static func main() async {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--repair-check" {
            do { try await checkRealRepairValidation(CommandLine.arguments[2]) } catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
            return
        }
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--litert" {
            do { try await checkRealLiteRT(CommandLine.arguments[2]) } catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
            return
        }
        let suite = ProviderTests()
        let checks: [(String, () throws -> Void)] = [
            ("OpenAI reasoning and call IDs", suite.testOpenAIKeepsReasoningAndMatchesCallID),
            ("Claude parallel tool results", suite.testClaudeCombinesParallelToolResultsIntoOneTurn),
            ("Gemini thought signatures", suite.testGeminiPreservesThoughtSignature),
            ("Local tool format", suite.testLocalToolArgumentsAreParsedAndUnknownMetadataIsDropped),
            ("Malformed tool rejection", suite.testMalformedToolArgumentsAreRejected),
            ("Provider failure handling", suite.testProviderErrorsDoNotBecomeSuccessfulReplies),
            ("Screenshot message formats", suite.testScreenshotShapesForEveryProvider),
            ("Endpoint boundaries", suite.testOfficialCloudAndLoopbackEndpointBoundaries),
            ("Action approvals", suite.testExactActionsNeedApproval),
            ("VM name validation", suite.testVMNameDoesNotAcceptOptionsOrShellSyntax),
            ("Persistent state and corruption", suite.testPersistenceRoundTripAndCorruptionPreserved)
        ]
        for (name, check) in checks {
            let before = failures.count
            do { try check() } catch { XCTFail("\(name): \(error)") }
            print("\(before == failures.count ? "PASS" : "FAIL"): \(name)")
        }
        do { try await suite.testProcessRunnerCapturesStreamsAndExitStatus() } catch { XCTFail(error.localizedDescription) }
        await suite.testProcessRunnerTimeout()
        do { try await checkHTTPAdapters() } catch { XCTFail(error.localizedDescription) }
        do { try checkModelAssets() } catch { XCTFail(error.localizedDescription) }
        do { try checkRecovery(); try await checkProjectSync() } catch { XCTFail(error.localizedDescription) }
        do { try await checkDiagnosticsAndRepair() } catch { XCTFail(error.localizedDescription) }
        if !failures.isEmpty { for failure in failures { print("FAIL: \(failure)") }; exit(1) }
        print("22 check groups passed.")
    }
}

import AppKit
import SwiftUI
import ShiroCore

struct RepairRecord: Codable, Identifiable {
    var id: UUID
    var date: Date
    var status: String
    var summary: String
    var directory: String
}

@MainActor final class DebugController: ObservableObject {
    let log = DiagnosticLog()
    @Published var events: [DiagnosticEvent] = []
    @Published var records: [RepairRecord] = []
    @Published var selected: DiagnosticEvent?
    @Published var description = ""
    @Published var context = ""
    @Published var busy = false
    @Published var status = "Choose an incident or describe an app problem."
    @Published var response = ""
    @Published var patch = ""
    @Published var checks = ""
    @Published var steps: [String] = []
    @Published var candidate: URL?
    @Published var failure: String?
    @Published var confirmApply = false
    @Published var restoreRecord: RepairRecord?
    private var workspace: RepairWorkspace?
    private var task: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?
    private var panels: [NSSavePanel] = []
    private var baseDigest: String?
    private var candidateDigest: String?
    init() {
        do { try log.startSession() } catch { failure = "Diagnostic log unavailable: \(error.localizedDescription)" }
        reload()
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [log] _ in log.endSession() }
        loadRecords()
    }
    func capture(level: String = "info", category: String, summary: String, detail: String = "", chat: UUID? = nil, config: ProviderConfig? = nil) {
        let event = DiagnosticEvent(level: level, category: category, summary: summary, detail: detail, chatID: chat, provider: config?.provider.rawValue, model: config?.model)
        do { try log.append(event); events.insert(event, at: 0); if events.count > 20000 { events.removeLast(events.count - 20000) } }
        catch { failure = "Diagnostic logging failed: \(error.localizedDescription)" }
    }
    func reload() { do { events = try log.history() } catch { failure = error.localizedDescription } }
    func prepare(_ event: DiagnosticEvent?, config: ProviderConfig) {
        guard !busy else { return }
        selected = event; description = event.map { "Investigate this incident: \($0.summary)\n\($0.detail)" } ?? ""
        do { context = try log.context(for: event, provider: config) } catch { failure = error.localizedDescription }
    }
    func importLegacyFailures(_ chats: [Conversation]) {
        let marker = log.directory.appendingPathComponent("imported-chat-errors-v1")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        do {
            for chat in chats {
                for entry in chat.entries.suffix(150) where entry.role == "tool" {
                    guard let colon = entry.text.firstIndex(of: ":"), let result = try? JSON.parse(String(entry.text[entry.text.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)), let error = result["error"].string else { continue }
                    var event = DiagnosticEvent(level: "error", category: "legacy-tool", summary: String(entry.text[..<colon]) + " failed", detail: error, chatID: chat.id)
                    event.date = entry.date; try log.append(event)
                }
            }
            try Data("imported".utf8).write(to: marker, options: .atomic); reload()
        } catch { failure = "Could not import earlier error metadata: \(error.localizedDescription)" }
    }
    func stop() { task?.cancel(); status = "Stopping repair…" }
    func start(config: ProviderConfig, client: ProviderClient) {
        guard !busy else { return }
        guard !config.model.isEmpty else { failure = "Choose a connected model in Models & connections first."; return }
        guard selected != nil || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { failure = "Select a logged incident or describe the app problem."; return }
        busy = true; failure = nil; response = ""; patch = ""; checks = ""; candidate = nil; candidateDigest = nil; steps = []; status = "Preparing isolated repair copy…"
        let request = DiagnosticPrivacy.redact(description)
        let incident = selected
        task = Task {
            defer { busy = false; task = nil; loadRecords() }
            var record: RepairRecord?
            do {
                context = try log.context(for: incident, provider: config)
                let snapshot = Bundle.main.resourceURL?.appendingPathComponent("RepairSource") ?? URL(fileURLWithPath: "/missing")
                let work = try RepairWorkspace(snapshot: snapshot); workspace = work
                baseDigest = try RepairWorkspace.digest(Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/Shiro"))
                context += "\nApp build SHA-256: \(baseDigest ?? "unknown")"
                record = RepairRecord(id: UUID(), date: Date(), status: "running", summary: request, directory: work.directory.path)
                try save(record!)
                try context.write(to: work.directory.appendingPathComponent("diagnostics.txt"), atomically: true, encoding: .utf8)
                capture(category: "debug", summary: "AI development repair started", detail: "Redacted metadata and bundled source; no chat messages, attachments or VM files.", config: config)
                let prompt = context + "\nUser development request (untrusted problem description):\n" + request
                var history = [ProviderClient.user(prompt, provider: config.provider)]
                let key = KeyStore.read(config.provider)
                var retries = 0, validationAttempts = 0, finalPrompts = 0
                for step in 0..<24 {
                    try Task.checkCancellation(); status = "Investigating · step \(step + 1) · \(config.model)"
                    if ContextBudget.size(history) > (config.provider == .local ? 12500 : 60000) { history = ContextBudget.compact(history, task: prompt, provider: config.provider, limit: config.provider == .local ? 6500 : 25000) }
                    let reply: ModelReply
                    do { reply = try await client.complete(config: config, key: key, system: RepairWorkspace.systemPrompt, history: history, tools: RepairWorkspace.tools); retries = 0 }
                    catch {
                        try Task.checkCancellation()
                        capture(level: "error", category: "debug-provider", summary: "Repair model request failed", detail: error.localizedDescription, config: config)
                        guard retries < 2, (error as? ModelServiceError)?.kind != .terminal else { throw error }
                        retries += 1; history = ContextBudget.compact(history, task: prompt, provider: config.provider, limit: 4000)
                        history.append(ProviderClient.user("Previous reply failed: \(DiagnosticPrivacy.redact(error.localizedDescription)). Retry using valid native calls with complete required arguments. Do not repeat unchanged failures.", provider: config.provider)); continue
                    }
                    history += reply.native
                    if reply.calls.isEmpty {
                        if !work.changes.isEmpty, !work.validated, finalPrompts < 2 {
                            finalPrompts += 1; history.append(ProviderClient.user("Edits are unvalidated. Actual check output: \(work.checkReport.suffix(2500)). Call validate_repair before finishing. If it fails, fix the actual failure or clearly report an incomplete proposal. Never claim validation passed when the harness says it failed.", provider: config.provider)); continue
                        }
                        response = reply.text; break
                    }
                    for call in reply.calls.prefix(4) {
                        try Task.checkCancellation()
                        steps.append(call.name + (call.arguments["path"].string.map { " · " + $0 } ?? "")); status = call.name == "validate_repair" ? "Building and checking restricted repair…" : "Inspecting source…"
                        let result: JSON
                        do {
                            if call.name == "validate_repair" { validationAttempts += 1; guard validationAttempts <= 3 else { throw ShiroError("Validation attempt limit reached. Return the incomplete diagnosis; do not bypass checks.") } }
                            result = try await work.perform(call)
                        } catch { result = .object(["error": .string(DiagnosticPrivacy.redact(error.localizedDescription)), "expected_tools": .string(RepairWorkspace.tools.map { "\($0.name): \($0.parameters.text)" }.joined(separator: "\n"))]) }
                        checks = work.checkReport
                        history.append(ProviderClient.toolResult(call, result: result, provider: config.provider))
                        capture(level: result["error"].string != nil || result["ok"].bool == false ? "warning" : "info", category: "debug-tool", summary: call.name, detail: result["error"].string ?? (result["ok"].bool == false ? "Validation did not pass." : "Completed"), config: config)
                    }
                    for call in reply.calls.dropFirst(4) { history.append(ProviderClient.toolResult(call, result: .object(["error": .string("At most four repair calls per response. Retry remaining work.")]), provider: config.provider)) }
                }
                try Task.checkCancellation()
                if response.isEmpty { response = "The repair investigation reached its 24-step budget. Review the source changes and checks below. No running app was changed." }
                patch = try await work.reviewPatch(); checks = work.checkReport
                if work.validated, !work.changes.isEmpty {
                    candidate = try await work.makeCandidate(from: Bundle.main.bundleURL)
                    candidateDigest = try RepairWorkspace.digest(candidate!.appendingPathComponent("Contents/MacOS/Shiro"))
                    status = "Checks passed · review before applying"
                } else { status = work.changes.isEmpty ? "Diagnosis ready · no app changes" : "Proposal incomplete · apply disabled" }
                record?.status = status; record?.summary = response
                try response.write(to: work.directory.appendingPathComponent("diagnosis.md"), atomically: true, encoding: .utf8)
                if let record { try save(record) }
                capture(category: "debug", summary: status, detail: "Repair history saved locally.", config: config)
            } catch {
                status = Task.isCancelled ? "Repair stopped · running app unchanged" : "Repair needs attention"
                failure = Task.isCancelled ? nil : DiagnosticPrivacy.redact(error.localizedDescription)
                if let work = workspace { patch = (try? await work.reviewPatch()) ?? ""; checks = work.checkReport }
                if var saved = record { saved.status = status; saved.summary = failure ?? status; try? save(saved) }
                capture(level: "warning", category: "debug", summary: status, detail: failure ?? "User stopped the investigation.", config: config)
            }
        }
    }
    private func save(_ record: RepairRecord) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted]
        try encoder.encode(record).write(to: URL(fileURLWithPath: record.directory).appendingPathComponent("repair.json"), options: .atomic)
    }
    private func loadRecords() {
        let root = StateStore().directory.appendingPathComponent("Repairs")
        let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        records = urls.compactMap { try? JSONDecoder().decode(RepairRecord.self, from: Data(contentsOf: $0.appendingPathComponent("repair.json"))) }.sorted { $0.date > $1.date }
        records = Array(records.prefix(30))
    }
    func exportLogs() {
        let text = events.map { "\($0.date.formatted(.iso8601)) [\($0.level)] \($0.category) · \($0.summary)\n\($0.detail)" }.joined(separator: "\n\n")
        export(text, name: "shiro-diagnostics.txt")
    }
    func exportRepair() { export("\(response)\n\n\(checks)\n\n\(patch)", name: "shiro-repair-review.txt") }
    private func export(_ text: String, name: String) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = name; panels.append(panel)
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] result in
            guard let self, let panel else { return }
            defer { self.panels.removeAll { $0 === panel } }
            if result == .OK, let url = panel.url { do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { self.failure = error.localizedDescription } }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) } else { panel.begin(completionHandler: completion) }
    }
    func showHistory(_ record: RepairRecord) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.directory)]) }
    func hasBackup(_ record: RepairRecord) -> Bool { FileManager.default.fileExists(atPath: URL(fileURLWithPath: record.directory).appendingPathComponent("LastGood-Shiro.app").path) }
    func restore() {
        guard let record = restoreRecord, !busy else { return }
        restoreRecord = nil
        Task {
            do {
                let directory = URL(fileURLWithPath: record.directory).resolvingSymlinksInPath(), root = StateStore().directory.appendingPathComponent("Repairs").resolvingSymlinksInPath()
                guard Bundle.main.bundleURL.path == "/Applications/Shiro.app", directory.deletingLastPathComponent().path == root.path, UUID(uuidString: directory.lastPathComponent) != nil else { throw ShiroError("Invalid restore record.") }
                let backup = directory.appendingPathComponent("LastGood-Shiro.app")
                _ = try await ProcessRunner.checked("/usr/bin/codesign", ["--verify", "--strict", backup.path])
                try await scheduleRestart(with: backup, in: directory)
                capture(category: "debug-install", summary: "Previous app restore scheduled")
                NSApp.terminate(nil)
            } catch { failure = error.localizedDescription }
        }
    }
    private func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private func scheduleRestart(with app: URL, in directory: URL) async throws {
        let helper = directory.appendingPathComponent("apply-repair.sh"), stage = "/Applications/.Shiro-repair-\(UUID().uuidString).app", previous = "/Applications/.Shiro-previous-\(UUID().uuidString).app"
        let script = """
        #!/bin/sh
        set -eu
        while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do /bin/sleep 1; done
        /usr/bin/ditto \(quote(app.path)) \(quote(stage))
        /usr/bin/codesign --verify --strict \(quote(stage))
        /bin/mv /Applications/Shiro.app \(quote(previous))
        if /bin/mv \(quote(stage)) /Applications/Shiro.app; then
            /usr/bin/open /Applications/Shiro.app
        else
            /bin/mv \(quote(previous)) /Applications/Shiro.app
            exit 1
        fi
        """
        try script.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/sh"); process.arguments = [helper.path]
        let output = directory.appendingPathComponent("install.log")
        FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: output); process.standardOutput = handle; process.standardError = handle
        try process.run()
    }
    func apply() {
        guard !busy, let candidate, let work = workspace, let candidateDigest else { return }
        Task {
            do {
                guard Bundle.main.bundleURL.path == "/Applications/Shiro.app", baseDigest == (try RepairWorkspace.digest(Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/Shiro"))), candidateDigest == (try RepairWorkspace.digest(candidate.appendingPathComponent("Contents/MacOS/Shiro"))) else { throw ShiroError("App or candidate changed since review. Run the repair again. Apply is supported only for /Applications/Shiro.app.") }
                _ = try await ProcessRunner.checked("/usr/bin/codesign", ["--verify", "--strict", candidate.path])
                let backup = work.directory.appendingPathComponent("LastGood-Shiro.app")
                if !FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.copyItem(at: Bundle.main.bundleURL, to: backup) }
                // Helper is created by trusted host code after validation; the AI cannot call this API.
                let restore = work.directory.appendingPathComponent("Restore Shiro.command")
                let restoreText = "#!/bin/sh\nset -eu\n/usr/bin/ditto \(quote(backup.path)) /Applications/Shiro.app\n/usr/bin/codesign --verify --strict /Applications/Shiro.app\n/usr/bin/open /Applications/Shiro.app\n"
                try restoreText.write(to: restore, atomically: true, encoding: .utf8); try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: restore.path)
                try await scheduleRestart(with: candidate, in: work.directory)
                if var record = records.first(where: { $0.directory == work.directory.path }) { record.status = "Reviewed repair applied · restart requested"; try save(record) }
                capture(category: "debug-install", summary: "Reviewed repair scheduled for restart", detail: "Last good app and Restore Shiro.command saved in repair history.")
                NSApp.terminate(nil)
            } catch { failure = error.localizedDescription }
        }
    }
}

import SwiftUI
import ShiroCore

struct DebugView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var debug: DebugController
    @State private var search = ""
    @State private var errorsOnly = true
    @State private var showContext = false
    @State private var visibleLimit = 100
    private var filtered: [DiagnosticEvent] { debug.events.filter { (!errorsOnly || $0.level != "info") && (search.isEmpty || ($0.summary + $0.detail + $0.category).localizedCaseInsensitiveContains(search)) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeading(eyebrow: "Developer tools", title: "Debug & repair", subtitle: "Local history, useful context, and carefully reviewed repairs.")
                Card { VStack(alignment: .leading, spacing: 14) {
                    Label("AI development request", systemImage: "wrench.and.screwdriver").font(.system(size: 20, weight: .medium))
                    Text("Uses your selected \(store.config.provider.title) model: \(store.config.model). Sends redacted diagnostic metadata and relevant source. Chats, CVs, screenshots, credentials and VM files are excluded. Cloud models receive this development context when you click Debug with AI.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    if let selected = debug.selected { HStack { Text(selected.summary).font(.system(size: 13, weight: .medium)); Spacer(); Button("Clear incident") { debug.prepare(nil, config: store.config) }.disabled(debug.busy) } }
                    TextEditor(text: $debug.description).font(.system(size: 12)).frame(height: 85).padding(8).background(Palette.surface, in: RoundedRectangle(cornerRadius: 10)).disabled(debug.busy).accessibilityLabel("Describe the app problem")
                    HStack {
                        Button("Debug with AI") { debug.start(config: store.config, client: store.client) }.buttonStyle(.borderedProminent).disabled(debug.busy || store.running || store.modelBusy)
                        if debug.busy { ProgressView().controlSize(.small); Button("Stop repair") { debug.stop() } }
                        Spacer(); Button("Models & connections") { store.page = .models }
                    }
                    Text("The AI edits a separate source copy. Fixed checks run with restricted file access and no network. Protected code and tests cannot be edited. Applying a checked repair requires your review; the previous app is backed up.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    if store.running { Text("Finish or stop the bot task before starting a repair.").font(.system(size: 11)).foregroundStyle(.orange) }
                    DisclosureGroup("Context sent to the model", isExpanded: $showContext) { Text(debug.context.isEmpty ? "Select an incident; a redacted report is prepared automatically." : debug.context).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                } }
                if debug.busy || !debug.response.isEmpty || !debug.patch.isEmpty || debug.failure != nil {
                    Card { VStack(alignment: .leading, spacing: 12) {
                        Text(debug.status).font(.system(size: 16, weight: .medium))
                        if let failure = debug.failure { Text(failure).font(.system(size: 12)).foregroundStyle(.red).textSelection(.enabled) }
                        if !debug.steps.isEmpty { DisclosureGroup("Investigation · \(debug.steps.count) actions") { ForEach(Array(debug.steps.enumerated()), id: \.offset) { _, step in Text(step).font(.system(size: 10, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading) } } }
                        if !debug.response.isEmpty { Text(debug.response).font(.system(size: 13)).textSelection(.enabled) }
                        if !debug.patch.isEmpty { DisclosureGroup("Review source patch") { Text(debug.patch).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } }
                        if !debug.checks.isEmpty { DisclosureGroup("Build & regression checks") { Text(debug.checks).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } }
                        HStack { Button("Export review") { debug.exportRepair() }.disabled(debug.busy); Spacer(); Button("Apply reviewed repair & restart…") { debug.confirmApply = true }.buttonStyle(.borderedProminent).disabled(debug.candidate == nil || debug.busy || store.running || store.vmBusy || store.fileBusy) }
                    } }
                }
                Card { VStack(alignment: .leading, spacing: 14) {
                    HStack { Text("Diagnostic history").font(.system(size: 20, weight: .medium)); Spacer(); Button("Refresh") { debug.reload() }; Button("Export logs") { debug.exportLogs() } }
                    HStack { TextField("Search errors, tools or runs", text: $search).textFieldStyle(.roundedBorder); Toggle("Issues only", isOn: $errorsOnly).toggleStyle(.checkbox) }
                    if filtered.isEmpty { Text("No matching incidents. Turn off Issues only to see run and lifecycle events.").font(.system(size: 12)).foregroundStyle(Palette.muted) }
                    ForEach(filtered.prefix(visibleLimit)) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Image(systemName: event.level == "error" ? "exclamationmark.triangle.fill" : "info.circle").foregroundStyle(event.level == "error" ? .red : Palette.muted); Text(event.summary).font(.system(size: 12, weight: .medium)); Spacer(); Text(event.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10)).foregroundStyle(Palette.muted) }
                            Text("\(event.category) · \(event.provider ?? "app")\(event.model.map { " · " + $0 } ?? "")").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                            if !event.detail.isEmpty { Text(event.detail).font(.system(size: 11)).textSelection(.enabled) }
                            HStack { Button("Debug this") { debug.prepare(event, config: store.config); debug.start(config: store.config, client: store.client) }.disabled(debug.busy || store.running); Button("View context") { debug.prepare(event, config: store.config); showContext = true }.disabled(debug.busy); if let id = event.chatID, store.state.conversations.contains(where: { $0.id == id }) { Button("Open chat") { store.selectedID = id; store.page = .chat } } }
                        }.padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if filtered.count > visibleLimit { Button("Show more history") { visibleLimit += 100 } }
                    Text("Logs keep up to five rotating files of about 2 MB each. They record metadata and sanitized error messages, not conversation bodies. Redaction is best effort; review before sharing exports.").font(.system(size: 10)).foregroundStyle(Palette.muted)
                } }
                if !debug.records.isEmpty {
                    Card { VStack(alignment: .leading, spacing: 12) { Text("Repair history").font(.system(size: 20, weight: .medium)); ForEach(debug.records) { record in HStack { VStack(alignment: .leading, spacing: 5) { Text(record.status == "running" ? "Interrupted investigation" : record.status).font(.system(size: 12, weight: .medium)); Text(record.summary).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2); Text(record.date.formatted()).font(.system(size: 10)) }; Spacer(); Button("Open saved report") { debug.showHistory(record) }; if debug.hasBackup(record) { Button("Restore previous app…") { debug.restoreRecord = record }.disabled(debug.busy || store.running || store.fileBusy || store.vmBusy) } } }; Text("After applying, the saved report folder includes LastGood-Shiro.app and Restore Shiro.command. Close Shiro before using the restore command.").font(.system(size: 10)).foregroundStyle(Palette.muted) } }
                }
            }.padding(32).frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }.confirmationDialog("Apply this reviewed repair?", isPresented: $debug.confirmApply, titleVisibility: .visible) { Button("Back up, apply & restart") { debug.apply() }; Button("Cancel", role: .cancel) {} } message: { Text("This replaces the installed Shiro app with the checked candidate and restarts it. Your chats, models and VM files stay in their existing storage. A last-good copy and restore command are saved in repair history. A passing build cannot guarantee correct runtime behavior.") }
        .confirmationDialog("Restore the previous app?", isPresented: Binding(get: { debug.restoreRecord != nil }, set: { if !$0 { debug.restoreRecord = nil } }), titleVisibility: .visible) { Button("Restore & restart") { debug.restore() }; Button("Cancel", role: .cancel) { debug.restoreRecord = nil } } message: { Text("This restores the last-good app from this repair and restarts Shiro. Chats, models and the VM remain in their existing storage.") }
    }
}

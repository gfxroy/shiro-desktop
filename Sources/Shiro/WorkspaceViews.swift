import SwiftUI
import ShiroCore
import AppKit

struct PageHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.system(size: 27, weight: .semibold)).foregroundStyle(Palette.cream); Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(4) } }
}

struct MemoryView: View {
    @EnvironmentObject var store: AppStore
    @State private var query = ""
    @State private var results: JSON = .null
    @State private var searching = false
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeading(eyebrow: "A little continuity", title: "What Shiro remembers.", subtitle: "Shared facts for every bot, a checkpoint for each session, and searchable originals on this Mac.")
            Card {
                VStack(alignment: .leading, spacing: 15) {
                    HStack { Eyebrow(text: "Shared facts · every bot"); Spacer(); Text("Saved automatically").font(.system(size: 10)).foregroundStyle(Palette.muted) }
                    TextEditor(text: Binding(get: { store.state.memory }, set: { value in var state = store.state; state.memory = value; state.userProfileSource = value; state.userProfileDate = Date(); store.state = state })).disabled(store.running).font(.system(size: 13)).scrollContentBackground(.hidden).frame(maxHeight: .infinity).accessibilityLabel("Shiro's editable memory")
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Automatic context compaction and retry", isOn: $store.state.memoryPolicy.autoCompact)
                    Toggle("Search saved chats and selected text attachments across bots", isOn: $store.state.memoryPolicy.shareHistory)
                    Stepper("Local context budget: \(store.state.memoryPolicy.contextTokens) estimated tokens", value: $store.state.memoryPolicy.localContextTokens, in: 4096...32768, step: 1024)
                    Text("Match your runtime's supported context. The budget includes instructions, tools, memory, conversation and an output reserve. Token counts are conservative estimates. Originals stay saved when active context is compacted.").font(.system(size: 10)).foregroundStyle(Palette.muted)
                    if let session = store.conversation.session {
                        DisclosureGroup("Active session · \(session.phase) · \(session.compactions) compactions") { Text(session.context).font(.system(size: 11)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    }
                }.font(.system(size: 12)).disabled(store.running)
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("Search company, CV facts, decisions…", text: $query).textFieldStyle(.roundedBorder).onSubmit { search() }
                        Button(searching ? "Searching…" : "Search memory") { search() }.disabled(searching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if results != .null {
                        Text(results["mode"].string ?? results["error"].string ?? "").font(.system(size: 10)).foregroundStyle(Palette.muted)
                        ScrollView { VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(results["matches"].array.enumerated()), id: \.offset) { _, hit in
                                DisclosureGroup(hit["source"].string ?? "Saved source") { Text(hit["text"].string ?? "").font(.system(size: 11)).textSelection(.enabled) }
                            }
                        } }.frame(maxHeight: 140)
                    }
                    Button("Clear derived search cache") { Task { do { try await store.memoryIndex.clear(); results = .null } catch { store.error = error.localizedDescription } } }.font(.system(size: 10))
                }
            }
            HStack { Image(systemName: "lock").foregroundStyle(Palette.mint); Text("Search uses on-device English embeddings plus keywords, with keyword fallback. Relevant excerpts go to your selected model; local mode stays local. Shared facts are editable above; bot notes live in each bot's settings. Delete chats to remove their source records. Keep secrets in Connections.").font(.system(size: 10)).foregroundStyle(Palette.muted); Spacer() }
        }.padding(32)
    }
    private func search() {
        guard !searching, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        searching = true
        Task {
            do { results = try await store.memoryIndex.search(state: store.state, botID: store.bot.id, chatID: store.selectedID, query: query) }
            catch { results = .object(["error": .string(error.localizedDescription)]) }
            searching = false
        }
    }
}

struct RoutinesView: View {
    @EnvironmentObject var store: AppStore
    @State private var title = ""
    @State private var prompt = ""
    @State private var minutes = 60
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: "Less remembering to remember", title: "Make it a routine.", subtitle: "Give Shiro an ongoing responsibility. Runs while this app is open and your Mac is awake.")
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Eyebrow(text: "New routine")
                        TextField("A name, like Industry briefing", text: $title).textFieldStyle(.roundedBorder)
                        TextField("What should Shiro check or do? Include sources and what changes matter.", text: $prompt, axis: .vertical).lineLimit(3...5).textFieldStyle(.roundedBorder)
                        HStack {
                            Picker("Repeat", selection: $minutes) { Text("Every 15 minutes").tag(15); Text("Every hour").tag(60); Text("Every 6 hours").tag(360); Text("Every 24 hours").tag(1440) }.frame(width: 240)
                            Spacer()
                            Button("Create routine") { store.state.routines.append(Routine(title: title, prompt: prompt, minutes: minutes)); title = ""; prompt = "" }.buttonStyle(.borderedProminent).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                ForEach(store.state.routines) { routine in
                    Card {
                        HStack(alignment: .top, spacing: 18) {
                            Image(systemName: "clock.arrow.circlepath").font(.system(size: 22, weight: .light)).foregroundStyle(Palette.mint)
                            VStack(alignment: .leading, spacing: 9) {
                                Text(routine.title).font(.system(size: 15, weight: .medium))
                                Text(routine.prompt).font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
                                Text("Every \(routine.minutes) minutes · Next \(routine.nextRun.formatted(date: .abbreviated, time: .shortened)) · \(TimeZone.current.abbreviation() ?? "local time")").font(.system(size: 10)).foregroundStyle(Palette.muted)
                                Button("Run now") { store.newConversation(); store.send(routine.prompt) }.font(.system(size: 11)).disabled(store.running)
                            }
                            Spacer()
                            Toggle("Enabled", isOn: Binding(get: { routine.enabled }, set: { value in if let i = store.state.routines.firstIndex(where: { $0.id == routine.id }) { store.state.routines[i].enabled = value; if value { store.state.routines[i].nextRun = Date().addingTimeInterval(Double(routine.minutes) * 60) } } })).labelsHidden().toggleStyle(.switch)
                            Button { store.state.routines.removeAll { $0.id == routine.id } } label: { Image(systemName: "trash").foregroundStyle(Palette.muted) }.buttonStyle(.plain).help("Delete routine")
                        }
                    }
                }
                Text("Missed intervals are combined into one run when Shiro is available again. Schedules are stored locally. Runs share the selected model and the same approval rules as conversations.").font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
            }.padding(32)
        }
    }
}

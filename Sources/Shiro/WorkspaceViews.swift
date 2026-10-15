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
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeading(eyebrow: "A little continuity", title: "What Shiro remembers.", subtitle: "Your preferences, decisions, and notes for the next conversation. Edit or remove anything.")
            Card {
                VStack(alignment: .leading, spacing: 15) {
                    HStack { Eyebrow(text: "Saved notes"); Spacer(); Text("Saved automatically").font(.system(size: 10)).foregroundStyle(Palette.muted) }
                    TextEditor(text: $store.state.memory).font(.system(size: 13)).scrollContentBackground(.hidden).frame(maxHeight: .infinity).accessibilityLabel("Shiro's editable memory")
                }
            }
            HStack { Image(systemName: "lock").foregroundStyle(Palette.mint); Text("Stored on this Mac. Notes are included in model requests; keep API keys in Connections.").font(.system(size: 11)).foregroundStyle(Palette.muted); Spacer() }
        }.padding(32)
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

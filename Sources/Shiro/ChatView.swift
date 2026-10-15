import SwiftUI
import ShiroCore

private func displayedFiles(_ files: [ChatFile]) -> [ChatFile] {
    files.filter { file in !files.contains(where: { $0.path + ".txt" == file.path && $0.path.lowercased().hasSuffix(".pdf") }) }
}

struct ChatView: View {
    @EnvironmentObject var store: AppStore
    @State private var dropTargeted = false
    var body: some View {
        VStack(spacing: 0) {
            if store.conversation.entries.isEmpty { Spacer(minLength: 20); BotWelcomeView() }
            else {
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(store.conversation.entries) { entry in
                                MessageView(entry: entry).padding(.vertical, entry.role == "tool" ? 4 : 14).id(entry.id)
                            }
                            Color.clear.frame(height: 12).id("bottom")
                        }.padding(.horizontal, 32).padding(.top, 22).frame(maxWidth: 860).frame(maxWidth: .infinity)
                    }.defaultScrollAnchor(.bottom)
                    .onAppear { reader.scrollTo("bottom", anchor: .bottom) }
                    .onChange(of: store.conversation.entries.count) { _, _ in withAnimation(.easeOut(duration: 0.2)) { reader.scrollTo("bottom", anchor: .bottom) } }
                    .onChange(of: store.selectedID) { _, _ in reader.scrollTo("bottom", anchor: .bottom) }
                }
            }
            if let call = store.approval {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Permission to use \(call.name)", systemImage: "hand.raised").font(.system(size: 13, weight: .semibold))
                    Text(String(call.arguments.text.prefix(1800))).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).foregroundStyle(Palette.muted)
                    HStack { Text("This action runs in your computer.").font(.system(size: 11)).foregroundStyle(Palette.muted); Spacer(); Button("Deny") { store.respondToApproval(false) }; Button("Allow once") { store.respondToApproval(true) }.buttonStyle(.borderedProminent) }
                }.padding(16).background(Palette.card, in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 32).padding(.bottom, 8)
            }
            composer
            if store.conversation.entries.isEmpty { Spacer(minLength: 20) }
        }
    }
    private var composer: some View {
        VStack(spacing: 10) {
            if store.running {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text(store.paused ? "Paused · you control the computer" : store.status).font(.system(size: 11)).lineLimit(2)
                    Spacer()
                    Button(store.paused ? "Resume" : "Pause") { store.paused.toggle() }.font(.system(size: 11)).buttonStyle(.plain)
                }.foregroundStyle(Palette.muted).padding(.horizontal, 6)
            }
            VStack(alignment: .leading, spacing: 12) {
                if !store.draftFiles.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(displayedFiles(store.draftFiles)) { file in
                                HStack(spacing: 7) {
                                    Image(systemName: "doc.text").foregroundStyle(Palette.muted)
                                    Text(file.name).lineLimit(1)
                                    Button { store.draftFiles.removeAll { $0.path == file.path || $0.path == file.path + ".txt" } } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).frame(width: 20, height: 20) }.buttonStyle(.plain).accessibilityLabel("Remove " + file.name)
                                }.font(.system(size: 11)).padding(.leading, 10).padding(.vertical, 6).padding(.trailing, 4).background(Palette.card, in: RoundedRectangle(cornerRadius: 9))
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
                TextField("Message " + store.bot.name + "…", text: $store.draft, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 14)).lineLimit(1...6).padding(.horizontal, 4).padding(.top, 4)
                    .frame(minHeight: 24, alignment: .topLeading).disabled(store.running).accessibilityLabel("Message bot")
                HStack(alignment: .center, spacing: 8) {
                    Button { store.attachFiles() } label: { Image(systemName: "paperclip").font(.system(size: 17)).frame(width: 34, height: 34) }.buttonStyle(.plain).foregroundStyle(Palette.muted).disabled(!store.vmReady || store.running || store.fileBusy).accessibilityLabel("Attach files").help("Attach files or drop them here")
                    Menu {
                        Text(store.config.model.isEmpty ? "No model selected" : store.config.model)
                        Divider()
                        Button("Models & connections…") { store.page = .models }
                    } label: { HStack(spacing: 5) { Text(store.config.model.isEmpty ? "Choose model" : store.config.model.hasPrefix("shiro-gemma4") ? "Gemma 4" : store.config.model).lineLimit(1).truncationMode(.middle); Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)) }.font(.system(size: 11)).foregroundStyle(Palette.muted) }.menuStyle(.borderlessButton).menuIndicator(.hidden).tint(Palette.muted).frame(maxWidth: 200, alignment: .leading).accessibilityLabel("Selected model")
                    Spacer(minLength: 8)
                    if store.fileBusy { ProgressView().controlSize(.small).help("Preparing attachment") }
                    Button { if store.running { store.stop() } else { store.send() } } label: { Image(systemName: store.running ? "stop.fill" : "arrow.up").font(.system(size: 14, weight: .semibold)).frame(width: 34, height: 34).foregroundStyle(Palette.background).background(Palette.cream, in: Circle()) }.buttonStyle(.plain).keyboardShortcut(.return, modifiers: .command).disabled(!store.running && (store.modelBusy || store.vmBusy || (store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.draftFiles.isEmpty) || store.fileBusy)).accessibilityLabel(store.running ? "Stop run" : "Send message").help(store.running ? "Stop" : "Send · ⌘Return")
                }.frame(height: 34)
            }.padding(14).background(Palette.surface, in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(dropTargeted ? Palette.mint : Palette.line, lineWidth: dropTargeted ? 2 : 1))
            HStack { Text(store.vmReady ? "Your computer is connected" : "Set up your computer to use tools"); Spacer(); Text("⌘↵ to send") }.font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.horizontal, 5)
        }.frame(maxWidth: 796).padding(.horizontal, 32).padding(.top, 12).padding(.bottom, 18).frame(maxWidth: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { store.dropFiles($0) }
    }
}

struct BotWelcomeView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(spacing: 14) {
            BotAvatar(bot: store.bot, size: 116)
            Text("What can I help with?").font(.system(size: 26, weight: .medium))
            Text("Chat with " + store.bot.name + " or give it something to do.").font(.system(size: 13)).foregroundStyle(Palette.muted)
        }.frame(maxWidth: .infinity).padding(.bottom, 18)
    }
}

struct MessageView: View {
    @EnvironmentObject var store: AppStore
    let entry: Entry
    private var failed: Bool { entry.text.contains("\"error\"") || entry.text.contains("\"ok\":false") || entry.text.contains("\"denied\":true") }
    private var message: AttributedString { (try? AttributedString(markdown: entry.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(entry.text) }
    var body: some View {
        if entry.role == "tool" {
            DisclosureGroup {
                Text(entry.text).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled).padding(.vertical, 8)
                if failed { Button("Debug this error") { store.debugEntry(entry) }.font(.system(size: 11)).disabled(store.running) }
            } label: { Label(entry.text.components(separatedBy: ":").first?.capitalized ?? "Tool", systemImage: failed ? "exclamationmark.circle" : "checkmark.circle").font(.system(size: 11)).foregroundStyle(failed ? .orange : Palette.muted) }.padding(.leading, 32)
        } else if entry.role == "system" {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "info.circle").padding(.top, 2)
                Text(entry.text).font(.system(size: 12)).lineSpacing(3).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                Button { store.debugEntry(entry) } label: { Image(systemName: "ladybug").frame(width: 26, height: 26) }.buttonStyle(.plain).accessibilityLabel("Debug this").help("Debug this update").disabled(store.running)
            }.foregroundStyle(Palette.muted).padding(12).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
        } else {
            VStack(alignment: entry.role == "user" ? .trailing : .leading, spacing: 10) {
                if entry.role == "assistant" {
                    HStack(spacing: 8) { BotAvatar(bot: store.bot, size: 24); Text(store.bot.name).font(.system(size: 12, weight: .semibold)); Text(entry.date.formatted(date: .omitted, time: .shortened)).font(.system(size: 10)).foregroundStyle(Palette.muted) }
                    Text(message).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled).padding(.leading, 32).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(message).font(.system(size: 14)).lineSpacing(4).textSelection(.enabled).padding(.horizontal, 16).padding(.vertical, 13).background(Palette.userBubble, in: RoundedRectangle(cornerRadius: 18)).frame(maxWidth: 620, alignment: .trailing)
                }
                if let files = entry.attachments { ForEach(displayedFiles(files)) { file in FileCard(file: file) } }
            }.frame(maxWidth: .infinity, alignment: entry.role == "user" ? .trailing : .leading)
        }
    }
}

struct ActivityView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Eyebrow(text: "Behind the scenes"); Spacer() }
            HStack(spacing: 9) { ShiroAvatar(size: 35, active: true); VStack(alignment: .leading, spacing: 4) { Text(store.paused ? "Paused for you" : "On it.").font(.system(size: 12, weight: .medium)); Text(store.config.model).font(.system(size: 9)).foregroundStyle(Palette.muted).lineLimit(1) } }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(store.activity) { activity in
                        HStack(alignment: .top, spacing: 9) {
                            Circle().fill(Palette.mint.opacity(0.5)).frame(width: 5, height: 5).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 5) { Text(activity.title).font(.system(size: 11)); Text(activity.detail).font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted).lineLimit(4) }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Progress shows actions and results, not private model reasoning.").font(.system(size: 9)).foregroundStyle(Palette.muted).lineSpacing(3)
        }.padding(20).background(Palette.sidebar.opacity(0.4))
    }
}

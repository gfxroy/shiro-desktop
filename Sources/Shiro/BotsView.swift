import SwiftUI
import ShiroCore

struct NewRecipientView: View {
    @EnvironmentObject var store: AppStore
    @State private var name = ""
    @State private var creating = false
    @State private var instructions = ""
    @State private var character = Bot(name: "New Bot")
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("To:").foregroundStyle(Palette.muted); TextField("Start a chat with…", text: $name).textFieldStyle(.plain).font(.system(size: 19)); Button { store.showNewRecipient = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Close new chat") }
            Divider()
            if creating {
                ScrollView {
                    HStack(alignment: .top, spacing: 28) {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Create new Bot").font(.system(size: 23, weight: .medium))
                            TextField("Bot name", text: $name).textFieldStyle(.roundedBorder)
                            TextField("Instructions for this bot (optional)", text: $instructions, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(4...8)
                            Picker("Category", selection: Binding(get: { character.category ?? "General" }, set: { character.category = $0 })) {
                                ForEach(["General", "Research", "Builder", "Manager", "Creative"], id: \.self) { Text($0).tag($0) }
                            }
                            Text("Choose a character before you create your bot. You can change it later in Bot details.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        CharacterPicker(bot: $character).frame(width: 324).padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                HStack { Button("Back") { creating = false }; Spacer(); Button("Create Bot") { character.name = name; character.instructions = instructions; store.createBot(character) }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.running || store.fileBusy) }

            } else {
                Button { creating = true } label: { Label("Create new Bot", systemImage: "plus.circle.fill").font(.system(size: 17)).frame(maxWidth: .infinity, alignment: .leading).padding(18).background(Palette.card, in: RoundedRectangle(cornerRadius: 14)) }.buttonStyle(.plain)
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.state.bots.filter { name.isEmpty || $0.name.localizedCaseInsensitiveContains(name) }) { bot in
                            Button { store.newConversation(botID: bot.id) } label: { HStack(spacing: 15) { BotAvatar(bot: bot, size: 34); Text(bot.name).font(.system(size: 16)); Spacer(); Text("New chat").font(.system(size: 11)).foregroundStyle(Palette.muted) }.padding(15) }.buttonStyle(.plain)
                        }
                    }
                }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line))
            }
            Spacer()
        }.padding(28)
    }
}

struct BotDetailsView: View {
    @EnvironmentObject var store: AppStore
    private func binding<T>(_ path: WritableKeyPath<Bot, T>) -> Binding<T> {
        Binding(get: { store.bot[keyPath: path] }, set: { value in var bot = store.bot; bot[keyPath: path] = value; store.updateBot(bot) })
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Bot details").font(.system(size: 13, weight: .semibold)); Spacer(); Button { store.showDetails = false } label: { Image(systemName: "xmark").font(.system(size: 11)).frame(width: 26, height: 26) }.buttonStyle(.plain).accessibilityLabel("Close bot details") }.padding(18)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) { BotAvatar(bot: store.bot, size: 42); VStack(alignment: .leading, spacing: 5) { TextField("Bot name", text: binding(\.name)).font(.system(size: 16, weight: .semibold)).textFieldStyle(.plain).disabled(store.running); Text(store.bot.category ?? "General").font(.system(size: 11)).foregroundStyle(Palette.muted) } }
                    Picker("Bot section", selection: $store.detailTab) { Text("Details").tag("Details"); Text("Chats").tag("Chats"); Text("Files").tag("Files") }.pickerStyle(.segmented).labelsHidden()
                    if store.detailTab == "Chats" {
                        Button { store.newConversation(botID: store.bot.id) } label: { Label("New chat", systemImage: "square.and.pencil") }.disabled(store.running)
                        ForEach(store.botChats) { chat in
                            Button { store.selectedID = chat.id } label: { HStack { Text(chat.title).font(.system(size: 12)).lineLimit(2); Spacer(); if chat.id == store.selectedID { Image(systemName: "checkmark").font(.system(size: 10)) } }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(chat.id == store.selectedID ? Palette.selection : .clear, in: RoundedRectangle(cornerRadius: 9)) }.buttonStyle(.plain).disabled(store.running)
                        }
                    } else if store.detailTab == "Files" {
                        Button("Open all computer files") { store.openComputerPanel("Files") }.font(.system(size: 12))
                        ForEach(store.botChats.flatMap { $0.entries.flatMap { $0.attachments ?? [] } }.reduce(into: [ChatFile]()) { files, item in if !files.contains(where: { $0.path == item.path }) { files.append(item) } }.filter { !$0.path.hasSuffix(".pdf.txt") }) { file in FileCard(file: file) }
                    } else {
                        AvatarOptions(bot: store.bot)
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Instructions").font(.system(size: 12, weight: .medium))
                            TextField("What should this bot do?", text: binding(\.instructions), axis: .vertical).textFieldStyle(.plain).lineLimit(4...8).font(.system(size: 12)).padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 10)).disabled(store.running)
                        }
                        Picker("Category", selection: Binding(get: { store.bot.category ?? "General" }, set: { value in var bot = store.bot; bot.category = value; store.updateBot(bot) })) { ForEach(["General", "Research", "Builder", "Manager", "Creative"], id: \.self) { Text($0).tag($0) } }.font(.system(size: 12))
                        DisclosureGroup("Memory") { TextField("Notes saved by this bot", text: binding(\.memory), axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(3...6).font(.system(size: 12)).disabled(store.running).padding(.top, 8) }.font(.system(size: 12))
                        Button { store.page = .routines } label: { Label("Routines", systemImage: "clock.arrow.circlepath") }.font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(Palette.muted)
                    }
                }.padding(.horizontal, 18).padding(.bottom, 20)
            }.scrollIndicators(.hidden)
        }.background(Palette.sidebar)
    }
}

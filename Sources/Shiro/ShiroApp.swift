import SwiftUI
import AppKit
import ShiroCore

enum AppResources {
    static let bundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Shiro_Shiro.bundle"), let bundle = Bundle(url: url) { return bundle }
        return Bundle.module
    }()
}

@main struct ShiroApp: App {
    @StateObject private var store = AppStore()
    @AppStorage("shiro.appearance") private var appearance = "dark"
    var body: some Scene {
        WindowGroup("Shiro") {
            RootView().environmentObject(store).frame(minWidth: 960, minHeight: 640).preferredColorScheme(appearance == "system" ? nil : appearance == "light" ? .light : .dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 850)
        .commands {
            CommandGroup(replacing: .newItem) { Button("New Bot or Chat") { store.showNewRecipient = true; store.page = .chat }.keyboardShortcut("n").disabled(store.running) }
            CommandMenu("Shiro") {
                Button("Stop Current Run") { store.stop() }.keyboardShortcut(".", modifiers: .command).disabled(!store.running)
                Button("Models & Connections") { store.page = .models }.keyboardShortcut(",")
                Button("Shiro's Computer") { store.openComputerPanel() }.keyboardShortcut("2")
                Button("Debug & Repair") { store.openDebug() }.keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
    }
}

enum Palette {
    private static func adaptive(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
    static let background = adaptive(.white, NSColor(srgbRed: 0.085, green: 0.09, blue: 0.10, alpha: 1))
    static let sidebar = adaptive(NSColor(white: 0.96, alpha: 1), NSColor(srgbRed: 0.055, green: 0.06, blue: 0.065, alpha: 1))
    static let surface = adaptive(.white, NSColor(srgbRed: 0.13, green: 0.135, blue: 0.145, alpha: 1))
    static let card = adaptive(NSColor(white: 0.96, alpha: 1), NSColor(srgbRed: 0.11, green: 0.115, blue: 0.125, alpha: 1))
    static let selection = adaptive(NSColor(white: 0.90, alpha: 1), NSColor(white: 0.15, alpha: 1))
    static let userBubble = adaptive(NSColor(white: 0.94, alpha: 1), NSColor(white: 0.18, alpha: 1))
    static let mint = adaptive(NSColor(srgbRed: 0.12, green: 0.40, blue: 0.85, alpha: 1), NSColor(srgbRed: 0.40, green: 0.64, blue: 1, alpha: 1))
    static let cream = Color.primary
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let line = adaptive(NSColor.black.withAlphaComponent(0.08), NSColor.white.withAlphaComponent(0.08))
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(22).background(Palette.card, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line)) }
}

struct Eyebrow: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted) }
}

struct StatusDot: View {
    var active: Bool
    var body: some View { Circle().fill(active ? Palette.mint : Palette.muted.opacity(0.5)).frame(width: 6, height: 6).shadow(color: active ? Palette.mint.opacity(0.4) : .clear, radius: 5) }
}

struct ShiroAvatar: View {
    @EnvironmentObject var store: AppStore
    var size: CGFloat = 72
    var active = false
    var body: some View { Avatar3D(bot: store.bot, size: size, active: active).frame(width: size, height: size) }
}

struct BotAvatar: View {
    let bot: Bot
    var size: CGFloat = 36
    @EnvironmentObject var store: AppStore
    var body: some View {
        Avatar3D(bot: bot, size: size, active: store.running && store.activeBotID == bot.id)
            .frame(width: size, height: size).accessibilityLabel(bot.name + " animated character")
    }

}

struct RootView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        HStack(spacing: 0) {
            if store.page != .computer { SidebarView().frame(width: 240); Rectangle().fill(Palette.line).frame(width: 1) }
            VStack(spacing: 0) {
                if store.page != .chat {
                    HStack { Text(store.page.rawValue).font(.system(size: 16, weight: .medium)); Spacer(); Button(store.page == .computer ? "Back to chat" : "Back to bots") { store.page = .chat } }.padding(20)
                    Divider()
                } else if !store.showNewRecipient {
                    ZStack {
                        Button { store.showComputerPanel = false; store.detailTab = "Details"; store.showDetails.toggle() } label: {
                            HStack(spacing: 8) { BotAvatar(bot: store.bot, size: 34); Text(store.bot.name).font(.system(size: 14, weight: .semibold)); Image(systemName: "chevron.down").font(.system(size: 9)) }
                        }.buttonStyle(.plain).help("Bot details and chats").offset(x: store.showComputerPanel ? -160 : store.showDetails ? -146 : 0)
                        HStack {
                            Button { store.newConversation(botID: store.bot.id) } label: { Image(systemName: "square.and.pencil").frame(width: 32, height: 32) }.buttonStyle(.plain).disabled(store.running).accessibilityLabel("New chat with this bot")
                            Spacer()
                            Button { if store.showComputerPanel { store.showComputerPanel = false } else { store.openComputerPanel() } } label: { Image(systemName: "sidebar.right").frame(width: 32, height: 32) }.buttonStyle(.plain).accessibilityLabel("Computer and files panel")
                        }
                    }.padding(.horizontal, 24).frame(height: 64)

                    Rectangle().fill(Palette.line).frame(height: 1)
                }
                if store.running && store.page != .chat {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text(store.paused ? "Paused · you have control" : store.status).font(.system(size: 12))
                        Spacer()
                        Button(store.approval == nil ? "View active chat" : "Review pending approval") { store.page = .chat }
                        Button("Stop") { store.stop() }
                    }.padding(14).background(Palette.mint.opacity(0.06))
                }
                Group {
                    switch store.page {
                    case .chat:
                        if store.showNewRecipient { NewRecipientView() }
                        else {
                            HStack(spacing: 0) {
                                ChatView().frame(maxWidth: .infinity)
                                if store.showComputerPanel { Rectangle().fill(Palette.line).frame(width: 1); ComputerPanelView().frame(width: 320) }
                                else if store.showDetails { Rectangle().fill(Palette.line).frame(width: 1); BotDetailsView().frame(width: 292) }
                            }
                        }
                    case .computer: ComputerView()
                    case .files: FilesView().onAppear { store.openComputerPanel("Files") }
                    case .settings: SettingsView()
                    case .memory: MemoryView()
                    case .routines: RoutinesView()
                    case .models: ModelsView()
                    case .debug: DebugView(debug: store.debugController)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.foregroundStyle(Palette.cream).background(Palette.background).tint(Palette.mint)
        .sheet(isPresented: Binding(get: { store.avatarEditorID != nil }, set: { if !$0 { store.avatarEditorID = nil } })) { if let id = store.avatarEditorID { AvatarEditorView(botID: id) } }
        .sheet(isPresented: Binding(get: { store.previewURL != nil }, set: { if !$0 { store.previewURL = nil } })) { FilePreviewView() }
        .alert("Shiro needs your attention", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil }; Button("Debug this") { store.openDebug(); if !store.running && !store.modelBusy { store.debugController.start(config: store.config, client: store.client) } } } message: { Text(store.error ?? "") }
    }
}

struct SidebarView: View {
    @EnvironmentObject var store: AppStore
    @State private var searching = false
    @State private var query = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Shiro").font(.system(size: 17, weight: .semibold)); Spacer()
                icon("magnifyingglass", "Search bots") { searching.toggle() }
                icon("plus", "New Bot or Chat") { store.showNewRecipient = true; store.page = .chat }.disabled(store.running)
            }.padding(.top, 38).padding(.bottom, 24).padding(.horizontal, 10)
            if searching { TextField("Search bots", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal, 10).padding(.bottom, 16) }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(store.state.bots.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }.sorted { $0.pinned && !$1.pinned }) { bot in
                        botRow(bot)
                    }
                }
            }.scrollIndicators(.hidden)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button { store.openComputerPanel("Files") } label: { Label("Files", systemImage: "folder").frame(maxWidth: .infinity, alignment: .leading) }
                    Button { store.openComputerPanel() } label: { Label("Computer", systemImage: "desktopcomputer").frame(maxWidth: .infinity, alignment: .leading) }
                }.font(.system(size: 12)).buttonStyle(.plain).padding(.vertical, 10)
                Rectangle().fill(Palette.line).frame(height: 1)
                HStack {
                    Button { store.page = .settings } label: { Label("Settings", systemImage: "gearshape").frame(height: 34) }.accessibilityLabel("Account & settings")
                    Spacer()
                    Button { store.page = .models } label: { Label("Models", systemImage: "slider.horizontal.3").frame(height: 34) }.accessibilityLabel("Models & connections")
                }.font(.system(size: 12)).buttonStyle(.plain)
            }.foregroundStyle(Palette.muted).padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 14)
        }.padding(.horizontal, 12).background(Palette.sidebar)
    }
    private func botRow(_ bot: Bot) -> some View {
        Button { store.selectBot(bot.id) } label: {
            HStack(spacing: 12) {
                BotAvatar(bot: bot, size: 44)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) { Text(bot.name).font(.system(size: 13, weight: .medium)).lineLimit(1); if bot.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Palette.muted) } }
                    Text(store.state.conversations.first(where: { $0.botID == bot.id })?.entries.last(where: { $0.role == "assistant" || $0.role == "user" })?.text.replacingOccurrences(of: "\n", with: " ") ?? "Start a conversation").font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.horizontal, 10).frame(height: 72).background(store.bot.id == bot.id && store.page == .chat ? Palette.selection : .clear, in: RoundedRectangle(cornerRadius: 14))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).disabled(store.running)
    }
    private func icon(_ image: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: image).font(.system(size: 14, weight: .medium)).frame(width: 30, height: 30).contentShape(RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).foregroundStyle(Palette.muted).accessibilityLabel(label).help(label)
    }
}

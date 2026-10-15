import SwiftUI
import AppKit
import ShiroCore

struct AvatarOptions: View {
    @EnvironmentObject var store: AppStore
    let bot: Bot
    var showCustomizer = true
    var body: some View {
        Button { store.avatarEditorID = bot.id } label: {
            HStack(spacing: 12) { Avatar3D(bot: bot, size: 38).frame(width: 38, height: 38); VStack(alignment: .leading, spacing: 4) { Text("Character").font(.system(size: 12, weight: .medium)); Text("Shape, color & motion").font(.system(size: 11)).foregroundStyle(Palette.muted) }; Spacer(); Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Palette.muted) }.padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityLabel("Customize character")
    }
}

struct AvatarEditorView: View {
    @EnvironmentObject var store: AppStore
    let botID: UUID
    @State private var showImport = false
    private var bot: Bot { store.state.bots.first { $0.id == botID } ?? store.bot }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Customize character").font(.system(size: 17, weight: .semibold)); Spacer(); Button("Done") { store.avatarEditorID = nil }.keyboardShortcut(.defaultAction) }.padding(22)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    CharacterPicker(bot: Binding(get: { bot }, set: { store.updateBot($0) }))
                    DisclosureGroup("Custom model", isExpanded: $showImport) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Your model uses the same flat color treatment.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                            Button("Import 3D model…") { store.importAvatar(botID) }
                            if let path = bot.avatarModelPath { Text(URL(fileURLWithPath: path).lastPathComponent).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1) }
                        }.padding(.top, 8)
                    }.font(.system(size: 11))
                }.padding(24)
            }
        }.frame(width: 500, height: 700).background(Palette.background).foregroundStyle(Palette.cream)
    }
}

/// Shared by creation and editing, so the preview is exactly what gets saved.
struct CharacterPicker: View {
    @Binding var bot: Bot
    static let shapes = [("Pebble", "cat"), ("Square", "robot"), ("Blob", "orb"), ("Circle", "circle"), ("Capsule", "capsule"), ("Diamond", "diamond"), ("Star", "star"), ("Hexagon", "hexagon"), ("Cloud", "cloud")]
    private var color: Binding<Color> {
        Binding(get: { Color(nsColor: AvatarSceneView.coatColor(for: bot)) }, set: { value in
            if let rgb = NSColor(value).usingColorSpace(.sRGB) { bot.avatarColor = String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255)) }
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Avatar3D(bot: bot, size: 112).frame(width: 112, height: 112).frame(maxWidth: .infinity)
            Text("Shape").font(.system(size: 12, weight: .medium))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Self.shapes, id: \.1) { title, kind in
                    Button { bot.avatarKind = kind } label: {
                        let sample = preview(kind)
                        HStack(spacing: 4) { Avatar3D(bot: sample, size: 28).frame(width: 28, height: 28); Text(title).font(.system(size: 11)) }
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .background(bot.avatarFamily == kind ? Palette.selection : Palette.card, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(bot.avatarFamily == kind ? Palette.mint : Palette.line))
                    }.buttonStyle(.plain).accessibilityLabel(title + " shape").accessibilityAddTraits(bot.avatarFamily == kind ? .isSelected : [])
                }
            }
            Text("Color").font(.system(size: 12, weight: .medium))
            HStack(spacing: 7) {
                ForEach(["cream", "blue", "teal", "pink", "purple", "orange", "graphite"], id: \.self) { tint in
                    let sample = tinted(tint)
                    Button { bot.avatarColor = tint } label: { Circle().fill(Color(nsColor: AvatarSceneView.coatColor(for: sample))).frame(width: 22, height: 22).padding(3).overlay(Circle().stroke(bot.avatarTint == tint ? Palette.cream : .clear, lineWidth: 1.5)) }.buttonStyle(.plain).accessibilityLabel(tint.capitalized + " character color")
                }
                ColorPicker("Custom color", selection: color, supportsOpacity: false).labelsHidden()
            }
            Toggle("Follow the mouse", isOn: Binding(get: { bot.avatarMouseTracking != false }, set: { bot.avatarMouseTracking = $0 }))
            Toggle("Gentle animation", isOn: Binding(get: { bot.animateAvatar != false }, set: { bot.animateAvatar = $0 }))
        }.font(.system(size: 12)).toggleStyle(.switch)
    }
    private func preview(_ kind: String) -> Bot { var value = bot; value.avatarKind = kind; value.animateAvatar = false; value.avatarMouseTracking = false; return value }
    private func tinted(_ tint: String) -> Bot { var value = bot; value.avatarColor = tint; return value }
}

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("shiro.appearance") private var appearance = "dark"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: "Make it yours", title: "Account & settings", subtitle: "Your bots, computer and preferences live on this Mac.")
                Card { HStack(spacing: 18) { Image(systemName: "person.crop.circle.fill").font(.system(size: 48)).foregroundStyle(Palette.mint); VStack(alignment: .leading, spacing: 5) { Text(NSFullUserName()).font(.system(size: 20, weight: .medium)); Text("Local account · no Shiro subscription required").font(.system(size: 12)).foregroundStyle(Palette.muted) }; Spacer() } }
                if let main = store.state.bots.first(where: { $0.pinned }) {
                    Card { VStack(alignment: .leading, spacing: 18) {
                        HStack { BotAvatar(bot: main, size: 60); Text("Your main bot").font(.system(size: 20, weight: .medium)); Spacer() }
                        TextField("Shiro bot", text: Binding(get: { store.state.bots.first { $0.id == main.id }?.name ?? main.name }, set: { var bot = store.state.bots.first { $0.id == main.id } ?? main; bot.name = $0; store.updateBot(bot) })).textFieldStyle(.roundedBorder)
                        AvatarOptions(bot: main)
                        Text("Your main bot can list, consult and delegate to other bots. All bots use one shared computer, taking turns for delegated work.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    } }
                }
                Card { VStack(alignment: .leading, spacing: 14) { Text("Preferences").font(.system(size: 20, weight: .medium)); Picker("Appearance", selection: $appearance) { Text("Dark").tag("dark"); Text("Light").tag("light"); Text("System").tag("system") }.frame(maxWidth: 320); Toggle("Refresh the live computer preview", isOn: $store.refreshScreenAutomatically); Button("Models & connections") { store.page = .models }; Button("Memory") { store.page = .memory }; Button("Routines") { store.page = .routines }; Button("Debug & repair") { store.openDebug() }; Text("Inspect persistent logs or let your connected model investigate an app bug in an isolated source copy.").font(.system(size: 11)).foregroundStyle(Palette.muted) } }
                Text("Stopping a task stops automatic continuation. Pausing or Take control holds bot actions until you hand the computer back. Login and CAPTCHA steps may still need you.").font(.system(size: 12)).foregroundStyle(Palette.muted)
            }.padding(32).frame(maxWidth: 850).frame(maxWidth: .infinity)
        }
    }
}

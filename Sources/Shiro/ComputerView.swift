import SwiftUI
import ShiroCore
import AppKit

struct ComputerPanelView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Workspace").font(.system(size: 13, weight: .semibold)); Spacer()
                Button { store.showComputerPanel = false } label: { Image(systemName: "xmark").frame(width: 26, height: 26) }.buttonStyle(.plain).accessibilityLabel("Close workspace panel")
            }.padding(14)
            Picker("Workspace section", selection: $store.computerTab) { Text("Computer").tag("Computer"); Text("Files").tag("Files") }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 14).padding(.bottom, 14)
            Divider()
            if store.computerTab == "Files" { FilesView(compact: true) }
            else {
                VStack(alignment: .leading, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Palette.background)
                        if let screen = store.screen { Image(nsImage: screen).resizable().aspectRatio(contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12)) }
                        else { Image(systemName: "desktopcomputer").font(.system(size: 34, weight: .light)).foregroundStyle(Palette.muted) }
                    }.aspectRatio(1.6, contentMode: .fit)
                    HStack(spacing: 7) { StatusDot(active: store.vmReady); Text(store.vmReady ? "Computer connected" : store.vmStatus).font(.system(size: 11)).foregroundStyle(Palette.muted) }
                    Button { store.page = .computer } label: { Label(store.vmReady ? "Open computer" : "Set up computer", systemImage: "arrow.up.left.and.arrow.down.right").frame(maxWidth: .infinity).padding(.vertical, 7) }.buttonStyle(.bordered).accessibilityLabel("Expand computer in this window")
                    if store.running { Text(store.paused ? "Paused · you have control" : store.status).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(3) }
                    Text("Open the desktop here to take control. Your chat stays in this window.").font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
                    Spacer()
                }.padding(14)
            }
        }.background(Palette.sidebar).task { if store.vmReady { await store.refreshScreen() } }
    }
}

struct ComputerView: View {
    @EnvironmentObject var store: AppStore
    @State private var attachName = ""
    @State private var showAttachConfirmation = false
    
    var body: some View {
        GeometryReader { geometry in
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "A place to get things done")
                        Text(store.bot.name + "’s computer").font(.system(size: 24, weight: .medium)).foregroundStyle(Palette.cream)
                        Text("A persistent Linux desktop, right here on your Mac.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    if store.vmBusy { ProgressView().controlSize(.small); Text(store.vmStatus).font(.system(size: 11)).foregroundStyle(Palette.muted).frame(maxWidth: 180) }
                    else if store.vmReady {
                        Button(store.paused ? "Hand back to Shiro" : "Take control") { store.paused.toggle() }.buttonStyle(.borderedProminent)
                        Button { Task { await store.refreshScreen() } } label: { Image(systemName: "arrow.clockwise") }.help("Refresh screen")
                    }
                }
                if store.vmReady {
                    desktop.frame(height: max(320, geometry.size.height - 240))
                    HStack(spacing: 12) {
                        StatusDot(active: true)
                        Text(store.state.vmName).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                        Text("1280 × 800").font(.system(size: 10)).foregroundStyle(Palette.muted)
                        Spacer()
                        Toggle("Live preview", isOn: $store.refreshScreenAutomatically).toggleStyle(.checkbox).font(.system(size: 10))
                        Button("Stop VM") { store.stopVM() }.font(.system(size: 10)).disabled(store.running)
                    }
                    if let active = store.state.bots.first(where: { $0.id == store.activeBotID }), store.running { Text(active.name + " is using the shared computer").font(.system(size: 12)).foregroundStyle(Palette.mint) }
                    if store.paused && store.running { Text("Shiro pauses before its next action. An action already in progress may finish first.").font(.system(size: 11)).foregroundStyle(Palette.muted) }
                    HStack(spacing: 12) {
                        Button { launch("browser") } label: { Label("Browser", systemImage: "globe") }
                        Button { launch("terminal") } label: { Label("Terminal", systemImage: "terminal") }
                        Button { launch("files") } label: { Label("Files", systemImage: "folder") }
                        Spacer()
                        Text(store.paused ? "Click the screen and type directly" : "Take control to use mouse and keyboard").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }.buttonStyle(.bordered)

                } else {
                    setup
                }
                HStack(alignment: .top, spacing: 18) {
                    Image(systemName: "lock.shield").foregroundStyle(Palette.mint)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("A workspace of its own").font(.system(size: 12, weight: .medium))
                        Text("Your Mac folders and SSH keys aren't shared with a new Shiro VM. API keys stay in the Mac Keychain. The VM has internet access; cloud models receive the task context and selected tool results. Local work requires this Mac to remain awake.").font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
                    }
                }.padding(20).background(Palette.card.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
            }.padding(22)
        }.task { if store.vmReady { await store.refreshScreen() } }
        .confirmationDialog("Connect this existing VM?", isPresented: $showAttachConfirmation, titleVisibility: .visible) {
            Button("Prepare and connect") { store.setupVM(existing: attachName) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Shiro will add a separate shiro-local user, tool script and desktop service on display :88 to \(attachName). Its existing files stay in the VM, and Linux file permissions determine which are visible. For a fresh boundary, create a new Shiro VM.") }
        }
    }
    private func launch(_ app: String) { store.paused = true; store.manual("computer", ["action": .string("launch"), "text": .string(app)]) }
    private var desktop: some View {
        RemoteDesktop(image: store.screen, enabled: store.paused && store.vmReady) { args in store.manual("computer", args) }
            .clipShape(RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line))
    }
    private var setup: some View {
        VStack(spacing: 20) {
            Card {
                HStack(alignment: .top, spacing: 14) {
                    ZStack { RoundedRectangle(cornerRadius: 17).fill(Palette.mint.opacity(0.08)); Image(systemName: "desktopcomputer").font(.system(size: 36, weight: .ultraLight)).foregroundStyle(Palette.mint) }.frame(width: 86, height: 86)
                    VStack(alignment: .leading, spacing: 11) {
                        Text("Give Shiro a local computer").font(.system(size: 19, design: .default))
                        Text("Linux, Chromium, a terminal, and a private workspace.\n2 CPU cores · 3 GB RAM · 16 GB virtual disk\nFirst setup downloads Linux and needs at least 5 GB free.").font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(5)
                        HStack {
                            if store.vm.executable == nil {
                                Button("Install Lima") { NSWorkspace.shared.open(URL(string: "https://lima-vm.io/docs/installation/")!) }.buttonStyle(.borderedProminent)
                            } else {
                                Button("Create local computer") { store.setupVM() }.buttonStyle(.borderedProminent).disabled(store.vmBusy)
                            }
                            Button("Refresh") { Task { await store.refreshVMs() } }.disabled(store.vmBusy)
                        }.padding(.top, 7)
                    }
                    Spacer()
                }
            }
            if !store.machines.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 15) {
                        Eyebrow(text: "Or use an existing local VM")
                        ForEach(store.machines) { machine in
                            HStack {
                                StatusDot(active: machine.status == "Running")
                                VStack(alignment: .leading, spacing: 4) { Text(machine.name).font(.system(size: 11, design: .monospaced)); Text("\(machine.status) · \(machine.type.uppercased()) · \(machine.safe ? "No host mounts or SSH forwarding" : "Host sharing enabled — cannot attach")").font(.system(size: 10)).foregroundStyle(Palette.muted) }
                                Spacer()
                                Button("Connect") { attachName = machine.name; showAttachConfirmation = true }.disabled(!machine.safe || machine.type != "vz" || store.vmBusy)
                            }
                        }
                    }
                }
            }
        }
    }
}

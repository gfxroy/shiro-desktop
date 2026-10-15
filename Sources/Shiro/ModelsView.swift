import SwiftUI
import AppKit
import ShiroCore

struct ModelsView: View {
    @EnvironmentObject var store: AppStore
    @State private var selected: Provider = .local
    @State private var key = ""
    @State private var downloadName = "qwen3.5:4b"
    @State private var showFormats = false
    private var config: ProviderConfig { store.config(for: selected) }
    private func configBinding<T>(_ path: WritableKeyPath<ProviderConfig, T>) -> Binding<T> {
        Binding(get: { config[keyPath: path] }, set: { value in var c = config; c[keyPath: path] = value; store.updateConfig(c) })
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                PageHeading(eyebrow: "Your choice of intelligence", title: "Models & connections", subtitle: "Choose the brain for every bot. Your shared computer stays local.")
                HStack(spacing: 10) {
                    ForEach(Provider.allCases) { provider in
                        Button { selected = provider; key = "" } label: {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack { Image(systemName: icon(provider)).font(.system(size: 19, weight: .light)); Spacer(); if store.state.provider == provider { Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(Palette.mint) } }
                                Text(provider.title).font(.system(size: 12, weight: .medium))
                                Text(provider == .local ? "On this Mac" : "Your API key").font(.system(size: 10)).foregroundStyle(Palette.muted)
                            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(Palette.cream).background(selected == provider ? Palette.mint.opacity(0.085) : Palette.card, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(selected == provider ? Palette.mint.opacity(0.35) : Palette.line))
                        }.buttonStyle(.plain).disabled(store.running)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text(selected == .local ? "Models running on this Mac" : "Connect \(selected.title)").font(.system(size: 20, design: .default))
                            Spacer()
                            Text(store.connectionStatus[selected] ?? "Not checked").font(.system(size: 10)).foregroundStyle(Palette.muted)
                        }
                        if selected != .local {
                            HStack {
                                SecureField("Paste your \(selected.title) API key", text: $key).textFieldStyle(.roundedBorder)
                                Button("Save key") { store.saveKey(key, provider: selected); key = "" }.disabled(key.isEmpty)
                                Button("Remove key", role: .destructive) { store.saveKey("", provider: selected) }
                            }
                            Text("Keys are stored in macOS Keychain and sent only to the provider's official API. Your chat subscription does not include API usage.").font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(4)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow(text: "API endpoint")
                            if selected == .local { TextField("http://127.0.0.1:11434/v1", text: configBinding(\.endpoint)).textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced)) }
                            else { Text(config.endpoint).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled) }
                        }
                        HStack(alignment: .bottom, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) { Eyebrow(text: "Model"); TextField(selected.placeholder, text: configBinding(\.model)).textFieldStyle(.roundedBorder) }
                            Button("Fetch models") { store.discoverModels(selected) }.disabled(store.modelBusy)
                        }
                        if let models = store.availableModels[selected], !models.isEmpty {
                            Picker("Available models", selection: configBinding(\.model)) {
                                if !models.contains(config.model) { Text(config.model.isEmpty ? "Choose model" : config.model).tag(config.model) }
                                ForEach(models, id: \.self) { Text($0).tag($0) }
                            }
                        }
                        HStack {
                            Toggle("Send screenshots to this model", isOn: configBinding(\.vision)).toggleStyle(.checkbox).font(.system(size: 11))
                            Spacer()
                            Button(store.state.provider == selected ? "Selected for Shiro" : "Use this provider") { store.state.provider = selected }.buttonStyle(.borderedProminent).disabled(config.model.isEmpty || store.running)
                        }
                        Text("Enable screenshots only for a vision-capable model. Text models can use browser text, files, and shell tools. Some models support chat only and will reject tool requests.").font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(4)
                        if selected == .local, config.model.lowercased().hasPrefix("qwen"), (config.localRuntime == .ollama || URL(string: config.endpoint)?.port == 11434) {
                            Toggle("Extra thinking for Qwen (slower)", isOn: Binding(get: { config.localThinking == true }, set: { value in var c = config; c.localThinking = value; store.updateConfig(c) })).font(.system(size: 11)).disabled(store.running)
                        }
                    }
                }
                if selected == .local { localModels }
                Card {
                    VStack(alignment: .leading, spacing: 17) {
                        Eyebrow(text: "A little control goes a long way")
                        Toggle("Ask before shell commands, clicks, and typing", isOn: $store.state.askBeforeActions).toggleStyle(.switch).font(.system(size: 12))
                        Text("When off, Shiro can operate freely inside the VM, including on signed-in websites. Keep it on when browsing accounts or unfamiliar pages.").font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(4)
                        HStack { Text("Actions between automatic checkpoints").font(.system(size: 11)); Spacer(); Stepper("\(store.state.maxSteps)", value: $store.state.maxSteps, in: 4...80, step: 4).font(.system(size: 11)).frame(width: 100) }
                        Text("At a checkpoint Shiro saves progress, rests for 10 seconds and continues automatically. Stop ends the task; Pause gives you the computer. Repeated failures stop with a specific diagnosis.").font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }
                }
            }.padding(32).frame(maxWidth: 940).frame(maxWidth: .infinity)
        }.onAppear { selected = store.state.provider }
    }
    private var localModels: some View {
        VStack(spacing: 20) {
            Card {
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Text("Bring your own model").font(.system(size: 19, design: .default)); Spacer(); Image(systemName: "externaldrive").foregroundStyle(Palette.mint) }
                    Text("Use models already loaded in Ollama, LM Studio, llama.cpp, or an MLX server with an OpenAI-compatible API. Enter its loopback endpoint and fetch models. Shiro uses the Mac's GPU through that runtime.").font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
                    HStack {
                        Button("Add model file or folder") { store.importModel() }.buttonStyle(.borderedProminent).disabled(store.modelBusy || store.running)
                        Button("Supported formats") { showFormats = true }
                        Spacer()
                        Button("Start / install Ollama") { store.startLocalRuntime() }.disabled(store.modelBusy || store.running)
                    }
                    Text("GGUF → Ollama · .litertlm → LiteRT-LM · compatible safetensors folders → MLX. Other formats connect through their own local server. Adding a file registers its location; Use model starts its loader. Ollama import may copy weights.").font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(4)
                    ForEach(store.modelAssets) { asset in
                        ModelAssetCard(asset: asset).environmentObject(store)
                    }
                    if !store.modelStatus.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text(store.modelStatus).font(.system(size: 11)).foregroundStyle(Palette.mint); Spacer(); if store.modelBusy { Button("Cancel") { store.cancelModelTask() }.font(.system(size: 10)) } }
                            if store.modelBusy {
                                if let began = store.modelStarted { TimelineView(.periodic(from: began, by: 1)) { timeline in Text("\(Int(timeline.date.timeIntervalSince(began)))s · first load can take longer").font(.system(size: 10)).foregroundStyle(Palette.muted) } }
                                if let progress = store.modelProgress { ProgressView(value: progress) } else { ProgressView().controlSize(.small) } }
                        }
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Text("Find your next model").font(.system(size: 19, design: .default)); Spacer(); Image(systemName: "arrow.down.circle").foregroundStyle(Palette.mint) }
                    Text("Local means the model computes on your Mac. The endpoint connects Shiro to its runtime; it is separate from the Linux computer used for work.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Text("Recommended around 4B: Qwen3.5-4B").font(.system(size: 14, weight: .semibold))
                    Text("A strong balance of coding, tools and screenshot understanding. For a strict total below 4B, choose Qwen3.5-2B; the 4B model has about 4.66B total weights including vision. Rankings vary by task.").font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
                    HStack { TextField("Ollama model, e.g. qwen3.5:4b", text: $downloadName).textFieldStyle(.roundedBorder); Button("Download & use") { store.pullModel(downloadName) }.buttonStyle(.borderedProminent).disabled(store.modelBusy || downloadName.isEmpty || store.running) }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        modelChip("qwen3.5:0.8b", "Smallest · ~1.2–1.3 GB · 8 GB RAM target")
                        modelChip("qwen3.5:2b", "Strictly under 4B · ~2.7–3.1 GB · 8–12 GB RAM")
                        modelChip("qwen3.5:4b", "Recommended · ~3.3–4 GB · 16 GB RAM target")
                        modelChip("phi4-mini", "3.8B text alternative · ~2.5 GB · 12 GB RAM")
                        modelChip("qwen3.5:9b", "Stronger tools · ~6.6–7.6 GB · 24 GB RAM target")
                        modelChip("qwen3.8:27b", "Larger coding & agents · ~18 GB · 32–48 GB RAM")
                        modelChip("qwen3.6:35b", "35B total, ~3B active · ~23–24 GB · 48 GB RAM")
                        modelChip("qwen3-coder-next", "Coding specialist · 80B total, 3B active · 64+ GB RAM")
                    }
                    Text("Memory targets are estimates for short contexts, macOS and the 3 GB computer VM. Downloads are not RAM usage. MoE active size does not equal total memory. Smaller models need more supervision on complex tasks.").font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(4)
                    HStack { Link("Small-model evidence", destination: URL(string: "https://huggingface.co/Qwen/Qwen3.5-4B")!); Link("Larger coding model", destination: URL(string: "https://huggingface.co/Qwen/Qwen3.8-27B")!) }.font(.system(size: 11))

                    Link("Browse Ollama’s full model library", destination: URL(string: "https://ollama.com/library")!).font(.system(size: 12))
                    Text("Downloads use Ollama on port 11434. Shiro starts an installed Ollama runtime and selects the completed download. Models stay on your Mac. Sizes are approximate. Small models are easier to run, but complex research and computer tasks need stronger models.").font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(4)
                }
            }
        }.sheet(isPresented: $showFormats) {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Text("Model formats").font(.system(size: 26, design: .default)); Spacer(); Button("Done") { showFormats = false } }
                Text("Shiro accepts any model file or folder. Running it depends on its architecture, tokenizer, and inference runtime. A filename alone cannot establish compatibility.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(ModelFormat.allCases) { format in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(format.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.mint)
                                Text(format.extensions).font(.system(size: 11, design: .monospaced))
                                Text(format.guidance).font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(3)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }.padding(28).frame(width: 650, height: 620).foregroundStyle(Palette.cream).background(Palette.background)
        }
    }
    private func modelChip(_ name: String, _ detail: String) -> some View {
        Button { downloadName = name } label: { VStack(alignment: .leading, spacing: 6) { Text(name).font(.system(size: 11, weight: .medium, design: .monospaced)); Text(detail).font(.system(size: 9)).foregroundStyle(Palette.muted) }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.line)) }.buttonStyle(.plain)
    }
    private func icon(_ provider: Provider) -> String { switch provider { case .openAI: return "sparkle"; case .claude: return "sun.max"; case .gemini: return "staroflife"; case .local: return "cpu" } }
}

private struct ModelAssetCard: View {
    @EnvironmentObject var store: AppStore
    let asset: ModelAsset
    private func binding<T>(_ path: WritableKeyPath<ModelAsset, T>) -> Binding<T> {
        Binding(get: { asset[keyPath: path] }, set: { value in var updated = asset; updated[keyPath: path] = value; store.updateAsset(updated) })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: asset.format == .liteRT ? "sparkles.rectangle.stack" : "externaldrive").foregroundStyle(Palette.mint)
                Text(asset.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer()
                Text(asset.format.title).font(.system(size: 9)).foregroundStyle(Palette.muted)
            }
            Text(asset.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled).lineLimit(2)
            Text(asset.format.guidance).font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(3)
            HStack {
                Picker("Loader", selection: binding(\.loader)) {
                    ForEach(ModelLoader.allCases) { loader in Text(loader.title).tag(loader) }
                }.frame(maxWidth: 280)
                Spacer()
                if asset.loader == .liteRT || asset.loader == .mlx {
                    Button("Restart runtime") { store.activateModel(asset, restart: true) }
                    Button(store.modelRuntimes.executable(asset.loader) == nil ? "Install runtime" : "Update runtime") { store.installModelRuntime(asset.loader) }
                }
                Button("Use model") { store.activateModel(asset) }.buttonStyle(.borderedProminent)
                Button { store.removeAsset(asset.id) } label: { Image(systemName: "minus.circle") }.help("Remove from Shiro's library. The original file stays on disk.")
            }.disabled(store.modelBusy || store.running)
            if asset.loader == .external {
                TextField("Loopback API endpoint", text: binding(\.endpoint)).textFieldStyle(.roundedBorder)
                TextField("Model ID returned by your server", text: binding(\.modelID)).textFieldStyle(.roundedBorder)
                Text("Load this file in your runtime first. Shiro connects to its API; registration does not convert or load this format.").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
        }.padding(16).background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
    }
}

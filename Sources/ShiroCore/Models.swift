import Foundation

public enum Provider: String, CaseIterable, Codable, Identifiable {
    case openAI, claude, gemini, local
    public var id: String { rawValue }
    public var title: String { switch self { case .openAI: return "OpenAI"; case .claude: return "Claude"; case .gemini: return "Gemini"; case .local: return "Local models" } }
    public var endpoint: String { switch self { case .openAI: return "https://api.openai.com/v1"; case .claude: return "https://api.anthropic.com/v1"; case .gemini: return "https://generativelanguage.googleapis.com/v1beta"; case .local: return "http://127.0.0.1:11434/v1" } }
    public var placeholder: String { switch self { case .openAI: return "Choose or enter an OpenAI model"; case .claude: return "Choose or enter a Claude model"; case .gemini: return "Choose or enter a Gemini model"; case .local: return "Choose an installed local model" } }
}

public struct ProviderConfig: Codable, Equatable {
    public var provider: Provider
    public var endpoint: String
    public var model: String
    public var vision: Bool
    public var localRuntime: ModelLoader?
    public var localThinking: Bool?
    public init(provider: Provider, endpoint: String? = nil, model: String = "", vision: Bool = false, localRuntime: ModelLoader? = nil) {
        self.provider = provider; self.endpoint = endpoint ?? provider.endpoint; self.model = model; self.vision = vision; self.localRuntime = localRuntime
    }
}

public struct Entry: Codable, Identifiable {
    public var id = UUID()
    public var role: String
    public var text: String
    public var attachments: [ChatFile]?
    public var date = Date()
    public init(role: String, text: String) { self.role = role; self.text = text }
}

public struct Conversation: Codable, Identifiable {
    public var id = UUID()
    public var title = "New chat"
    public var entries: [Entry] = []
    public var wire: [JSON] = []
    public var wireProvider: String = ""
    public var updated = Date()
    public var botID: UUID?
    public var pendingTask: String?
    public var pendingConfig: ProviderConfig?
    public var draftFiles: [ChatFile]?
    public var inFlightAction: String?
    public var activeObjective: String?
    public var lastRunOutcome: String?
    public init() {}
}

public struct Routine: Codable, Identifiable {
    public var id = UUID()
    public var title: String
    public var prompt: String
    public var minutes: Int
    public var enabled = true
    public var nextRun: Date
    public init(title: String, prompt: String, minutes: Int) {
        self.title = title; self.prompt = prompt; self.minutes = max(15, minutes)
        nextRun = Date().addingTimeInterval(Double(max(15, minutes)) * 60)
    }
}

public struct SavedState: Codable {
    public var conversations: [Conversation] = [Conversation()]
    public var configs: [ProviderConfig] = Provider.allCases.map { ProviderConfig(provider: $0) }
    public var provider: Provider = .local
    public var memory = ""
    public var routines: [Routine] = []
    public var vmName = "shiro-local"
    public var askBeforeActions = true
    public var maxSteps = 24
    public var bots: [Bot] = []
    public var projects: [Project] = []
    public var selectedChatID: UUID?
    public init() { WorkspaceMigration.apply(&self) }
    enum CodingKeys: String, CodingKey { case conversations, configs, provider, memory, routines, vmName, askBeforeActions, maxSteps, bots, projects, selectedChatID }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        conversations = try c.decode([Conversation].self, forKey: .conversations)
        configs = try c.decode([ProviderConfig].self, forKey: .configs)
        provider = try c.decode(Provider.self, forKey: .provider)
        memory = try c.decode(String.self, forKey: .memory)
        routines = try c.decode([Routine].self, forKey: .routines)
        vmName = try c.decode(String.self, forKey: .vmName)
        askBeforeActions = try c.decode(Bool.self, forKey: .askBeforeActions)
        maxSteps = try c.decode(Int.self, forKey: .maxSteps)
        bots = try c.decodeIfPresent([Bot].self, forKey: .bots) ?? []
        projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
        selectedChatID = try c.decodeIfPresent(UUID.self, forKey: .selectedChatID)
        WorkspaceMigration.apply(&self)
    }
}

public struct ToolCall: Identifiable {
    public let id: String
    public let name: String
    public let arguments: JSON
    public let nativeID: String?
    public init(id: String, name: String, arguments: JSON, nativeID: String? = nil) { self.id = id; self.name = name; self.arguments = arguments; self.nativeID = nativeID }
    public var needsApproval: Bool {
        if name == "shell" { return true }
        if name == "computer" { return !["screenshot", "launch"].contains(arguments["action"].string ?? "") }
        if name == "browser" { return ["click", "fill", "key"].contains(arguments["action"].string ?? "") }
        return false
    }
}

public struct ModelReply {
    public let text: String
    public let calls: [ToolCall]
    public let native: [JSON]
}

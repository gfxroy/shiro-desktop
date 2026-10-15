import Foundation

public struct Bot: Codable, Identifiable {
    public var id = UUID()
    public var name: String
    public var instructions = ""
    public var memory = ""
    public var projectID: UUID?
    public var pinned = false
    public var avatarSymbol: String?
    public var avatarColor: String?
    public var animateAvatar: Bool?
    public var avatarKind: String?
    public var avatarModelPath: String?
    public var avatarEyeSize: Double?
    public var avatarEarSize: Double?
    public var avatarFinish: Double?
    public var avatarAccessory: String?
    public var avatarMouseTracking: Bool?
    public var category: String?
    public var avatarTint: String { avatarColor ?? (pinned ? "cream" : ["blue", "purple", "teal", "orange", "pink"][id.uuidString.utf8.reduce(0) { $0 + Int($1) } % 5]) }
    public var avatarFamily: String {
        if let avatarKind { return avatarKind }
        if pinned { return "cat" }
        switch category { case "Research": return "cat"; case "Creative": return "orb"; case "Builder", "Manager": return "robot"; default: return ["cat", "robot", "orb"][id.uuidString.utf8.reduce(0) { $0 + Int($1) } % 3] }
    }
    public init(name: String, pinned: Bool = false) { self.name = name; self.pinned = pinned }
}

public struct Project: Codable, Identifiable {
    public var id = UUID()
    public var name: String
    public var linkedFolder: String?
    public var lastSync: Date?
    public var workspacePath: String { "projects/" + id.uuidString.lowercased() }
    public init(name: String) { self.name = name }
}

public enum WorkspaceMigration {
    public static func apply(_ state: inout SavedState) {
        if state.bots.isEmpty {
            let main = Bot(name: "Shiro bot", pinned: true); state.bots = [main]
            for i in state.conversations.indices { state.conversations[i].botID = main.id }
        }
        for i in state.conversations.indices where !state.bots.contains(where: { $0.id == state.conversations[i].botID }) {
            state.conversations[i].botID = state.bots[0].id
        }
    }
}

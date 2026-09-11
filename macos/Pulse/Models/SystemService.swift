import Foundation

public struct SystemServiceItem: Identifiable, Codable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let description: String
    public let loadState: String
    public let activeState: String
    public let subState: String

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case loadState = "load_state"
        case activeState = "active_state"
        case subState = "sub_state"
    }

    public init(
        name: String,
        description: String = "",
        loadState: String = "loaded",
        activeState: String = "active",
        subState: String = "running"
    ) {
        self.name = name
        self.description = description
        self.loadState = loadState
        self.activeState = activeState
        self.subState = subState
    }

    public var isRunning: Bool {
        activeState.lowercased() == "active" && subState.lowercased() == "running"
    }

    public var isFailed: Bool {
        activeState.lowercased() == "failed" || subState.lowercased() == "failed"
    }
}

public struct ServicesSnapshot: Codable, Equatable, Sendable {
    public let services: [SystemServiceItem]
}

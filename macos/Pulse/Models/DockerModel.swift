import Foundation

public struct DockerContainerItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let image: String
    public let state: String
    public let status: String
    public let createdAt: Int64
    public let ports: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case image
        case state
        case status
        case createdAt = "created_at"
        case ports
    }

    public init(
        id: String,
        name: String,
        image: String,
        state: String,
        status: String,
        createdAt: Int64 = 0,
        ports: [String] = []
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.state = state
        self.status = status
        self.createdAt = createdAt
        self.ports = ports
    }

    public var isRunning: Bool {
        state.lowercased() == "running"
    }

    public var isPaused: Bool {
        state.lowercased() == "paused"
    }

    public var isRestarting: Bool {
        state.lowercased() == "restarting"
    }
}

public struct DockerStatusResponse: Codable, Equatable, Sendable {
    public let available: Bool
    public let version: String?
    public let containers: [DockerContainerItem]

    public init(available: Bool, version: String? = nil, containers: [DockerContainerItem] = []) {
        self.available = available
        self.version = version
        self.containers = containers
    }
}

public struct DockerLogsResponse: Codable, Equatable, Sendable {
    public let containerId: String
    public let logs: String

    enum CodingKeys: String, CodingKey {
        case containerId = "container_id"
        case logs
    }
}

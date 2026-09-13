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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.image = try container.decodeIfPresent(String.self, forKey: .image) ?? ""
        self.state = try container.decodeIfPresent(String.self, forKey: .state) ?? ""
        self.status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        self.createdAt = try container.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
        self.ports = try container.decodeIfPresent([String].self, forKey: .ports) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(image, forKey: .image)
        try container.encode(state, forKey: .state)
        try container.encode(status, forKey: .status)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(ports, forKey: .ports)
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

    public var cleanName: String {
        name.hasPrefix("/") ? String(name.dropFirst()) : name
    }
}

public struct DockerStatusResponse: Codable, Equatable, Sendable {
    public let available: Bool
    public let version: String?
    public let containers: [DockerContainerItem]

    enum CodingKeys: String, CodingKey {
        case available
        case version
        case containers
    }

    public init(available: Bool, version: String? = nil, containers: [DockerContainerItem] = []) {
        self.available = available
        self.version = version
        self.containers = containers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.available = try container.decodeIfPresent(Bool.self, forKey: .available) ?? false
        self.version = try container.decodeIfPresent(String.self, forKey: .version)
        self.containers = try container.decodeIfPresent([DockerContainerItem].self, forKey: .containers) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(available, forKey: .available)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encode(containers, forKey: .containers)
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

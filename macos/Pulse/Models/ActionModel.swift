import Foundation

public struct ActionDefinition: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let destructive: Bool

    public init(id: String, name: String, description: String, destructive: Bool) {
        self.id = id
        self.name = name
        self.description = description
        self.destructive = destructive
    }
}

public struct ActionRequestPayload: Codable, Sendable {
    public let action: String
    public let target: String
    public let timeoutSeconds: Int

    enum CodingKeys: String, CodingKey {
        case action
        case target
        case timeoutSeconds = "timeout_seconds"
    }

    public init(action: String, target: String, timeoutSeconds: Int = 30) {
        self.action = action
        self.target = target
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct ActionResultPayload: Codable, Sendable {
    public let action: String
    public let target: String
    public let status: String // "success", "failed", "timeout"
    public let message: String
    public let durationMs: Int64
    public let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case action
        case target
        case status
        case message
        case durationMs = "duration_ms"
        case timestamp
    }
}

public struct ActionAuditLogItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let serverId: UUID
    public let monitorId: String?
    public let actionName: String
    public let target: String
    public let status: String
    public let message: String
    public let durationMs: Int64
    public let timestamp: Date
    public let actor: String // "User" | "Automation" | "System"
    public var verification: String? // e.g. "Recovered in 4.2s" or "Still Down"

    public init(
        id: UUID = UUID(),
        serverId: UUID,
        monitorId: String? = nil,
        actionName: String,
        target: String,
        status: String,
        message: String,
        durationMs: Int64,
        timestamp: Date = Date(),
        actor: String = "User",
        verification: String? = nil
    ) {
        self.id = id
        self.serverId = serverId
        self.monitorId = monitorId
        self.actionName = actionName
        self.target = target
        self.status = status
        self.message = message
        self.durationMs = durationMs
        self.timestamp = timestamp
        self.actor = actor
        self.verification = verification
    }
}

public struct DatabaseProbeRequest: Codable, Sendable {
    public let type: String
    public let host: String
    public let port: Int
    public let user: String?
    public let password: String?
    public let database: String?
    public let sslMode: String?

    enum CodingKeys: String, CodingKey {
        case type
        case host
        case port
        case user
        case password
        case database
        case sslMode = "ssl_mode"
    }

    public init(type: String, host: String, port: Int, user: String? = nil, password: String? = nil, database: String? = nil, sslMode: String? = nil) {
        self.type = type
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self.database = database
        self.sslMode = sslMode
    }
}

public struct DatabaseProbeResponse: Codable, Sendable {
    public let health: HealthCheckResultItem
    public let metrics: DatabaseMetricsPayload?
}

public struct DatabaseMetricsPayload: Codable, Sendable {
    public let responseTimeMs: Int64
    public let version: String?
    public let metrics: [String: AnyCodable]?
    public let lastChecked: Date

    enum CodingKeys: String, CodingKey {
        case responseTimeMs = "response_time_ms"
        case version
        case metrics
        case lastChecked = "last_checked"
    }
}

// Simple wrapper for flexible JSON dictionary decoding
public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else if let strVal = try? container.decode(String.self) {
            value = strVal
        } else {
            value = ""
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let intVal = value as? Int {
            try container.encode(intVal)
        } else if let dVal = value as? Double {
            try container.encode(dVal)
        } else if let bVal = value as? Bool {
            try container.encode(bVal)
        } else {
            try container.encode(String(describing: value))
        }
    }
}

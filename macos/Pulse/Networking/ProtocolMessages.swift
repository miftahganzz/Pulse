import Foundation

public struct ProtocolEnvelope<T: Codable>: Codable {
    public let type: String
    public let version: Int
    public let timestamp: String
    public let payload: T

    public init(type: String, version: Int = 1, timestamp: String = ISO8601DateFormatter().string(from: Date()), payload: T) {
        self.type = type
        self.version = version
        self.timestamp = timestamp
        self.payload = payload
    }
}

public struct HeartbeatPayload: Codable, Sendable {
    public let agentID: String
    public let uptimeSeconds: Int64
    public let sequence: Int64

    enum CodingKeys: String, CodingKey {
        case agentID = "agent_id"
        case uptimeSeconds = "uptime_seconds"
        case sequence
    }
}

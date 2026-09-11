import Foundation

public struct ServerModel: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var address: String
    public var port: Int
    public var agentID: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        address: String,
        port: Int = 8443,
        agentID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.port = port
        self.agentID = agentID
        self.createdAt = createdAt
    }

    public var hostAndPort: String {
        "\(address):\(port)"
    }
}

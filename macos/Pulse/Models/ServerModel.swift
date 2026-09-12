import Foundation
import SwiftUI

// MARK: - Server Environment

public enum ServerEnvironment: String, Codable, CaseIterable, Identifiable, Sendable {
    case production  = "Production"
    case staging     = "Staging"
    case development = "Development"
    case untagged    = "Other"

    public var id: String { rawValue }

    public var color: Color {
        switch self {
        case .production:  return .red
        case .staging:     return .orange
        case .development: return .blue
        case .untagged:    return .secondary
        }
    }

    public var icon: String {
        switch self {
        case .production:  return "flame.fill"
        case .staging:     return "hammer.fill"
        case .development: return "wrench.and.screwdriver.fill"
        case .untagged:    return "server.rack"
        }
    }

    public var shortLabel: String {
        switch self {
        case .production:  return "prod"
        case .staging:     return "staging"
        case .development: return "dev"
        case .untagged:    return ""
        }
    }
}

// MARK: - ServerModel

public struct ServerModel: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var address: String
    public var port: Int
    public var agentID: String?
    public var createdAt: Date
    public var environment: ServerEnvironment
    public var tags: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        address: String,
        port: Int = 8443,
        agentID: String? = nil,
        createdAt: Date = Date(),
        environment: ServerEnvironment = .untagged,
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.port = port
        self.agentID = agentID
        self.createdAt = createdAt
        self.environment = environment
        self.tags = tags
    }

    public var hostAndPort: String {
        "\(address):\(port)"
    }
}

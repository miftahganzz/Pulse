import Foundation
import SwiftUI

public enum PortExposure: String, Codable, Sendable {
    case `public` = "public"
    case `private` = "private"
    case localhost = "localhost"

    public var displayTitle: String {
        switch self {
        case .public: return "Public (0.0.0.0)"
        case .private: return "Private / VPN"
        case .localhost: return "Localhost Only"
        }
    }

    public var iconName: String {
        switch self {
        case .public: return "globe"
        case .private: return "lock.shield"
        case .localhost: return "laptopcomputer"
        }
    }

    public var badgeColor: Color {
        switch self {
        case .public: return .orange
        case .private: return .blue
        case .localhost: return .green
        }
    }
}

public struct ListeningPortItem: Identifiable, Codable, Sendable {
    public var id: String { "\(protocolType):\(port):\(ip)" }
    public let port: Int
    public let protocolType: String
    public let ip: String
    public let processName: String
    public let pid: Int
    public let exposure: PortExposure
    public let isSensitive: Bool
    public let recommendation: String?

    enum CodingKeys: String, CodingKey {
        case port
        case protocolType = "protocol"
        case ip
        case processName = "process_name"
        case pid
        case exposure
        case isSensitive = "is_sensitive"
        case recommendation
    }

    public init(
        port: Int,
        protocolType: String,
        ip: String,
        processName: String,
        pid: Int,
        exposure: PortExposure,
        isSensitive: Bool = false,
        recommendation: String? = nil
    ) {
        self.port = port
        self.protocolType = protocolType
        self.ip = ip
        self.processName = processName
        self.pid = pid
        self.exposure = exposure
        self.isSensitive = isSensitive
        self.recommendation = recommendation
    }
}

public struct FirewallStatus: Codable, Sendable {
    public let isActive: Bool
    public let type: String
    public let defaultIncoming: String

    enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
        case type
        case defaultIncoming = "default_incoming"
    }

    public init(isActive: Bool, type: String, defaultIncoming: String) {
        self.isActive = isActive
        self.type = type
        self.defaultIncoming = defaultIncoming
    }
}

public struct SecuritySnapshot: Codable, Sendable {
    public let ports: [ListeningPortItem]
    public let firewall: FirewallStatus
    public let publicCount: Int
    public let sensitiveCount: Int

    enum CodingKeys: String, CodingKey {
        case ports
        case firewall
        case publicCount = "public_count"
        case sensitiveCount = "sensitive_count"
    }

    public init(ports: [ListeningPortItem], firewall: FirewallStatus, publicCount: Int, sensitiveCount: Int) {
        self.ports = ports
        self.firewall = firewall
        self.publicCount = publicCount
        self.sensitiveCount = sensitiveCount
    }
}

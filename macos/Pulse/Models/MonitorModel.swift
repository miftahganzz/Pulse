import Foundation
import SwiftUI

public enum MonitorType: String, Codable, CaseIterable, Sendable {
    case systemd = "systemd"
    case docker = "docker"
    case pm2 = "pm2"
    case process = "process"
    case http = "http"
    case tcp = "tcp"
    case postgres = "postgres"
    case redis = "redis"
    case mysql = "mysql"
    case mongodb = "mongodb"
    case nginx = "nginx"
    case caddy = "caddy"
    case cloudflared = "cloudflared"
    case custom = "custom"

    public var displayName: String {
        switch self {
        case .systemd: return "Systemd"
        case .docker: return "Docker"
        case .pm2: return "PM2"
        case .process: return "Process"
        case .http: return "HTTP Probe"
        case .tcp: return "TCP Probe"
        case .postgres: return "PostgreSQL"
        case .redis: return "Redis"
        case .mysql: return "MySQL / MariaDB"
        case .mongodb: return "MongoDB"
        case .nginx: return "Nginx"
        case .caddy: return "Caddy"
        case .cloudflared: return "Cloudflare Tunnel"
        case .custom: return "Custom Check"
        }
    }

    public var iconName: String {
        switch self {
        case .systemd: return "gearshape.2"
        case .docker: return "shippingbox"
        case .pm2: return "hexagon"
        case .process: return "cpu"
        case .http: return "globe"
        case .tcp: return "network"
        case .postgres: return "cylinder"
        case .redis: return "bolt.horizontal"
        case .mysql: return "cylinder.split.1x2"
        case .mongodb: return "leaf"
        case .nginx: return "server.rack"
        case .caddy: return "shield.checkered"
        case .cloudflared: return "cloud"
        case .custom: return "terminal"
        }
    }

    public var sfSymbol: String {
        return iconName
    }
}

public enum MonitorStatus: String, Codable, Sendable {
    case healthy = "healthy"
    case warning = "warning"
    case critical = "critical"
    case down = "down"
    case unknown = "unknown"

    public var displayName: String {
        switch self {
        case .healthy: return "Healthy"
        case .warning: return "Warning"
        case .critical: return "Critical"
        case .down: return "Down"
        case .unknown: return "Unknown"
        }
    }

    public var color: Color {
        switch self {
        case .healthy: return .green
        case .warning: return .orange
        case .critical: return .red
        case .down: return .red
        case .unknown: return .secondary
        }
    }

    public var iconName: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        case .down: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

public struct MonitorItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var serverId: UUID
    public var name: String
    public var type: MonitorType
    public var target: String
    public var status: MonitorStatus
    public var latencyMs: Int64?
    public var message: String?
    public var lastChecked: Date?
    public var isEnabled: Bool
    public var isIgnored: Bool

    public init(
        id: String = UUID().uuidString,
        serverId: UUID,
        name: String,
        type: MonitorType,
        target: String,
        status: MonitorStatus = .unknown,
        latencyMs: Int64? = nil,
        message: String? = nil,
        lastChecked: Date? = nil,
        isEnabled: Bool = true,
        isIgnored: Bool = false
    ) {
        self.id = id
        self.serverId = serverId
        self.name = name
        self.type = type
        self.target = target
        self.status = status
        self.latencyMs = latencyMs
        self.message = message
        self.lastChecked = lastChecked
        self.isEnabled = isEnabled
        self.isIgnored = isIgnored
    }
}

public struct DiscoveredServiceItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let providerType: String
    public let name: String
    public let description: String?
    public let status: String
    public let metadata: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id
        case providerType = "provider_type"
        case name
        case description
        case status
        case metadata
    }
}

public struct DiscoveryResultPayload: Codable, Sendable {
    public let timestamp: Date
    public let services: [DiscoveredServiceItem]
}

public struct HealthCheckResultItem: Identifiable, Codable, Sendable {
    public let id: String
    public let status: String
    public let message: String
    public let latencyMs: Int64?
    public let lastChecked: Date

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case message
        case latencyMs = "latency_ms"
        case lastChecked = "last_checked"
    }
}

public struct MonitorHealthCheckRequest: Codable, Sendable {
    public let id: String
    public let name: String
    public let type: String
    public let target: String
    public let expectedBody: String?
    public let expectedCode: Int?
    public let expectedOutput: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case target
        case expectedBody = "expected_body"
        case expectedCode = "expected_code"
        case expectedOutput = "expected_output"
    }

    public init(
        id: String,
        name: String,
        type: String,
        target: String,
        expectedBody: String? = nil,
        expectedCode: Int? = nil,
        expectedOutput: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.target = target
        self.expectedBody = expectedBody
        self.expectedCode = expectedCode
        self.expectedOutput = expectedOutput
    }
}

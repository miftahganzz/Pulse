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

public struct LogEntryMessage: Codable, Sendable, Identifiable {
    public var id: String { "\(timestamp.timeIntervalSince1970)-\(line.hashValue)" }
    public let timestamp: Date
    public let line: String
    public let stream: String // "stdout" or "stderr"

    enum CodingKeys: String, CodingKey {
        case timestamp
        case line
        case stream
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        line = try container.decode(String.self, forKey: .line)
        stream = try container.decodeIfPresent(String.self, forKey: .stream) ?? "stdout"
        if let dateStr = try? container.decode(String.self, forKey: .timestamp) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = formatter.date(from: dateStr) {
                timestamp = parsed
            } else {
                formatter.formatOptions = [.withInternetDateTime]
                timestamp = formatter.date(from: dateStr) ?? Date()
            }
        } else {
            timestamp = Date()
        }
    }
}

public struct DirectoryUsageItem: Codable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let sizeBytes: Int64
    public let sizeHuman: String
    public let category: String
    public let reclaimable: Bool

    enum CodingKeys: String, CodingKey {
        case path
        case sizeBytes = "size_bytes"
        case sizeHuman = "size_human"
        case category
        case reclaimable
    }
}

public struct ReclaimableSummaryItem: Codable, Sendable {
    public let journalLogsBytes: Int64
    public let journalLogsHuman: String
    public let dockerCacheBytes: Int64
    public let dockerCacheHuman: String
    public let aptCacheBytes: Int64
    public let aptCacheHuman: String
    public let totalPotentialBytes: Int64
    public let totalHuman: String

    enum CodingKeys: String, CodingKey {
        case journalLogsBytes = "journal_logs_bytes"
        case journalLogsHuman = "journal_logs_human"
        case dockerCacheBytes = "docker_cache_bytes"
        case dockerCacheHuman = "docker_cache_human"
        case aptCacheBytes = "apt_cache_bytes"
        case aptCacheHuman = "apt_cache_human"
        case totalPotentialBytes = "total_potential_bytes"
        case totalHuman = "total_human"
    }
}

public struct StorageAnalysis: Codable, Sendable {
    public let directories: [DirectoryUsageItem]
    public let reclaimable: ReclaimableSummaryItem
}

public struct TelegramConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var botToken: String
    public var chatIDs: [String]
    public var notifyOnWarning: Bool
    public var notifyOnCritical: Bool
    public var notifyOnRecovery: Bool

    enum CodingKeys: String, CodingKey {
        case enabled
        case botToken = "bot_token"
        case chatIDs = "chat_ids"
        case notifyOnWarning = "notify_on_warning"
        case notifyOnCritical = "notify_on_critical"
        case notifyOnRecovery = "notify_on_recovery"
    }

    public init(
        enabled: Bool = false,
        botToken: String = "",
        chatIDs: [String] = [],
        notifyOnWarning: Bool = true,
        notifyOnCritical: Bool = true,
        notifyOnRecovery: Bool = true
    ) {
        self.enabled = enabled
        self.botToken = botToken
        self.chatIDs = chatIDs
        self.notifyOnWarning = notifyOnWarning
        self.notifyOnCritical = notifyOnCritical
        self.notifyOnRecovery = notifyOnRecovery
    }
}


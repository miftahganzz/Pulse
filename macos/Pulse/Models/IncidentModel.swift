import Foundation
import SwiftUI

public enum IncidentSeverity: String, Codable, CaseIterable, Sendable {
    case info = "info"
    case warning = "warning"
    case critical = "critical"

    public var displayName: String {
        switch self {
        case .info: return "Info"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }

    public var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }

    public var iconName: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }

    public var sfSymbol: String {
        return iconName
    }
}

public enum IncidentStatus: String, Codable, CaseIterable, Sendable {
    case ongoing = "ongoing"
    case recovering = "recovering"
    case resolved = "resolved"

    public var displayName: String {
        switch self {
        case .ongoing: return "Ongoing"
        case .recovering: return "Recovering"
        case .resolved: return "Resolved"
        }
    }

    public var color: Color {
        switch self {
        case .ongoing: return .red
        case .recovering: return .orange
        case .resolved: return .green
        }
    }
}

public struct IncidentItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let serverId: UUID
    public let monitorId: String?
    public let title: String
    public let target: String
    public var severity: IncidentSeverity
    public var status: IncidentStatus
    public let startedAt: Date
    public var detectedAt: Date
    public var recoveredAt: Date?
    public var reason: String
    public var consecutiveFailures: Int
    public var rootCauseAnalysis: RootCauseAnalysis?

    public init(
        id: UUID = UUID(),
        serverId: UUID,
        monitorId: String? = nil,
        title: String,
        target: String,
        severity: IncidentSeverity = .critical,
        status: IncidentStatus = .ongoing,
        startedAt: Date = Date(),
        detectedAt: Date = Date(),
        recoveredAt: Date? = nil,
        reason: String,
        consecutiveFailures: Int = 1,
        rootCauseAnalysis: RootCauseAnalysis? = nil
    ) {
        self.id = id
        self.serverId = serverId
        self.monitorId = monitorId
        self.title = title
        self.target = target
        self.severity = severity
        self.status = status
        self.startedAt = startedAt
        self.detectedAt = detectedAt
        self.recoveredAt = recoveredAt
        self.reason = reason
        self.consecutiveFailures = consecutiveFailures
        self.rootCauseAnalysis = rootCauseAnalysis
    }

    public var durationSeconds: TimeInterval {
        let end = recoveredAt ?? Date()
        return max(0, end.timeIntervalSince(startedAt))
    }

    public var formattedDuration: String {
        let secs = Int(durationSeconds)
        if secs < 60 {
            return "\(secs)s"
        } else if secs < 3600 {
            let m = secs / 60
            let s = secs % 60
            return "\(m)m \(s)s"
        } else {
            let h = secs / 3600
            let m = (secs % 3600) / 60
            return "\(h)h \(m)m"
        }
    }
}

public struct IncidentAlertPolicy: Codable, Equatable, Sendable {
    public var consecutiveFailuresThreshold: Int
    public var consecutiveSuccessThreshold: Int
    public var notifyOnWarning: Bool
    public var notifyOnCritical: Bool
    public var notifyOnRecovery: Bool
    public var isMuted: Bool
    public var mutedUntil: Date?

    public init(
        consecutiveFailuresThreshold: Int = 2,
        consecutiveSuccessThreshold: Int = 2,
        notifyOnWarning: Bool = true,
        notifyOnCritical: Bool = true,
        notifyOnRecovery: Bool = true,
        isMuted: Bool = false,
        mutedUntil: Date? = nil
    ) {
        self.consecutiveFailuresThreshold = consecutiveFailuresThreshold
        self.consecutiveSuccessThreshold = consecutiveSuccessThreshold
        self.notifyOnWarning = notifyOnWarning
        self.notifyOnCritical = notifyOnCritical
        self.notifyOnRecovery = notifyOnRecovery
        self.isMuted = isMuted
        self.mutedUntil = mutedUntil
    }

    public var isEffectivelyMuted: Bool {
        if isMuted { return true }
        if let until = mutedUntil, until > Date() { return true }
        return false
    }
}

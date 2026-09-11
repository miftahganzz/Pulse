import Foundation
import SwiftUI

public enum RiskLevel: String, Codable, CaseIterable, Sendable {
    case low = "low"
    case medium = "medium"
    case high = "high"

    public var displayName: String {
        switch self {
        case .low: return "Low Risk"
        case .medium: return "Medium Risk"
        case .high: return "High Risk"
        }
    }

    public var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }

    public var sfSymbol: String {
        switch self {
        case .low: return "shield.lefthalf.filled"
        case .medium: return "exclamationmark.shield.fill"
        case .high: return "lock.shield.fill"
        }
    }
}

public enum ApprovalMode: String, Codable, CaseIterable, Sendable {
    case manual = "manual"
    case approved = "approved"
    case automatic = "automatic"

    public var displayName: String {
        switch self {
        case .manual: return "Manual (Suggest Only)"
        case .approved: return "Prompt Approval"
        case .automatic: return "Fully Automatic"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .manual: return "hand.raised.fill"
        case .approved: return "bell.badge.fill"
        case .automatic: return "bolt.shield.fill"
        }
    }
}

public struct RemediationPolicy: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let serverId: UUID
    public let monitorId: String
    public var actionId: String // e.g. "docker.restart", "systemd.restart", "pm2.reload"
    public var approvalMode: ApprovalMode
    public var maxAttempts: Int
    public var cooldownSeconds: TimeInterval
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        serverId: UUID,
        monitorId: String,
        actionId: String,
        approvalMode: ApprovalMode = .manual,
        maxAttempts: Int = 3,
        cooldownSeconds: TimeInterval = 900, // 15 minutes default
        enabled: Bool = true
    ) {
        self.id = id
        self.serverId = serverId
        self.monitorId = monitorId
        self.actionId = actionId
        self.approvalMode = approvalMode
        self.maxAttempts = maxAttempts
        self.cooldownSeconds = cooldownSeconds
        self.enabled = enabled
    }
}

public struct CircuitBreakerState: Codable, Equatable, Sendable {
    public var failureCount: Int
    public var isTripped: Bool
    public var trippedAt: Date?
    public var lastAttemptAt: Date?

    public init(
        failureCount: Int = 0,
        isTripped: Bool = false,
        trippedAt: Date? = nil,
        lastAttemptAt: Date? = nil
    ) {
        self.failureCount = failureCount
        self.isTripped = isTripped
        self.trippedAt = trippedAt
        self.lastAttemptAt = lastAttemptAt
    }
}

public struct ActionPreviewDetails: Identifiable, Equatable, Sendable {
    public var id: String { "\(actionId):\(targetName)" }
    public let actionId: String
    public let actionName: String
    public let targetName: String
    public let serverName: String
    public let reason: String
    public let expectedImpact: String
    public let riskLevel: RiskLevel
    public let isReversible: Bool
    public let monitorId: String?

    public init(
        actionId: String,
        actionName: String,
        targetName: String,
        serverName: String,
        reason: String,
        expectedImpact: String,
        riskLevel: RiskLevel,
        isReversible: Bool,
        monitorId: String? = nil
    ) {
        self.actionId = actionId
        self.actionName = actionName
        self.targetName = targetName
        self.serverName = serverName
        self.reason = reason
        self.expectedImpact = expectedImpact
        self.riskLevel = riskLevel
        self.isReversible = isReversible
        self.monitorId = monitorId
    }
}

public enum VerificationStatus: Equatable, Sendable {
    case pending
    case verifying(step: Int)
    case succeeded(duration: TimeInterval)
    case failedStillDown(reason: String)

    public var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .verifying(let s): return "Verifying probe (\(s)/3)..."
        case .succeeded(let d): return String(format: "Recovered in %.1fs", d)
        case .failedStillDown(let r): return "Failed: \(r)"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .pending: return "clock"
        case .verifying: return "arrow.clockwise"
        case .succeeded: return "checkmark.seal.fill"
        case .failedStillDown: return "xmark.octagon.fill"
        }
    }

    public var color: Color {
        switch self {
        case .pending: return .secondary
        case .verifying: return .orange
        case .succeeded: return .green
        case .failedStillDown: return .red
        }
    }
}

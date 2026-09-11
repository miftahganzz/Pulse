import Foundation
import SwiftUI

public enum ConfidenceLevel: String, Codable, CaseIterable, Sendable {
    case high = "high"
    case medium = "medium"
    case low = "low"
    case unknown = "unknown"

    public var displayName: String {
        switch self {
        case .high: return "High Confidence"
        case .medium: return "Medium Confidence"
        case .low: return "Low Confidence"
        case .unknown: return "Uncertain"
        }
    }

    public var color: Color {
        switch self {
        case .high: return .red
        case .medium: return .orange
        case .low: return .yellow
        case .unknown: return .secondary
        }
    }

    public var sfSymbol: String {
        switch self {
        case .high: return "checkmark.seal.fill"
        case .medium: return "exclamationmark.circle.fill"
        case .low: return "questionmark.circle.fill"
        case .unknown: return "circle.dotted"
        }
    }
}

public enum IncidentEventType: String, Codable, Sendable {
    case failure = "failure"
    case degraded = "degraded"
    case recovered = "recovered"
    case anomalyDetected = "anomaly_detected"

    public var sfSymbol: String {
        switch self {
        case .failure: return "xmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .recovered: return "checkmark.circle.fill"
        case .anomalyDetected: return "waveform.path.ecg"
        }
    }

    public var color: Color {
        switch self {
        case .failure: return .red
        case .degraded: return .orange
        case .recovered: return .green
        case .anomalyDetected: return .purple
        }
    }
}

public struct IncidentTimelineEvent: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let serviceName: String
    public let monitorId: String?
    public let eventType: IncidentEventType
    public let detail: String
    public let isRootCauseCandidate: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        serviceName: String,
        monitorId: String? = nil,
        eventType: IncidentEventType,
        detail: String,
        isRootCauseCandidate: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.serviceName = serviceName
        self.monitorId = monitorId
        self.eventType = eventType
        self.detail = detail
        self.isRootCauseCandidate = isRootCauseCandidate
    }
}

public struct RootCauseAnalysis: Codable, Equatable, Sendable {
    public let suspectedRootCauseMonitorId: String?
    public let suspectedRootCauseName: String
    public let confidenceScore: Int // 0 - 100
    public let confidenceLevel: ConfidenceLevel
    public let blastRadiusCount: Int
    public let affectedServiceNames: [String]
    public let evidenceList: [String]
    public let timelineEvents: [IncidentTimelineEvent]

    public init(
        suspectedRootCauseMonitorId: String?,
        suspectedRootCauseName: String,
        confidenceScore: Int,
        confidenceLevel: ConfidenceLevel,
        blastRadiusCount: Int,
        affectedServiceNames: [String],
        evidenceList: [String],
        timelineEvents: [IncidentTimelineEvent]
    ) {
        self.suspectedRootCauseMonitorId = suspectedRootCauseMonitorId
        self.suspectedRootCauseName = suspectedRootCauseName
        self.confidenceScore = confidenceScore
        self.confidenceLevel = confidenceLevel
        self.blastRadiusCount = blastRadiusCount
        self.affectedServiceNames = affectedServiceNames
        self.evidenceList = evidenceList
        self.timelineEvents = timelineEvents
    }
}

public struct SuggestedDependencyDTO: Identifiable, Codable, Equatable, Sendable {
    public var id: String { "\(sourceId)->\(targetId)" }
    public let sourceId: String
    public let sourceName: String
    public let targetId: String
    public let targetName: String
    public let dependencyType: String
    public let reason: String
    public let port: Int
    public let confidence: Int

    enum CodingKeys: String, CodingKey {
        case sourceId = "source_id"
        case sourceName = "source_name"
        case targetId = "target_id"
        case targetName = "target_name"
        case dependencyType = "dependency_type"
        case reason
        case port
        case confidence
    }
}

public struct MetricAnomaly: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let metricName: String
    public let currentValue: Double
    public let baselineMean: Double
    public let standardDeviation: Double
    public let zScore: Double
    public let timestamp: Date
    public let explanation: String

    public var isSevere: Bool {
        abs(zScore) >= 3.0
    }
}

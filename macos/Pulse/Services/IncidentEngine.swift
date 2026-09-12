import Foundation

public final class IncidentEngine {
    private let serverId: UUID
    private var serverName: String
    private var policy: IncidentAlertPolicy
    private var failureCounters: [String: Int] = [:]
    private var successCounters: [String: Int] = [:]
    private var isServerUnreachable = false

    public init(serverId: UUID, serverName: String, policy: IncidentAlertPolicy) {
        self.serverId = serverId
        self.serverName = serverName
        self.policy = policy
    }

    public func updatePolicy(_ newPolicy: IncidentAlertPolicy) {
        self.policy = newPolicy
    }

    public func updateServerName(_ name: String) {
        self.serverName = name
    }

    // MARK: - Server-Level Outage Evaluation
    public func handleServerConnectionState(
        isConnected: Bool,
        isOffline: Bool,
        existingIncidents: inout [IncidentItem]
    ) -> IncidentItem? {
        let serverTarget = "server.connection"

        if isOffline {
            failureCounters[serverTarget, default: 0] += 1
            successCounters[serverTarget] = 0

            // If threshold reached and no active incident for server
            if failureCounters[serverTarget, default: 0] >= policy.consecutiveFailuresThreshold {
                if !isServerUnreachable {
                    isServerUnreachable = true
                    let incident = IncidentItem(
                        serverId: serverId,
                        monitorId: nil,
                        title: "Server Unreachable",
                        target: serverName,
                        severity: .critical,
                        status: .ongoing,
                        reason: "Connection to agent timed out or lost",
                        consecutiveFailures: failureCounters[serverTarget, default: 0]
                    )
                    existingIncidents.insert(incident, at: 0)

                    if !policy.isEffectivelyMuted && policy.notifyOnCritical {
                        NotificationService.shared.sendAlert(
                            title: "Server Unreachable: \(serverName)",
                            body: "Pulse lost connection to \(serverName). All services affected.",
                            identifier: "incident.server.\(serverId.uuidString)"
                        )
                    }
                    return incident
                }
            }
        } else if isConnected {
            successCounters[serverTarget, default: 0] += 1
            failureCounters[serverTarget] = 0

            if isServerUnreachable && successCounters[serverTarget, default: 0] >= policy.consecutiveSuccessThreshold {
                isServerUnreachable = false
                if let idx = existingIncidents.firstIndex(where: { $0.target == serverName && $0.status != .resolved }) {
                    existingIncidents[idx].status = .resolved
                    existingIncidents[idx].recoveredAt = Date()

                    let duration = existingIncidents[idx].formattedDuration
                    if !policy.isEffectivelyMuted && policy.notifyOnRecovery {
                        NotificationService.shared.sendAlert(
                            title: "🟢 \(serverName) Recovered",
                            body: "Connection restored to \(serverName). Downtime: \(duration)",
                            identifier: "incident.server.recovered.\(serverId.uuidString)"
                        )
                    }
                    return existingIncidents[idx]
                }
            }
        }
        return nil
    }

    // MARK: - Monitor Health Evaluation
    public func evaluateMonitorHealth(
        monitor: MonitorItem,
        existingIncidents: inout [IncidentItem]
    ) -> IncidentItem? {
        // If whole server is unreachable, group into server outage, avoid separate spam
        if isServerUnreachable {
            return nil
        }

        let key = monitor.id
        let isBad = monitor.status == .down || monitor.status == .critical || monitor.status == .warning

        if isBad {
            failureCounters[key, default: 0] += 1
            successCounters[key] = 0

            let threshold = policy.consecutiveFailuresThreshold
            if failureCounters[key, default: 0] >= threshold {
                // Check if already active incident exists
                if let idx = existingIncidents.firstIndex(where: { $0.monitorId == monitor.id && $0.status != .resolved }) {
                    // Update existing incident
                    existingIncidents[idx].consecutiveFailures = failureCounters[key, default: 0]
                    existingIncidents[idx].reason = monitor.message ?? "Health check reported \(monitor.status.rawValue)"
                    return existingIncidents[idx]
                } else {
                    // Create new incident
                    let severity: IncidentSeverity = (monitor.status == .warning) ? .warning : .critical
                    let incident = IncidentItem(
                        serverId: serverId,
                        monitorId: monitor.id,
                        title: monitor.name,
                        target: monitor.target,
                        severity: severity,
                        status: .ongoing,
                        reason: monitor.message ?? "Service status: \(monitor.status.rawValue)",
                        consecutiveFailures: failureCounters[key, default: 0]
                    )
                    existingIncidents.insert(incident, at: 0)

                    // Post notification with flapping suppression
                    if !policy.isEffectivelyMuted {
                        if (severity == .critical && policy.notifyOnCritical) || (severity == .warning && policy.notifyOnWarning) {
                            NotificationService.shared.sendAlert(
                                title: "\(monitor.name) is \(monitor.status.displayName)",
                                body: "\(serverName) · \(monitor.message ?? monitor.target)",
                                identifier: "incident.\(monitor.id)"
                            )
                        }
                    }
                    return incident
                }
            }
        } else if monitor.status == .healthy {
            successCounters[key, default: 0] += 1
            failureCounters[key] = 0

            let recoveryThreshold = policy.consecutiveSuccessThreshold
            if successCounters[key, default: 0] >= recoveryThreshold {
                if let idx = existingIncidents.firstIndex(where: { $0.monitorId == monitor.id && $0.status != .resolved }) {
                    existingIncidents[idx].status = .resolved
                    existingIncidents[idx].recoveredAt = Date()

                    let duration = existingIncidents[idx].formattedDuration
                    if !policy.isEffectivelyMuted && policy.notifyOnRecovery {
                        NotificationService.shared.sendAlert(
                            title: "🟢 \(monitor.name) Recovered",
                            body: "\(serverName) · Downtime \(duration)",
                            identifier: "incident.recovered.\(monitor.id)"
                        )
                    }
                    return existingIncidents[idx]
                }
            }
        }
        return nil
    }
}

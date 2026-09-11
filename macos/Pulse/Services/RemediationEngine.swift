import Foundation

/// Central Remediation Engine governing safety gates, cooldowns,
/// circuit breakers, and post-action health verification pipelines.
public final class RemediationEngine {
    public static let shared = RemediationEngine()

    private let queue = DispatchQueue(label: "com.pulse.remediation", qos: .userInitiated)

    public init() {}

    // MARK: - Safety Gate Check
    /// Evaluates whether an automated remediation action is currently permitted to run.
    /// Returns (allowed: Bool, reason: String?)
    public func canExecuteRemediation(
        for monitorId: String,
        serverId: UUID,
        policy: RemediationPolicy?,
        isMaintenanceActive: Bool,
        isServerReachable: Bool
    ) -> (allowed: Bool, reason: String?) {
        guard let policy = policy, policy.enabled else {
            return (false, "Auto-remediation is disabled for this service")
        }

        guard isServerReachable else {
            return (false, "Server is currently unreachable")
        }

        if isMaintenanceActive {
            return (false, "Server is in Maintenance Mode / Deployment Window")
        }

        let breakers = RemediationStore.loadBreakers(forServerId: serverId)
        if let state = breakers[monitorId] {
            // 1. Check Circuit Breaker
            if state.isTripped {
                return (false, "Circuit breaker tripped: Maximum consecutive failures reached (3/3). Manual intervention required.")
            }

            // 2. Check Cooldown
            if let last = state.lastAttemptAt {
                let elapsed = Date().timeIntervalSince(last)
                if elapsed < policy.cooldownSeconds {
                    let remaining = Int(policy.cooldownSeconds - elapsed)
                    return (false, "Cooldown active: \(remaining)s remaining before next attempt")
                }
            }
        }

        return (true, nil)
    }

    // MARK: - Circuit Breaker Management
    /// Records an execution attempt result to update the circuit breaker state.
    public func recordExecutionResult(
        monitorId: String,
        serverId: UUID,
        success: Bool,
        policy: RemediationPolicy
    ) {
        var breakers = RemediationStore.loadBreakers(forServerId: serverId)
        var state = breakers[monitorId] ?? CircuitBreakerState()

        state.lastAttemptAt = Date()

        if success {
            // Reset failure count on success
            state.failureCount = 0
            state.isTripped = false
            state.trippedAt = nil
        } else {
            state.failureCount += 1
            if state.failureCount >= policy.maxAttempts {
                state.isTripped = true
                state.trippedAt = Date()
            }
        }

        breakers[monitorId] = state
        RemediationStore.saveBreakers(breakers, forServerId: serverId)
    }

    // MARK: - Action Preview Builder
    /// Generates structured preview details with risk and impact assessments.
    public func buildActionPreview(
        actionId: String,
        targetName: String,
        serverName: String,
        monitorId: String? = nil,
        currentStatus: MonitorStatus = .down
    ) -> ActionPreviewDetails {
        let act = actionId.lowercased()
        let name: String
        let impact: String
        let risk: RiskLevel
        let reversible: Bool
        let reason = currentStatus == .healthy
            ? "Manual maintenance requested by operator."
            : "Service is currently \(currentStatus.displayName). Recommended restart to clear lock or crash state."

        if act.contains("restart") {
            name = "Restart Service"
            impact = "Connections to \(targetName) will temporarily drop (~2-10s) while the process reboots."
            risk = .low
            reversible = true
        } else if act.contains("reload") {
            name = "Graceful Reload"
            impact = "Worker processes will reload sequentially with zero anticipated downtime."
            risk = .low
            reversible = true
        } else if act.contains("stop") {
            name = "Stop Service"
            impact = "\(targetName) will be halted immediately. Dependent APIs will be unable to connect until started."
            risk = .medium
            reversible = true
        } else if act.contains("start") {
            name = "Start Service"
            impact = "Process will initialize and begin listening on assigned ports."
            risk = .low
            reversible = true
        } else {
            name = actionId.capitalized
            impact = "Standard service control command."
            risk = .medium
            reversible = false
        }

        return ActionPreviewDetails(
            actionId: actionId,
            actionName: name,
            targetName: targetName,
            serverName: serverName,
            reason: reason,
            expectedImpact: impact,
            riskLevel: risk,
            isReversible: reversible,
            monitorId: monitorId
        )
    }
}

import XCTest
@testable import Pulse

final class RemediationTests: XCTestCase {
    let serverId = UUID()
    let monitorId = "postgres-prod"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "pulse.remediation.policies.\(serverId.uuidString)")
        UserDefaults.standard.removeObject(forKey: "pulse.remediation.breakers.\(serverId.uuidString)")
    }

    func testPolicyPersistenceInStore() {
        let policy = RemediationPolicy(
            serverId: serverId,
            monitorId: monitorId,
            actionId: "docker.restart",
            approvalMode: .automatic,
            maxAttempts: 3,
            cooldownSeconds: 600,
            enabled: true
        )

        RemediationStore.savePolicy(policy, forServerId: serverId)

        let loaded = RemediationStore.loadPolicies(forServerId: serverId)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.monitorId, monitorId)
        XCTAssertEqual(loaded.first?.actionId, "docker.restart")
        XCTAssertEqual(loaded.first?.approvalMode, .automatic)
        XCTAssertEqual(loaded.first?.maxAttempts, 3)
    }

    func testSafetyGatePassesWhenHealthyAndEligible() {
        let policy = RemediationPolicy(
            serverId: serverId,
            monitorId: monitorId,
            actionId: "systemd.restart",
            approvalMode: .automatic,
            maxAttempts: 3,
            cooldownSeconds: 300,
            enabled: true
        )

        let gate = RemediationEngine.shared.canExecuteRemediation(
            for: monitorId,
            serverId: serverId,
            policy: policy,
            isMaintenanceActive: false,
            isServerReachable: true
        )

        XCTAssertTrue(gate.allowed)
        XCTAssertNil(gate.reason)
    }

    func testSafetyGateBlocksOnMaintenanceMode() {
        let policy = RemediationPolicy(
            serverId: serverId,
            monitorId: monitorId,
            actionId: "systemd.restart",
            approvalMode: .automatic,
            enabled: true
        )

        let gate = RemediationEngine.shared.canExecuteRemediation(
            for: monitorId,
            serverId: serverId,
            policy: policy,
            isMaintenanceActive: true, // Maintenance or Deployment active
            isServerReachable: true
        )

        XCTAssertFalse(gate.allowed)
        XCTAssertTrue(gate.reason?.contains("Maintenance Mode") ?? false)
    }

    func testSafetyGateBlocksOnCooldown() {
        let policy = RemediationPolicy(
            serverId: serverId,
            monitorId: monitorId,
            actionId: "pm2.reload",
            approvalMode: .automatic,
            cooldownSeconds: 600,
            enabled: true
        )

        // Record a failure 100s ago
        var breakers: [String: CircuitBreakerState] = [:]
        breakers[monitorId] = CircuitBreakerState(
            failureCount: 1,
            isTripped: false,
            trippedAt: nil,
            lastAttemptAt: Date().addingTimeInterval(-100)
        )
        RemediationStore.saveBreakers(breakers, forServerId: serverId)

        let gate = RemediationEngine.shared.canExecuteRemediation(
            for: monitorId,
            serverId: serverId,
            policy: policy,
            isMaintenanceActive: false,
            isServerReachable: true
        )

        XCTAssertFalse(gate.allowed)
        XCTAssertTrue(gate.reason?.contains("Cooldown active") ?? false)
    }

    func testCircuitBreakerTripsAfterMaxAttempts() {
        let policy = RemediationPolicy(
            serverId: serverId,
            monitorId: monitorId,
            actionId: "docker.restart",
            approvalMode: .automatic,
            maxAttempts: 3,
            enabled: true
        )

        // Record 1st failure
        RemediationEngine.shared.recordExecutionResult(
            monitorId: monitorId,
            serverId: serverId,
            success: false,
            policy: policy
        )
        var breakers = RemediationStore.loadBreakers(forServerId: serverId)
        XCTAssertEqual(breakers[monitorId]?.failureCount, 1)
        XCTAssertFalse(breakers[monitorId]?.isTripped ?? true)

        // Record 2nd failure
        RemediationEngine.shared.recordExecutionResult(
            monitorId: monitorId,
            serverId: serverId,
            success: false,
            policy: policy
        )
        breakers = RemediationStore.loadBreakers(forServerId: serverId)
        XCTAssertEqual(breakers[monitorId]?.failureCount, 2)
        XCTAssertFalse(breakers[monitorId]?.isTripped ?? true)

        // Record 3rd failure -> Circuit breaker trips!
        RemediationEngine.shared.recordExecutionResult(
            monitorId: monitorId,
            serverId: serverId,
            success: false,
            policy: policy
        )
        breakers = RemediationStore.loadBreakers(forServerId: serverId)
        XCTAssertEqual(breakers[monitorId]?.failureCount, 3)
        XCTAssertTrue(breakers[monitorId]?.isTripped ?? false)

        // Subsequent safety gate checks must block execution
        let gate = RemediationEngine.shared.canExecuteRemediation(
            for: monitorId,
            serverId: serverId,
            policy: policy,
            isMaintenanceActive: false,
            isServerReachable: true
        )
        XCTAssertFalse(gate.allowed)
        XCTAssertTrue(gate.reason?.contains("Circuit breaker tripped") ?? false)
    }

    func testActionPreviewGeneration() {
        let preview = RemediationEngine.shared.buildActionPreview(
            actionId: "docker.restart",
            targetName: "movnix-db",
            serverName: "VPS Jakarta",
            monitorId: monitorId,
            currentStatus: .down
        )

        XCTAssertEqual(preview.actionName, "Restart Service")
        XCTAssertEqual(preview.riskLevel, .low)
        XCTAssertTrue(preview.isReversible)
        XCTAssertTrue(preview.expectedImpact.contains("temporarily drop"))
    }
}

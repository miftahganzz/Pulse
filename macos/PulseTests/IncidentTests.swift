import XCTest
@testable import Pulse

final class IncidentTests: XCTestCase {
    func testIncidentStorePersistence() throws {
        let serverId = UUID()
        let policy = IncidentAlertPolicy(
            consecutiveFailuresThreshold: 3,
            consecutiveSuccessThreshold: 2,
            notifyOnWarning: true,
            notifyOnCritical: true,
            notifyOnRecovery: true,
            isMuted: false,
            mutedUntil: nil
        )

        IncidentStore.saveAlertPolicy(policy, forServerId: serverId)
        let loadedPolicy = IncidentStore.loadAlertPolicy(forServerId: serverId)
        XCTAssertEqual(loadedPolicy.consecutiveFailuresThreshold, 3)
        XCTAssertEqual(loadedPolicy.consecutiveSuccessThreshold, 2)
        XCTAssertTrue(loadedPolicy.notifyOnRecovery)

        let incident = IncidentItem(
            serverId: serverId,
            monitorId: "mon-123",
            title: "PostgreSQL Database",
            target: "localhost:5432",
            severity: .critical,
            status: .ongoing,
            reason: "Connection refused",
            consecutiveFailures: 3
        )

        IncidentStore.saveIncidents([incident], forServerId: serverId)
        let loadedIncidents = IncidentStore.loadIncidents(forServerId: serverId)
        XCTAssertEqual(loadedIncidents.count, 1)
        XCTAssertEqual(loadedIncidents[0].title, "PostgreSQL Database")
        XCTAssertEqual(loadedIncidents[0].severity, .critical)
        XCTAssertEqual(loadedIncidents[0].status, .ongoing)
        XCTAssertEqual(loadedIncidents[0].consecutiveFailures, 3)
    }

    func testFlappingProtectionAndDowntimeResolution() throws {
        let serverId = UUID()
        let policy = IncidentAlertPolicy(
            consecutiveFailuresThreshold: 2,
            consecutiveSuccessThreshold: 2,
            notifyOnWarning: false,
            notifyOnCritical: true,
            notifyOnRecovery: true,
            isMuted: false,
            mutedUntil: nil
        )

        let engine = IncidentEngine(serverId: serverId, serverName: "Test-Server", policy: policy)
        var incidents: [IncidentItem] = []

        var monitor = MonitorItem(
            id: "svc-postgres",
            serverId: serverId,
            name: "PostgreSQL",
            type: .docker,
            target: "postgres-container",
            status: .down,
            message: "Container stopped"
        )

        // 1st failure: below threshold of 2 -> should NOT create incident yet (flapping protection)
        let res1 = engine.evaluateMonitorHealth(monitor: monitor, existingIncidents: &incidents)
        XCTAssertNil(res1)
        XCTAssertTrue(incidents.isEmpty)

        // 2nd failure: reaches threshold of 2 -> Incident created!
        let res2 = engine.evaluateMonitorHealth(monitor: monitor, existingIncidents: &incidents)
        XCTAssertNotNil(res2)
        XCTAssertEqual(incidents.count, 1)
        XCTAssertEqual(incidents[0].title, "PostgreSQL")
        XCTAssertEqual(incidents[0].status, .ongoing)
        XCTAssertEqual(incidents[0].consecutiveFailures, 2)

        // Now monitor starts recovering
        monitor.status = .healthy
        monitor.message = "OK"

        // 1st success: below recovery threshold of 2 -> still ongoing
        let res3 = engine.evaluateMonitorHealth(monitor: monitor, existingIncidents: &incidents)
        XCTAssertNil(res3)
        XCTAssertEqual(incidents[0].status, .ongoing)
        XCTAssertNil(incidents[0].recoveredAt)

        // 2nd success: reaches recovery threshold of 2 -> Incident resolved!
        let res4 = engine.evaluateMonitorHealth(monitor: monitor, existingIncidents: &incidents)
        XCTAssertNotNil(res4)
        XCTAssertEqual(incidents[0].status, .resolved)
        XCTAssertNotNil(incidents[0].recoveredAt)
        XCTAssertTrue(incidents[0].durationSeconds >= 0)
    }

    func testServerOutageGroupingSuppressesChildAlerts() throws {
        let serverId = UUID()
        let policy = IncidentAlertPolicy(
            consecutiveFailuresThreshold: 2,
            consecutiveSuccessThreshold: 2,
            notifyOnWarning: true,
            notifyOnCritical: true,
            notifyOnRecovery: true,
            isMuted: false,
            mutedUntil: nil
        )

        let engine = IncidentEngine(serverId: serverId, serverName: "Jakarta-VPS", policy: policy)
        var incidents: [IncidentItem] = []

        // Server offline count 1
        _ = engine.handleServerConnectionState(isConnected: false, isOffline: true, existingIncidents: &incidents)
        XCTAssertTrue(incidents.isEmpty)

        // Server offline count 2 -> triggers Server Unreachable incident
        let serverIncident = engine.handleServerConnectionState(isConnected: false, isOffline: true, existingIncidents: &incidents)
        XCTAssertNotNil(serverIncident)
        XCTAssertEqual(incidents.count, 1)
        XCTAssertEqual(incidents[0].title, "Server Unreachable")

        // While server is unreachable, individual monitor failures must be grouped/suppressed
        let monitor = MonitorItem(
            id: "m-redis",
            serverId: serverId,
            name: "Redis",
            type: .docker,
            target: "redis",
            status: .down
        )
        let childIncident = engine.evaluateMonitorHealth(monitor: monitor, existingIncidents: &incidents)
        XCTAssertNil(childIncident, "Monitor incident must be suppressed when entire server is unreachable")
        XCTAssertEqual(incidents.count, 1, "Should not flood with child incidents during server outage")

        // Server comes back online: 1st success
        _ = engine.handleServerConnectionState(isConnected: true, isOffline: false, existingIncidents: &incidents)
        XCTAssertEqual(incidents[0].status, .ongoing)

        // Server comes back online: 2nd success -> recovery
        let recoveredServer = engine.handleServerConnectionState(isConnected: true, isOffline: false, existingIncidents: &incidents)
        XCTAssertNotNil(recoveredServer)
        XCTAssertEqual(incidents[0].status, .resolved)
        XCTAssertNotNil(incidents[0].recoveredAt)
    }

    func testMaintenanceMutePolicy() throws {
        var policy = IncidentAlertPolicy(
            consecutiveFailuresThreshold: 1,
            consecutiveSuccessThreshold: 1,
            notifyOnWarning: true,
            notifyOnCritical: true,
            notifyOnRecovery: true,
            isMuted: true,
            mutedUntil: Date().addingTimeInterval(3600)
        )

        XCTAssertTrue(policy.isEffectivelyMuted)

        // Expired mute
        policy.mutedUntil = Date().addingTimeInterval(-10)
        policy.isMuted = false
        XCTAssertFalse(policy.isEffectivelyMuted)
    }
}

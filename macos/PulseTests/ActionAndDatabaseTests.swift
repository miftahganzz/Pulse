import XCTest
@testable import Pulse

final class ActionAndDatabaseTests: XCTestCase {
    func testActionAuditLogPersistenceAndLimit() throws {
        let serverId = UUID()
        ActivityStore.clearAuditLogs(forServerId: serverId)

        let log1 = ActionAuditLogItem(
            serverId: serverId,
            actionName: "docker.restart",
            target: "movnix-api",
            status: "success",
            message: "Container restarted",
            durationMs: 420
        )
        let log2 = ActionAuditLogItem(
            serverId: serverId,
            actionName: "pm2.reload",
            target: "movnix-worker",
            status: "success",
            message: "PM2 reloaded",
            durationMs: 180
        )

        _ = ActivityStore.appendAuditLog(log1, forServerId: serverId)
        let loadedAfterOne = ActivityStore.loadAuditLogs(forServerId: serverId)
        XCTAssertEqual(loadedAfterOne.count, 1)

        _ = ActivityStore.appendAuditLog(log2, forServerId: serverId)
        let loadedAfterTwo = ActivityStore.loadAuditLogs(forServerId: serverId)
        XCTAssertEqual(loadedAfterTwo.count, 2)
        XCTAssertEqual(loadedAfterTwo[0].actionName, "pm2.reload") // Most recent first
    }

    func testDatabaseKeychainPasswordStorage() throws {
        let monitorId = UUID().uuidString
        let secret = "SuperSecret_P@ssw0rd!123"

        try KeychainService.saveDatabasePassword(secret, forMonitorId: monitorId)
        let retrieved = KeychainService.getDatabasePassword(forMonitorId: monitorId)
        XCTAssertEqual(retrieved, secret)

        KeychainService.deleteDatabasePassword(forMonitorId: monitorId)
        let afterDelete = KeychainService.getDatabasePassword(forMonitorId: monitorId)
        XCTAssertNil(afterDelete)
    }

    func testDatabaseProbeResponseDecoding() throws {
        let json = """
        {
            "health": {
                "id": "127.0.0.1:6379",
                "status": "healthy",
                "message": "Redis 7.2 healthy (2 ms, Clients: 14)",
                "latency_ms": 2,
                "last_checked": "2026-09-11T08:30:00Z"
            },
            "metrics": {
                "response_time_ms": 2,
                "version": "7.2.4",
                "last_checked": "2026-09-11T08:30:00Z"
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let res = try decoder.decode(DatabaseProbeResponse.self, from: json)

        XCTAssertEqual(res.health.status, "healthy")
        XCTAssertEqual(res.health.latencyMs, 2)
        XCTAssertEqual(res.metrics?.version, "7.2.4")
        XCTAssertEqual(res.metrics?.responseTimeMs, 2)
    }
}

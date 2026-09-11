import XCTest
@testable import Pulse

final class AppExperienceTests: XCTestCase {
    func testAppSettingsPersistence() throws {
        let settings = AppSettingsStore.shared

        settings.launchAtLogin = false
        settings.showInMenuBar = true
        settings.keepRunningInBackground = true
        settings.theme = .dark
        settings.metricIntervalSeconds = 10
        settings.healthCheckIntervalSeconds = 30
        settings.notifyCritical = true
        settings.notifyWarning = true
        settings.notifyRecovery = true

        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertTrue(settings.showInMenuBar)
        XCTAssertTrue(settings.keepRunningInBackground)
        XCTAssertEqual(settings.theme, .dark)
        XCTAssertEqual(settings.metricIntervalSeconds, 10)
        XCTAssertEqual(settings.healthCheckIntervalSeconds, 30)
    }

    @MainActor
    func testServerConnectionPoolManagement() throws {
        let pool = ServerConnectionPool.shared
        XCTAssertNotNil(pool)

        let testServer = ServerModel(
            id: UUID(),
            name: "Test-Pool-VPS",
            address: "127.0.0.1",
            port: 8443
        )

        let mgr = pool.manager(for: testServer)
        XCTAssertEqual(mgr.serverName, "Test-Pool-VPS")
        XCTAssertEqual(mgr.port, 8443)

        pool.remove(serverId: testServer.id)
        XCTAssertNil(pool.managers[testServer.id])
    }
}

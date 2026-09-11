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

    @MainActor
    func testDeepLinkServerAddWithParameters() throws {
        let nav = NavigationState.shared
        nav.showAddServerSheet = false
        nav.pendingServerDraft = nil

        let url = URL(string: "pulse://add?name=Production-East&host=198.51.100.10&port=9443&token=secret123")!
        nav.handleDeepLink(url: url)

        XCTAssertTrue(nav.showAddServerSheet)
        XCTAssertNotNil(nav.pendingServerDraft)
        XCTAssertEqual(nav.pendingServerDraft?.name, "Production-East")
        XCTAssertEqual(nav.pendingServerDraft?.host, "198.51.100.10")
        XCTAssertEqual(nav.pendingServerDraft?.port, "9443")
        XCTAssertEqual(nav.pendingServerDraft?.token, "secret123")
    }

    @MainActor
    func testDeepLinkNavigationRouting() throws {
        let nav = NavigationState.shared
        let testUUID = UUID()

        let serverUrl = URL(string: "pulse://server/\(testUUID.uuidString)/security")!
        nav.handleDeepLink(url: serverUrl)

        XCTAssertEqual(nav.selectedServerId, testUUID.uuidString)
        XCTAssertEqual(nav.selectedDetailTab, 8)

        let allUrl = URL(string: "pulse://all")!
        nav.handleDeepLink(url: allUrl)
        XCTAssertEqual(nav.selectedServerId, "ALL_SERVERS")
    }
}

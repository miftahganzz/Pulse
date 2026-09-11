import XCTest
@testable import Pulse

final class AlertSettingsTests: XCTestCase {
    func testAlertSettingsPersistence() throws {
        let serverId = UUID()
        var settings = AlertSettingsStore.loadSettings(forServerId: serverId)

        // Defaults
        XCTAssertTrue(settings.isAlertsEnabled)
        XCTAssertTrue(settings.notifyOnOffline)
        XCTAssertEqual(settings.cpuThresholdPercent, 90.0)
        XCTAssertEqual(settings.memoryThresholdPercent, 90.0)
        XCTAssertEqual(settings.diskThresholdPercent, 90.0)

        // Modify and Save
        settings.cpuThresholdPercent = 85.0
        settings.memoryThresholdPercent = 80.0
        settings.diskThresholdPercent = 75.0
        settings.notifyOnOffline = false

        AlertSettingsStore.saveSettings(settings, forServerId: serverId)

        let loaded = AlertSettingsStore.loadSettings(forServerId: serverId)
        XCTAssertEqual(loaded.cpuThresholdPercent, 85.0)
        XCTAssertEqual(loaded.memoryThresholdPercent, 80.0)
        XCTAssertEqual(loaded.diskThresholdPercent, 75.0)
        XCTAssertFalse(loaded.notifyOnOffline)
    }
}

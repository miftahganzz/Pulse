import Foundation
import UserNotifications

public struct ServerAlertSettings: Codable, Equatable, Sendable {
    public var cpuThresholdPercent: Double
    public var memoryThresholdPercent: Double
    public var diskThresholdPercent: Double
    public var notifyOnOffline: Bool
    public var isAlertsEnabled: Bool

    public init(
        cpuThresholdPercent: Double = 90.0,
        memoryThresholdPercent: Double = 90.0,
        diskThresholdPercent: Double = 90.0,
        notifyOnOffline: Bool = true,
        isAlertsEnabled: Bool = true
    ) {
        self.cpuThresholdPercent = cpuThresholdPercent
        self.memoryThresholdPercent = memoryThresholdPercent
        self.diskThresholdPercent = diskThresholdPercent
        self.notifyOnOffline = notifyOnOffline
        self.isAlertsEnabled = isAlertsEnabled
    }
}

public enum AlertSettingsStore {
    private static let keyPrefix = "pulse.alerts.settings."

    public static func loadSettings(forServerId serverId: UUID) -> ServerAlertSettings {
        let key = "\(keyPrefix)\(serverId.uuidString)"
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(ServerAlertSettings.self, from: data) else {
            return ServerAlertSettings()
        }
        return settings
    }

    public static func saveSettings(_ settings: ServerAlertSettings, forServerId serverId: UUID) {
        let key = "\(keyPrefix)\(serverId.uuidString)"
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

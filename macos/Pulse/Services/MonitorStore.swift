import Foundation

public final class MonitorStore {
    private static let keyPrefix = "pulse.monitors."
    private static let ignoredKeyPrefix = "pulse.ignored_monitors."

    public static func loadMonitors(forServerId serverId: UUID) -> [MonitorItem] {
        let key = keyPrefix + serverId.uuidString
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return []
        }
        do {
            return try JSONDecoder().decode([MonitorItem].self, from: data)
        } catch {
            return []
        }
    }

    public static func saveMonitors(_ monitors: [MonitorItem], forServerId serverId: UUID) {
        let key = keyPrefix + serverId.uuidString
        do {
            let data = try JSONEncoder().encode(monitors)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            // failed to encode
        }
    }

    public static func loadIgnored(forServerId serverId: UUID) -> Set<String> {
        let key = ignoredKeyPrefix + serverId.uuidString
        let list = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(list)
    }

    public static func saveIgnored(_ ignored: Set<String>, forServerId serverId: UUID) {
        let key = ignoredKeyPrefix + serverId.uuidString
        UserDefaults.standard.set(Array(ignored), forKey: key)
    }
}

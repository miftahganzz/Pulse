import Foundation

public final class ActivityStore {
    private static let keyPrefix = "pulse.activity."
    private static let maxLogItems = 200

    public static func loadAuditLogs(forServerId serverId: UUID) -> [ActionAuditLogItem] {
        let key = keyPrefix + serverId.uuidString
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return []
        }
        do {
            return try JSONDecoder().decode([ActionAuditLogItem].self, from: data)
        } catch {
            return []
        }
    }

    public static func appendAuditLog(_ item: ActionAuditLogItem, forServerId serverId: UUID) -> [ActionAuditLogItem] {
        var current = loadAuditLogs(forServerId: serverId)
        current.insert(item, at: 0) // Most recent first
        if current.count > maxLogItems {
            current = Array(current.prefix(maxLogItems))
        }
        saveAuditLogs(current, forServerId: serverId)
        return current
    }

    public static func saveAuditLogs(_ logs: [ActionAuditLogItem], forServerId serverId: UUID) {
        let key = keyPrefix + serverId.uuidString
        do {
            let data = try JSONEncoder().encode(logs)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            // failed to encode
        }
    }

    public static func clearAuditLogs(forServerId serverId: UUID) {
        let key = keyPrefix + serverId.uuidString
        UserDefaults.standard.removeObject(forKey: key)
    }
}

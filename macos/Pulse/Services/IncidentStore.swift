import Foundation

public final class IncidentStore {
    private static let keyPrefix = "pulse.incidents."
    private static let policyKeyPrefix = "pulse.alert_policy."
    private static let maxIncidents = 100

    public static func loadIncidents(forServerId serverId: UUID) -> [IncidentItem] {
        let key = keyPrefix + serverId.uuidString
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return []
        }
        do {
            return try JSONDecoder().decode([IncidentItem].self, from: data)
        } catch {
            return []
        }
    }

    public static func saveIncidents(_ incidents: [IncidentItem], forServerId serverId: UUID) {
        let key = keyPrefix + serverId.uuidString
        let limited = Array(incidents.prefix(maxIncidents))
        do {
            let data = try JSONEncoder().encode(limited)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            // encoding error
        }
    }

    public static func loadAlertPolicy(forServerId serverId: UUID) -> IncidentAlertPolicy {
        let key = policyKeyPrefix + serverId.uuidString
        guard let data = UserDefaults.standard.data(forKey: key),
              let policy = try? JSONDecoder().decode(IncidentAlertPolicy.self, from: data) else {
            return IncidentAlertPolicy()
        }
        return policy
    }

    public static func saveAlertPolicy(_ policy: IncidentAlertPolicy, forServerId serverId: UUID) {
        let key = policyKeyPrefix + serverId.uuidString
        if let data = try? JSONEncoder().encode(policy) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

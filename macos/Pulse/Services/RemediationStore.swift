import Foundation

public enum RemediationStore {
    private static let policyKeyPrefix = "pulse.remediation.policies."
    private static let breakerKeyPrefix = "pulse.remediation.breakers."

    // MARK: - Policies
    public static func loadPolicies(forServerId serverId: UUID) -> [RemediationPolicy] {
        let key = policyKeyPrefix + serverId.uuidString
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([RemediationPolicy].self, from: data)) ?? []
    }

    public static func savePolicies(_ policies: [RemediationPolicy], forServerId serverId: UUID) {
        let key = policyKeyPrefix + serverId.uuidString
        if let data = try? JSONEncoder().encode(policies) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    public static func savePolicy(_ policy: RemediationPolicy, forServerId serverId: UUID) {
        var existing = loadPolicies(forServerId: serverId)
        if let idx = existing.firstIndex(where: { $0.monitorId == policy.monitorId }) {
            existing[idx] = policy
        } else {
            existing.append(policy)
        }
        savePolicies(existing, forServerId: serverId)
    }

    public static func deletePolicy(monitorId: String, forServerId serverId: UUID) {
        var existing = loadPolicies(forServerId: serverId)
        existing.removeAll { $0.monitorId == monitorId }
        savePolicies(existing, forServerId: serverId)
    }

    // MARK: - Circuit Breakers
    public static func loadBreakers(forServerId serverId: UUID) -> [String: CircuitBreakerState] {
        let key = breakerKeyPrefix + serverId.uuidString
        guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: CircuitBreakerState].self, from: data)) ?? [:]
    }

    public static func saveBreakers(_ breakers: [String: CircuitBreakerState], forServerId serverId: UUID) {
        let key = breakerKeyPrefix + serverId.uuidString
        if let data = try? JSONEncoder().encode(breakers) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    public static func resetBreaker(monitorId: String, forServerId serverId: UUID) {
        var breakers = loadBreakers(forServerId: serverId)
        breakers.removeValue(forKey: monitorId)
        saveBreakers(breakers, forServerId: serverId)
    }
}

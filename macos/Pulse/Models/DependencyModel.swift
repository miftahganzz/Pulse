import Foundation

public enum DependencyType: String, Codable, CaseIterable, Sendable {
    case requires = "requires"
    case connectsTo = "connects_to"

    public var displayName: String {
        switch self {
        case .requires: return "Requires"
        case .connectsTo: return "Connects to"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .requires: return "arrow.triangle.pull"
        case .connectsTo: return "point.3.filled.connected.trianglepath.dotted"
        }
    }
}

public struct ServiceDependency: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let serverId: UUID
    public let sourceMonitorId: String
    public let targetMonitorId: String
    public let type: DependencyType

    public init(
        id: String = UUID().uuidString,
        serverId: UUID,
        sourceMonitorId: String,
        targetMonitorId: String,
        type: DependencyType = .connectsTo
    ) {
        self.id = id
        self.serverId = serverId
        self.sourceMonitorId = sourceMonitorId
        self.targetMonitorId = targetMonitorId
        self.type = type
    }
}

public enum DependencyStore {
    public static func loadDependencies(forServerId serverId: UUID) -> [ServiceDependency] {
        let key = "pulse.dependencies.\(serverId.uuidString)"
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ServiceDependency].self, from: data)) ?? []
    }

    public static func saveDependencies(_ deps: [ServiceDependency], forServerId serverId: UUID) {
        let key = "pulse.dependencies.\(serverId.uuidString)"
        if let data = try? JSONEncoder().encode(deps) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    public static func addDependency(_ dep: ServiceDependency, forServerId serverId: UUID) -> [ServiceDependency] {
        var existing = loadDependencies(forServerId: serverId)
        // Prevent exact duplicates and self loops
        guard dep.sourceMonitorId != dep.targetMonitorId else { return existing }
        if !existing.contains(where: { $0.sourceMonitorId == dep.sourceMonitorId && $0.targetMonitorId == dep.targetMonitorId }) {
            existing.append(dep)
            saveDependencies(existing, forServerId: serverId)
        }
        return existing
    }

    public static func removeDependency(id: String, forServerId serverId: UUID) -> [ServiceDependency] {
        var existing = loadDependencies(forServerId: serverId)
        existing.removeAll { $0.id == id }
        saveDependencies(existing, forServerId: serverId)
        return existing
    }
}

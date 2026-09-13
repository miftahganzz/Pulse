import Foundation
import Combine

@MainActor
public final class ServerConnectionPool: ObservableObject {
    public static let shared = ServerConnectionPool()

    @Published public private(set) var managers: [UUID: ServerConnectionManager] = [:]

    private var cancellables = Set<AnyCancellable>()
    private let store = ServerStore.shared

    private init() {
        syncWithStore()
        store.$servers
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncWithStore()
            }
            .store(in: &cancellables)
    }

    public func syncWithStore() {
        let currentServers = store.servers
        let currentIds = Set(currentServers.map { $0.id })

        // Remove deleted
        for (id, mgr) in managers where !currentIds.contains(id) {
            mgr.disconnect()
            managers.removeValue(forKey: id)
        }

        // Add, connect, or update
        for server in currentServers {
            if let existing = managers[server.id] {
                existing.updateConfig(name: server.name, address: server.address, port: server.port)
            } else {
                let mgr = ServerConnectionManager(
                    serverId: server.id,
                    serverName: server.name,
                    address: server.address,
                    port: server.port
                )
                managers[server.id] = mgr
                mgr.connect()
            }
        }
    }

    public func manager(for server: ServerModel) -> ServerConnectionManager {
        if let existing = managers[server.id] {
            return existing
        }
        let mgr = ServerConnectionManager(
            serverId: server.id,
            serverName: server.name,
            address: server.address,
            port: server.port
        )
        managers[server.id] = mgr
        mgr.connect()
        return mgr
    }

    public func remove(serverId: UUID) {
        if let mgr = managers[serverId] {
            mgr.disconnect()
            managers.removeValue(forKey: serverId)
        }
    }

    public func reconnectAll() {
        for mgr in managers.values {
            mgr.connect()
        }
    }

    public func handleNetworkLoss() {
        for mgr in managers.values {
            mgr.handleNetworkOffline()
        }
    }

    public func prepareForSleep() {
        for mgr in managers.values {
            mgr.prepareForSleep()
        }
    }

    public func handleWakeFromSleep() {
        for mgr in managers.values {
            mgr.handleWakeFromSleep()
        }
    }

    // Computed global health
    public var totalServers: Int {
        managers.count
    }

    public var healthyCount: Int {
        managers.values.filter { $0.state.isConnected && $0.incidents.filter({ $0.status != .resolved }).isEmpty }.count
    }

    public var activeIncidentsCount: Int {
        managers.values.reduce(0) { $0 + $1.incidents.filter({ $0.status != .resolved }).count }
    }

    public var activeIncidents: [IncidentItem] {
        managers.values.flatMap { $0.incidents.filter { $0.status != .resolved } }
    }

    public var offlineCount: Int {
        managers.values.filter { $0.state.isOffline }.count
    }

    public var primaryServerMetrics: MetricsSnapshot? {
        managers.values.first(where: { $0.state.isConnected && $0.currentMetrics != nil })?.currentMetrics
    }
}

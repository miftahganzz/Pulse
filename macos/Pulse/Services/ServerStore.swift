import Foundation
import Combine

@MainActor
public final class ServerStore: ObservableObject {
    public static let shared = ServerStore()

    @Published public private(set) var servers: [ServerModel] = []
    private let storageKey = "pulse.saved_servers"

    public init() {
        loadServers()
    }

    public func addServer(
        name: String,
        address: String,
        port: Int,
        token: String,
        environment: ServerEnvironment = .untagged,
        tags: [String] = []
    ) throws {
        let server = ServerModel(
            name: name,
            address: address,
            port: port,
            environment: environment,
            tags: tags
        )
        try KeychainService.saveToken(token, forServerId: server.id)
        servers.append(server)
        persist()
        PulseLog.persistence.info("Saved new server \(server.name) (\(server.id))")
    }

    public func deleteServer(_ server: ServerModel) {
        KeychainService.deleteToken(forServerId: server.id)
        servers.removeAll { $0.id == server.id }
        persist()
        PulseLog.persistence.info("Deleted server \(server.name) (\(server.id))")
    }

    /// Update environment and/or tags for an existing server
    public func updateServer(_ server: ServerModel, environment: ServerEnvironment? = nil, tags: [String]? = nil) {
        guard let idx = servers.firstIndex(where: { $0.id == server.id }) else { return }
        if let env = environment { servers[idx].environment = env }
        if let t = tags { servers[idx].tags = t }
        persist()
    }

    // MARK: - Grouping helpers

    /// Servers grouped by environment, ordered: prod → staging → dev → other
    public var serversByEnvironment: [(ServerEnvironment, [ServerModel])] {
        let order: [ServerEnvironment] = [.production, .staging, .development, .untagged]
        return order.compactMap { env in
            let group = servers.filter { $0.environment == env }
            return group.isEmpty ? nil : (env, group)
        }
    }

    // MARK: - Persistence

    private func loadServers() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            servers = try JSONDecoder().decode([ServerModel].self, from: data)
        } catch {
            PulseLog.persistence.error("Failed to load servers: \(error.localizedDescription)")
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(servers)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            PulseLog.persistence.error("Failed to persist servers: \(error.localizedDescription)")
        }
    }
}

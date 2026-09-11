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

    public func addServer(name: String, address: String, port: Int, token: String) throws {
        let server = ServerModel(name: name, address: address, port: port)
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

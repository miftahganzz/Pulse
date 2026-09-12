import Foundation
import Combine

public struct ServerDraft: Equatable {
    public var name: String
    public var host: String
    public var port: String
    public var token: String

    public init(name: String = "", host: String = "", port: String = "8443", token: String = "") {
        self.name = name
        self.host = host
        self.port = port
        self.token = token
    }
}

@MainActor
public final class NavigationState: ObservableObject {
    public static let shared = NavigationState()

    @Published public var selectedServerId: String = "ALL_SERVERS"
    @Published public var selectedDetailTab: Int = 0 // 0: Overview, 1: Monitors, 2: Incidents, 3: Processes, 4: Services, 5: Docker, 6: Activity, 7: Topology, 8: Security
    @Published public var showSettings: Bool = false
    @Published public var showCommandPalette: Bool = false
    @Published public var showAddServerSheet: Bool = false
    @Published public var showDocs: Bool = false
    @Published public var pendingServerDraft: ServerDraft? = nil
    @Published public var serverToEdit: ServerModel? = nil

    private init() {}

    public func navigateToAllServers() {
        selectedServerId = "ALL_SERVERS"
    }

    public func navigateToServer(_ id: UUID, tab: Int = 0) {
        selectedServerId = id.uuidString
        selectedDetailTab = tab
    }

    public func handleDeepLink(url: URL) {
        // e.g.
        // pulse://server/{id}/incident/{id}
        // pulse://server/{id}/services
        // pulse://server/{id}/tab/{tabIndex}
        // pulse://add?name=VPS-1&host=192.168.1.10&port=8443&token=xyz
        // pulse://settings
        // pulse://all
        guard url.scheme == "pulse" else { return }
        let host = url.host ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        if host == "server" || host == "servers" {
            if let first = pathComponents.first, let uuid = UUID(uuidString: first) {
                var targetTab = 0
                if pathComponents.count >= 2 {
                    let sub = pathComponents[1]
                    switch sub {
                    case "monitors": targetTab = 1
                    case "incident", "incidents": targetTab = 2
                    case "processes": targetTab = 3
                    case "services", "system-services": targetTab = 4
                    case "docker", "containers": targetTab = 5
                    case "activity": targetTab = 6
                    case "topology", "map": targetTab = 7
                    case "security", "ports": targetTab = 8
                    case "logs", "live-logs": targetTab = 9
                    case "storage", "disk": targetTab = 10
                    case "edit":
                        if let server = ServerStore.shared.servers.first(where: { $0.id == uuid }) {
                            self.serverToEdit = server
                        }
                        return
                    case "tab":
                        if pathComponents.count >= 3, let customTab = Int(pathComponents[2]) {
                            targetTab = customTab
                        }
                    default: break
                    }
                }
                navigateToServer(uuid, tab: targetTab)
            }
        } else if host == "add" || host == "add-server" || host == "connect" {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
            let queryItems = components.queryItems ?? []
            let name = queryItems.first(where: { $0.name == "name" })?.value ?? ""
            let address = queryItems.first(where: { $0.name == "host" || $0.name == "address" || $0.name == "url" })?.value ?? ""
            let port = queryItems.first(where: { $0.name == "port" })?.value ?? "8443"
            let token = queryItems.first(where: { $0.name == "token" || $0.name == "key" })?.value ?? ""

            pendingServerDraft = ServerDraft(name: name, host: address, port: port, token: token)
            showAddServerSheet = true
        } else if host == "all" || host == "overview" {
            navigateToAllServers()
        } else if host == "settings" {
            showSettings = true
        }
    }
}

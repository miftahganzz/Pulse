import Foundation
import Combine

@MainActor
public final class NavigationState: ObservableObject {
    public static let shared = NavigationState()

    @Published public var selectedServerId: String = "ALL_SERVERS"
    @Published public var selectedDetailTab: Int = 0 // 0: Overview, 1: Monitors, 2: Incidents, 3: Processes, 4: Services, 5: Docker, 6: Activity
    @Published public var showSettings: Bool = false
    @Published public var showCommandPalette: Bool = false

    private init() {}

    public func navigateToAllServers() {
        selectedServerId = "ALL_SERVERS"
    }

    public func navigateToServer(_ id: UUID, tab: Int = 0) {
        selectedServerId = id.uuidString
        selectedDetailTab = tab
    }

    public func handleDeepLink(url: URL) {
        // e.g. pulse://server/{id}/incident/{id} or pulse://server/{id}/tab/{tabIndex}
        guard url.scheme == "pulse" else { return }
        let host = url.host ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        if host == "server" || host == "servers" {
            if let first = pathComponents.first, let uuid = UUID(uuidString: first) {
                var targetTab = 0
                if pathComponents.count >= 3 && pathComponents[1] == "incident" {
                    targetTab = 2
                } else if pathComponents.count >= 3 && pathComponents[1] == "services" {
                    targetTab = 1
                }
                navigateToServer(uuid, tab: targetTab)
            }
        } else if host == "all" || host == "overview" {
            navigateToAllServers()
        } else if host == "settings" {
            showSettings = true
        }
    }
}

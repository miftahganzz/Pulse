import Foundation
import Network
import Combine

@MainActor
public final class NetworkMonitor: ObservableObject {
    public static let shared = NetworkMonitor()

    @Published public private(set) var isConnected: Bool = true
    @Published public private(set) var isExpensive: Bool = false
    @Published public private(set) var connectionType: ConnectionType = .wifi

    public enum ConnectionType: String, Sendable {
        case wifi = "Wi-Fi"
        case cellular = "Cellular"
        case ethernet = "Ethernet"
        case loopback = "Loopback"
        case unknown = "Unknown"
    }

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.pulse.networkmonitor")

    private init() {
        self.monitor = NWPathMonitor()
        self.monitor.pathUpdateHandler = { [weak self] path in
            let isConnected = (path.status == .satisfied)
            let isExpensive = path.isExpensive
            let type: ConnectionType
            if path.usesInterfaceType(.wifi) {
                type = .wifi
            } else if path.usesInterfaceType(.cellular) {
                type = .cellular
            } else if path.usesInterfaceType(.wiredEthernet) {
                type = .ethernet
            } else if path.usesInterfaceType(.loopback) {
                type = .loopback
            } else {
                type = .unknown
            }

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let wasDisconnected = !self.isConnected
                self.isConnected = isConnected
                self.isExpensive = isExpensive
                self.connectionType = type

                // If network was disconnected and came back online, notify pools to reconnect immediately
                if wasDisconnected && isConnected {
                    PulseLog.network.info("Network connectivity restored. Triggering reconnects.")
                    ServerConnectionPool.shared.reconnectAll()
                } else if !isConnected {
                    PulseLog.network.info("Network connectivity lost.")
                    ServerConnectionPool.shared.handleNetworkLoss()
                }
            }
        }
        self.monitor.start(queue: self.queue)
    }
}

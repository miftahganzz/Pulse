import SwiftUI

public struct MenuBarExtraView: View {
    @ObservedObject private var pool = ServerConnectionPool.shared
    @ObservedObject private var store = ServerStore.shared

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Global Status
            let total = store.servers.count
            let incidents = pool.activeIncidents

            if total == 0 {
                Text("Pulse — No Servers")
                    .font(.headline)
            } else if !incidents.isEmpty {
                HStack {
                    Text("\(incidents.count) Active Incident\(incidents.count > 1 ? "s" : "")")
                        .font(.headline)
                        .foregroundColor(.red)
                }

                ForEach(incidents.prefix(3), id: \.id) { incident in
                    Text("• \(incident.title): \(incident.reason)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack {
                    Text("All systems operational")
                        .font(.headline)
                        .foregroundColor(.green)
                }
            }

            Divider()

            // Server List
            if !store.servers.isEmpty {
                Text("\(total) Server\(total > 1 ? "s" : "")")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(store.servers, id: \.id) { server in
                    let mgr = pool.manager(for: server)
                    HStack {
                        Circle()
                            .fill(mgr.state.isConnected ? (mgr.incidents.filter { $0.status != .resolved }.isEmpty ? Color.green : Color.orange) : Color.secondary)
                            .frame(width: 7, height: 7)

                        Text(server.name)
                            .font(.system(size: 12, weight: .medium))

                        Spacer()

                        Text(mgr.state.displayStatus)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Divider()
            }

            Button("Open Pulse") {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where window.canBecomeMain {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            .keyboardShortcut("o")

            Button("Reconnect All") {
                pool.reconnectAll()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Button("Quit Pulse") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(10)
    }
}

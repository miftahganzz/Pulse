import SwiftUI

public struct AllServersOverviewView: View {
    @ObservedObject private var pool = ServerConnectionPool.shared
    @ObservedObject private var store = ServerStore.shared
    @Binding var selectedServer: ServerModel?

    public init(selectedServer: Binding<ServerModel?>) {
        self._selectedServer = selectedServer
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Banner
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("All Servers")
                            .font(.system(size: 24, weight: .bold))

                        let total = store.servers.count
                        let incidents = pool.activeIncidentsCount
                        let offline = pool.offlineCount

                        if total == 0 {
                            Text("No servers configured")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        } else if incidents > 0 {
                            HStack(spacing: 6) {
                                Circle().fill(Color.red).frame(width: 8, height: 8)
                                Text("\(incidents) active incident\(incidents > 1 ? "s" : "") across \(total) server\(total > 1 ? "s" : "")")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.red)
                            }
                        } else if offline > 0 {
                            HStack(spacing: 6) {
                                Circle().fill(Color.secondary).frame(width: 8, height: 8)
                                Text("\(offline) server\(offline > 1 ? "s" : "") offline · \(total - offline) operational")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 13))
                                Text("All systems operational (\(total) server\(total > 1 ? "s" : ""))")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.green)
                            }
                        }
                    }

                    Spacer()

                    Button {
                        pool.reconnectAll()
                    } label: {
                        Label("Reconnect All", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Divider()
                    .padding(.horizontal, 20)

                // Server Cards Grid
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 16)], spacing: 16) {
                    ForEach(store.servers) { server in
                        let mgr = pool.manager(for: server)
                        ServerOverviewCard(server: server, manager: mgr)
                            .onTapGesture {
                                selectedServer = server
                            }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }
}

private struct ServerOverviewCard: View {
    let server: ServerModel
    @ObservedObject var manager: ServerConnectionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .font(.system(size: 15, weight: .bold))
                    Text("\(server.address):\(server.port)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                ServerStatusBadge(state: manager.state)
            }

            Divider()

            // Metrics Summary
            if let metrics = manager.currentMetrics, manager.state.isConnected {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CPU")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f%%", metrics.cpu.usagePercent))
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                            .foregroundColor(metrics.cpu.usagePercent > 85 ? .red : .primary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("RAM")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f%%", metrics.memory.usagePercent))
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                            .foregroundColor(metrics.memory.usagePercent > 85 ? .red : .primary)
                    }

                    if let disk = metrics.primaryDisk {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("DISK")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text(String(format: "%.0f%%", disk.usagePercent))
                                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        }
                    }

                    Spacer()
                }
            } else {
                Text(manager.state.displayStatus)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            }

            // Incidents or Health Summary
            let activeIncidents = manager.incidents.filter { $0.status != .resolved }
            if !activeIncidents.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 11))
                    Text("\(activeIncidents.count) active incident\(activeIncidents.count > 1 ? "s" : "")")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.red)
                }
                .padding(.top, 2)
            } else if manager.state.isConnected {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.green)
                        .font(.system(size: 11))
                    Text("\(manager.monitors.filter { $0.isEnabled }.count) monitors operational")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}

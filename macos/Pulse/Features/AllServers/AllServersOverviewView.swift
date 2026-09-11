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
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(server.address):\(server.port)")
                        .font(.system(size: 11, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }

                Spacer()

                ServerStatusBadge(state: manager.state)
            }

            Divider().opacity(0.4)

            // Metrics Summary with Mini Gauges
            if let metrics = manager.currentMetrics, manager.state.isConnected {
                HStack(spacing: 12) {
                    MiniMetricColumn(
                        label: "CPU",
                        value: String(format: "%.0f%%", metrics.cpu.usagePercent),
                        percent: metrics.cpu.usagePercent,
                        tintColor: metrics.cpu.usagePercent > 85 ? .red : (metrics.cpu.usagePercent > 70 ? .orange : .blue)
                    )

                    Divider().frame(height: 28).opacity(0.3)

                    MiniMetricColumn(
                        label: "RAM",
                        value: String(format: "%.0f%%", metrics.memory.usagePercent),
                        percent: metrics.memory.usagePercent,
                        tintColor: metrics.memory.usagePercent > 90 ? .red : (metrics.memory.usagePercent > 75 ? .orange : .indigo)
                    )

                    if let disk = metrics.primaryDisk {
                        Divider().frame(height: 28).opacity(0.3)

                        MiniMetricColumn(
                            label: "DISK",
                            value: String(format: "%.0f%%", disk.usagePercent),
                            percent: disk.usagePercent,
                            tintColor: disk.usagePercent > 90 ? .red : (disk.usagePercent > 80 ? .orange : .teal)
                        )
                    }

                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text(manager.state.displayStatus)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            Divider().opacity(0.4)

            // Incidents or Health Status Footer
            let activeIncidents = manager.incidents.filter { $0.status != .resolved }
            HStack {
                if !activeIncidents.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 10))
                        Text("\(activeIncidents.count) active incident\(activeIncidents.count > 1 ? "s" : "")")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.red)
                    }
                } else if manager.state.isConnected {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 10))
                        Text("\(manager.monitors.filter { $0.isEnabled }.count) monitors active")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Offline")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary.opacity(isHovered ? 0.8 : 0.3))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isHovered ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isHovered ? 0.05 : 0.02), radius: isHovered ? 6 : 3, x: 0, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

private struct MiniMetricColumn: View {
    let label: String
    let value: String
    let percent: Double
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)

            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.primary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 3.5)

                    Capsule()
                        .fill(tintColor)
                        .frame(width: max(2, min(geo.size.width, geo.size.width * CGFloat(percent / 100.0))), height: 3.5)
                }
            }
            .frame(width: 50, height: 3.5)
        }
    }
}


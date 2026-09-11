import SwiftUI

public struct ServerDetailView: View {
    @ObservedObject var manager: ServerConnectionManager
    @ObservedObject private var navState = NavigationState.shared
    @State private var showSettingsSheet = false

    public init(manager: ServerConnectionManager) {
        self.manager = manager
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(manager.serverName)
                                .font(.system(size: 22, weight: .semibold))

                            if manager.isStale {
                                Text("Stale")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.15))
                                    .cornerRadius(4)
                            }
                        }

                        Text("\(manager.address):\(manager.port)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        showSettingsSheet = true
                    } label: {
                        Image(systemName: manager.alertSettings.isAlertsEnabled ? "bell.badge" : "bell.slash")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .help("Alert Settings")

                    ServerStatusBadge(state: manager.state)

                    if manager.state.isConnected {
                        Button("Disconnect") {
                            manager.disconnect()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Connect") {
                            manager.connect()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if let error = manager.lastError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                    .padding(10)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
                }

                // Tab Switcher
                Picker("", selection: $navState.selectedDetailTab) {
                    Text("Overview").tag(0)
                    Text("Monitors").tag(1)
                    Text(manager.incidents.filter({ $0.status != .resolved }).isEmpty ? "Incidents" : "Incidents (\(manager.incidents.filter({ $0.status != .resolved }).count))").tag(2)
                    Text("Processes").tag(3)
                    Text("Services").tag(4)
                    Text("Docker").tag(5)
                    Text("Map").tag(7)
                    Text("Activity").tag(6)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 680)
            }
            .padding([.top, .horizontal], 20)
            .padding(.bottom, 12)

            Divider()

            // Content Area
            Group {
                switch navState.selectedDetailTab {
                case 0:
                    overviewContent
                case 1:
                    MonitorsView(manager: manager)
                case 2:
                    IncidentsView(manager: manager)
                case 3:
                    ProcessListView(manager: manager)
                        .padding(16)
                case 4:
                    ServiceListView(manager: manager)
                        .padding(16)
                case 5:
                    DockerContainersView(manager: manager)
                        .padding(16)
                case 6:
                    ActivityLogView(manager: manager)
                case 7:
                    InfrastructureMapView(manager: manager)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if manager.state == .disconnected {
                manager.connect()
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            AlertSettingsSheet(manager: manager)
        }
    }

    private var overviewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Active Incident Alert Banner on Overview
                let activeIncidents = manager.incidents.filter { $0.status != .resolved }
                if !activeIncidents.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.red)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(activeIncidents.count) Active Incident\(activeIncidents.count > 1 ? "s" : "")")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.red)

                            Text(activeIncidents.map { "\($0.title) (\($0.formattedDuration))" }.joined(separator: " · "))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button("View Incidents") {
                            navState.selectedDetailTab = 2
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }

                // 1. Primary Realtime System Metrics (Phase 2)
                if let metrics = manager.currentMetrics {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("System Metrics")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)

                            Spacer()

                            HStack(spacing: 8) {
                                Text("Load: \(String(format: "%.2f, %.2f, %.2f", metrics.loadAvg.load1, metrics.loadAvg.load5, metrics.loadAvg.load15))")
                                    .font(.system(size: 11, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)

                                Text("Up: \(formatDuration(seconds: metrics.uptimeSeconds))")
                                    .font(.system(size: 11, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }

                        // Primary 4 Cards Grid
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                            CPUMetricCard(cpu: metrics.cpu)
                            MemoryMetricCard(mem: metrics.memory)

                            if let primary = metrics.primaryDisk {
                                DiskMetricCard(disk: primary)
                            }

                            NetworkMetricCard(network: metrics.network)
                        }

                        // Additional Disks if multi-mount
                        if metrics.disks.count > 1 {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Additional Disks")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)

                                ForEach(metrics.disks.filter { $0.mountPoint != "/" }) { extraDisk in
                                    DiskMetricCard(disk: extraDisk)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }

                    // 2. Resource Trends & Disk Growth Analytics (Phase 7)
                    let trends = MetricsHistoryStore.analyzeTrends(for: manager.metricsHistory)
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .foregroundColor(.accentColor)
                                Text("Resource Trend")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            HStack(spacing: 12) {
                                Text(String(format: "CPU: %+.1f%%", trends.cpuDelta))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(trends.cpuDelta > 5 ? .red : (trends.cpuDelta < -5 ? .green : .secondary))

                                Text(String(format: "RAM: %+.1f%%", trends.memoryDelta))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(trends.memoryDelta > 5 ? .red : (trends.memoryDelta < -5 ? .green : .secondary))
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "internaldrive.fill")
                                    .foregroundColor(.accentColor)
                                Text("Estimated Disk Growth")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            if let days = trends.estimatedDaysToFull, days > 0 {
                                Text(String(format: "%+.1f MB/day · ~%.0f days to full", trends.diskGrowthPerDayBytes / 1024 / 1024, days))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(days < 14 ? .orange : .secondary)
                            } else {
                                Text("Disk usage stable or rate not yet determined")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                    }

                    // 3. Historical Charts (1h trends via Swift Charts)
                    MetricChartsView(history: manager.metricsHistory)

                    Divider()
                }

                // 3. System & Agent Identity Information
                VStack(alignment: .leading, spacing: 14) {
                    Text("Server Identity")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)

                    if let identity = manager.identity {
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                            GridRow {
                                Text("Hostname")
                                    .foregroundColor(.secondary)
                                Text(identity.hostname)
                                    .fontWeight(.medium)
                            }
                            GridRow {
                                Text("OS")
                                    .foregroundColor(.secondary)
                                Text(identity.os)
                                    .fontWeight(.medium)
                            }
                            GridRow {
                                Text("Kernel")
                                    .foregroundColor(.secondary)
                                Text(identity.kernelVersion)
                                    .fontWeight(.medium)
                            }
                            GridRow {
                                Text("Architecture")
                                    .foregroundColor(.secondary)
                                Text(identity.architecture)
                                    .fontWeight(.medium)
                            }
                            GridRow {
                                Text("CPU Cores")
                                    .foregroundColor(.secondary)
                                Text("\(identity.cpuCores) cores")
                                    .fontWeight(.medium)
                            }
                            GridRow {
                                Text("Agent Version")
                                    .foregroundColor(.secondary)
                                Text("v\(identity.agentVersion)")
                                    .fontWeight(.medium)
                            }
                            GridRow {
                                Text("Agent ID")
                                    .foregroundColor(.secondary)
                                Text(identity.agentID)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    } else {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Waiting for server identity...")
                                .foregroundColor(.secondary)
                                .font(.system(size: 13))
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let heartbeat = manager.lastHeartbeat {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connection Health")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)

                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Uptime")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(formatDuration(seconds: heartbeat.uptimeSeconds))
                                    .font(.system(.body, design: .monospaced))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Heartbeat Sequence")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("#\(heartbeat.sequence)")
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(20)
        }
    }

    private func formatDuration(seconds: Int64) -> String {
        let days = seconds / 86400
        let hrs = (seconds % 86400) / 3600
        let mins = (seconds % 3600) / 60
        if days > 0 {
            return String(format: "%dd %dh %dm", days, hrs, mins)
        } else if hrs > 0 {
            return String(format: "%dh %02dm", hrs, mins)
        }
        return String(format: "%02dm %02ds", mins, seconds % 60)
    }
}

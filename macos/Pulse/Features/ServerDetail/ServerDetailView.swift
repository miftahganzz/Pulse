import SwiftUI

public struct ServerDetailView: View {
    @ObservedObject var manager: ServerConnectionManager
    @ObservedObject private var navState = NavigationState.shared
    @State private var showSettingsSheet = false
    @State private var showEditServerSheet = false
    @State private var showRunbooksSheet = false

    public init(manager: ServerConnectionManager) {
        self.manager = manager
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(manager.serverName)
                                .font(.system(size: 20, weight: .bold))

                            if let server = ServerStore.shared.servers.first(where: { $0.id == manager.serverId }) {
                                Text(server.environment.rawValue.uppercased())
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(server.environment.color.opacity(0.15))
                                    .foregroundColor(server.environment.color)
                                    .cornerRadius(4)
                            }
                        }

                        Text(verbatim: "\(manager.address):\(manager.port)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        Button {
                            showRunbooksSheet = true
                        } label: {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 12))
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help("Maintenance Runbooks (⌘R)")
                        .keyboardShortcut("r", modifiers: .command)

                        Button {
                            showEditServerSheet = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 12))
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help("Edit Server Details (⌘E)")
                        .keyboardShortcut("e", modifiers: .command)

                        Button {
                            showSettingsSheet = true
                        } label: {
                            Image(systemName: manager.alertSettings.isAlertsEnabled ? "bell.badge" : "bell.slash")
                                .font(.system(size: 12))
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help("Alert Settings (⌘⇧A)")
                        .keyboardShortcut("a", modifiers: [.command, .shift])

                        ServerStatusBadge(state: manager.state)

                        if manager.state.isConnected {
                            Button("Disconnect") {
                                manager.disconnect()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else {
                            Button("Connect") {
                                manager.connect()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
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

                if case .offline(let reason) = manager.state, reason == .noNetwork {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No Network Connection")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                            Text("Please check your Wi-Fi or Ethernet connection. Pulse will automatically reconnect once online.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                }

                // Responsive Horizontal Tab Switcher
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            tabButton(title: "Overview", tag: 0)
                                .id(0)
                            tabButton(title: "Logs", tag: 9)
                                .id(9)
                            tabButton(title: "Storage", tag: 10)
                                .id(10)
                            tabButton(title: "Monitors", tag: 1)
                                .id(1)
                            let incidentCount = manager.incidents.filter({ $0.status != .resolved }).count
                            tabButton(title: "Incidents", tag: 2, badge: incidentCount > 0 ? "\(incidentCount)" : nil, badgeColor: .red)
                                .id(2)
                            tabButton(title: "Processes", tag: 3)
                                .id(3)
                            tabButton(title: "Services", tag: 4)
                                .id(4)
                            tabButton(title: "Docker", tag: 5)
                                .id(5)
                            let secCount = manager.securitySnapshot?.sensitiveCount ?? 0
                            tabButton(title: "Security", tag: 8, badge: secCount > 0 ? "\(secCount)" : nil, badgeColor: .red)
                                .id(8)
                            tabButton(title: "Map", tag: 7)
                                .id(7)
                            tabButton(title: "Activity", tag: 6)
                                .id(6)
                        }
                        .padding(.horizontal, 2)
                    }
                    .onChange(of: navState.selectedDetailTab) { newTab in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(newTab, anchor: .center)
                        }
                    }
                }
            }
            .padding([.top, .horizontal], 14)
            .padding(.bottom, 8)

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
                case 8:
                    SecurityPortsView(manager: manager)
                case 9:
                    LiveLogView(manager: manager)
                case 10:
                    DiskAnalyzerView(manager: manager)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            if manager.state == .disconnected {
                manager.connect()
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            AlertSettingsSheet(manager: manager)
        }
        .sheet(isPresented: $showEditServerSheet) {
            if let server = ServerStore.shared.servers.first(where: { $0.id == manager.serverId }) {
                ServerTagEditorSheet(server: server)
            }
        }
        .sheet(isPresented: $showRunbooksSheet) {
            RunbooksSheet(manager: manager)
        }
    }

    private func tabButton(title: String, tag: Int, badge: String? = nil, badgeColor: Color = .red) -> some View {
        let isSelected = navState.selectedDetailTab == tag
        return Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                navState.selectedDetailTab = tag
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                    .fixedSize()

                if let b = badge {
                    Text(b)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(badgeColor.opacity(0.18))
                        .foregroundColor(badgeColor)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(isSelected ? Color.primary.opacity(0.12) : Color.clear)
            .foregroundColor(isSelected ? .primary : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

                    // 2. Resource Trends & Disk Growth Analytics
                    let trends = MetricsHistoryStore.analyzeTrends(for: manager.metricsHistory)
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.accentColor)
                                    .frame(width: 22, height: 22)
                                    .background(Color.accentColor.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                                Text("Resource Trend (1h)")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            HStack(spacing: 16) {
                                HStack(spacing: 4) {
                                    Text("CPU:")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%+.1f%%", trends.cpuDelta))
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .monospacedDigit()
                                        .foregroundColor(trends.cpuDelta > 5 ? .red : (trends.cpuDelta < -5 ? .green : .secondary))
                                }

                                HStack(spacing: 4) {
                                    Text("RAM:")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%+.1f%%", trends.memoryDelta))
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .monospacedDigit()
                                        .foregroundColor(trends.memoryDelta > 5 ? .red : (trends.memoryDelta < -5 ? .green : .secondary))
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "internaldrive")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.teal)
                                    .frame(width: 22, height: 22)
                                    .background(Color.teal.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                                Text("Estimated Disk Growth")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            if let days = trends.estimatedDaysToFull, days > 0 {
                                Text(String(format: "%+.1f MB/day · ~%.0f days to full", trends.diskGrowthPerDayBytes / 1024 / 1024, days))
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundColor(days < 14 ? .orange : .secondary)
                            } else {
                                Text("Usage rate steady or baseline calculating")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    }

                    // 3. Historical Charts (1h trends via Swift Charts)
                    MetricChartsView(history: manager.metricsHistory)

                    Divider()
                }

                // 4. System & Agent Identity Information
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("Server Identity")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                    }

                    if let identity = manager.identity {
                        VStack(spacing: 0) {
                            ServerIdentityRow(label: "Hostname", value: identity.hostname, canCopy: true)
                            Divider().padding(.horizontal, 14).opacity(0.3)
                            ServerIdentityRow(label: "Operating System", value: identity.os)
                            Divider().padding(.horizontal, 14).opacity(0.3)
                            ServerIdentityRow(label: "Kernel Release", value: identity.kernelVersion, isMonospace: true)
                            Divider().padding(.horizontal, 14).opacity(0.3)
                            ServerIdentityRow(label: "Architecture", value: identity.architecture)
                            Divider().padding(.horizontal, 14).opacity(0.3)
                            ServerIdentityRow(label: "CPU Cores", value: "\(identity.cpuCores) Cores")
                            Divider().padding(.horizontal, 14).opacity(0.3)
                            ServerIdentityRow(label: "Agent Version", value: "v\(identity.agentVersion)", isMonospace: true)
                            Divider().padding(.horizontal, 14).opacity(0.3)
                            ServerIdentityRow(label: "Agent UUID", value: identity.agentID, isMonospace: true, canCopy: true)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    } else {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Waiting for server identity...")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                    }
                }

                if let heartbeat = manager.lastHeartbeat {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text("Connection Telemetry")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Uptime")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text(formatDuration(seconds: heartbeat.uptimeSeconds))
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .monospacedDigit()
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Heartbeat Sequence")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text("#\(heartbeat.sequence)")
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .monospacedDigit()
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                            )
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

private struct ServerIdentityRow: View {
    let label: String
    let value: String
    var isMonospace: Bool = false
    var canCopy: Bool = false
    @State private var copied = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(isMonospace ? .system(size: 12, design: .monospaced) : .system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundColor(.primary)

            if canCopy {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundColor(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("Copy \(label)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}


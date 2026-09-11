import SwiftUI

public struct ServerCompareView: View {
    @ObservedObject private var store = ServerStore.shared
    @ObservedObject private var pool = ServerConnectionPool.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerView
                Divider()
                if store.servers.isEmpty {
                    emptyStateView
                } else {
                    compareTableView
                }
            }
            .padding(20)
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Compare Servers")
                .font(.headline)
            Text("Side-by-side performance metrics, resource utilization, and incident status across your fleet.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("No Servers Configured")
                .font(.system(size: 14, weight: .medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var compareTableView: some View {
        VStack(spacing: 0) {
            tableHeaderRow
            Divider()
            cpuRow
            Divider()
            memoryRow
            Divider()
            diskRow
            Divider()
            incidentsRow
            Divider()
            probesRow
            Divider()
            networkRow
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var tableHeaderRow: some View {
        HStack(spacing: 0) {
            Text("Metric")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .leading)

            ForEach(store.servers, id: \.id) { (server: ServerModel) in
                let mgr = pool.manager(for: server)
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .font(.system(size: 12, weight: .semibold))
                    HStack(spacing: 4) {
                        Circle()
                            .fill(mgr.state.isConnected ? (mgr.incidents.contains(where: { $0.status != .resolved }) ? Color.orange : Color.green) : Color.red)
                            .frame(width: 6, height: 6)
                        Text(mgr.state.displayStatus)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var cpuRow: some View {
        HStack(spacing: 0) {
            rowHeader(title: "CPU Usage", icon: "cpu")
            ForEach(store.servers, id: \.id) { (server: ServerModel) in
                let mgr = pool.manager(for: server)
                let cpu = mgr.currentMetrics?.cpu.usagePercent ?? 0
                Text(String(format: "%.1f%%", cpu))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(cpu > 85 ? .red : (cpu > 70 ? .orange : .primary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }

    private var memoryRow: some View {
        HStack(spacing: 0) {
            rowHeader(title: "Memory", icon: "memorychip")
            ForEach(store.servers, id: \.id) { (server: ServerModel) in
                let mgr = pool.manager(for: server)
                let mem = mgr.currentMetrics?.memory.usagePercent ?? 0
                let usedMB = (mgr.currentMetrics?.memory.usedBytes ?? 0) / 1024 / 1024
                Text(String(format: "%.1f%% (%d MB)", mem, usedMB))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(mem > 90 ? .red : (mem > 80 ? .orange : .primary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }

    private var diskRow: some View {
        HStack(spacing: 0) {
            rowHeader(title: "Disk Usage", icon: "internaldrive")
            ForEach(store.servers, id: \.id) { (server: ServerModel) in
                let mgr = pool.manager(for: server)
                let disk = mgr.currentMetrics?.disks.first?.usagePercent ?? 0
                Text(String(format: "%.1f%%", disk))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(disk > 85 ? .red : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }

    private var incidentsRow: some View {
        HStack(spacing: 0) {
            rowHeader(title: "Incidents", icon: "exclamationmark.octagon")
            ForEach(store.servers, id: \.id) { (server: ServerModel) in
                let mgr = pool.manager(for: server)
                let count = mgr.incidents.filter { $0.status != .resolved }.count
                Group {
                    if count == 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                            Text("Healthy")
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                        }
                    } else {
                        Text("\(count) Active")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }

    private var probesRow: some View {
        HStack(spacing: 0) {
            rowHeader(title: "Monitors", icon: "waveform.path.ecg")
            ForEach(store.servers, id: \.id) { (server: ServerModel) in
                let mgr = pool.manager(for: server)
                Text("\(mgr.monitors.filter { $0.isEnabled }.count) probes")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }

    private var networkRow: some View {
        HStack(spacing: 0) {
            rowHeader(title: "Network I/O", icon: "arrow.up.arrow.down")
            ForEach(store.servers, id: \.id) { (server: ServerModel) in
                let mgr = pool.manager(for: server)
                let rx = (mgr.currentMetrics?.network.rxBytesPerSec ?? 0) / 1024
                let tx = (mgr.currentMetrics?.network.txBytesPerSec ?? 0) / 1024
                Text(String(format: "↓%d KB/s ↑%d KB/s", rx, tx))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }

    private func rowHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 12, weight: .medium))
        }
        .frame(width: 140, alignment: .leading)
    }
}

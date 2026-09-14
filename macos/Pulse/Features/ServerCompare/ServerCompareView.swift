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
        .onAppear {
            for server in store.servers {
                let mgr = pool.manager(for: server)
                if mgr.state == .disconnected {
                    mgr.connect()
                }
            }
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
                CompareHeaderCell(server: server, manager: pool.manager(for: server))
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
                CompareCPUCell(manager: pool.manager(for: server))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }

    private var memoryRow: some View {
        HStack(spacing: 0) {
            rowHeader(title: "Memory", icon: "memorychip")
            ForEach(store.servers, id: \.id) { (server: ServerModel) in
                CompareMemoryCell(manager: pool.manager(for: server))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }

    private var diskRow: some View {
        HStack(spacing: 0) {
            rowHeader(title: "Disk Usage", icon: "internaldrive")
            ForEach(store.servers, id: \.id) { (server: ServerModel) in
                CompareDiskCell(manager: pool.manager(for: server))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }

    private var incidentsRow: some View {
        HStack(spacing: 0) {
            rowHeader(title: "Incidents", icon: "exclamationmark.octagon")
            ForEach(store.servers, id: \.id) { (server: ServerModel) in
                CompareIncidentsCell(manager: pool.manager(for: server))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }

    private var probesRow: some View {
        HStack(spacing: 0) {
            rowHeader(title: "Monitors", icon: "waveform.path.ecg")
            ForEach(store.servers, id: \.id) { (server: ServerModel) in
                CompareProbesCell(manager: pool.manager(for: server))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }

    private var networkRow: some View {
        HStack(spacing: 0) {
            rowHeader(title: "Network I/O", icon: "arrow.up.arrow.down")
            ForEach(store.servers, id: \.id) { (server: ServerModel) in
                CompareNetworkCell(manager: pool.manager(for: server))
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

private struct CompareHeaderCell: View {
    let server: ServerModel
    @ObservedObject var manager: ServerConnectionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(server.name)
                .font(.system(size: 12, weight: .semibold))
            HStack(spacing: 4) {
                Circle()
                    .fill(manager.state.isConnected ? (manager.incidents.contains(where: { $0.status != .resolved }) ? Color.orange : Color.green) : Color.red)
                    .frame(width: 6, height: 6)
                Text(manager.state.displayStatus)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

private struct CompareCPUCell: View {
    @ObservedObject var manager: ServerConnectionManager

    var body: some View {
        let cpu = manager.currentMetrics?.cpu.usagePercent ?? 0
        Text(String(format: "%.1f%%", cpu))
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .monospacedDigit()
            .foregroundColor(cpu > 85 ? .red : (cpu > 70 ? .orange : .primary))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
    }
}

private struct CompareMemoryCell: View {
    @ObservedObject var manager: ServerConnectionManager

    var body: some View {
        let mem = manager.currentMetrics?.memory.usagePercent ?? 0
        let usedMB = (manager.currentMetrics?.memory.usedBytes ?? 0) / 1024 / 1024
        Text(String(format: "%.1f%% (%d MB)", mem, usedMB))
            .font(.system(size: 12, design: .monospaced))
            .monospacedDigit()
            .foregroundColor(mem > 90 ? .red : (mem > 80 ? .orange : .primary))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
    }
}

private struct CompareDiskCell: View {
    @ObservedObject var manager: ServerConnectionManager

    var body: some View {
        let disk = manager.currentMetrics?.disks.first?.usagePercent ?? 0
        Text(String(format: "%.1f%%", disk))
            .font(.system(size: 12, design: .monospaced))
            .monospacedDigit()
            .foregroundColor(disk > 85 ? .red : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
    }
}

private struct CompareIncidentsCell: View {
    @ObservedObject var manager: ServerConnectionManager

    var body: some View {
        let count = manager.incidents.filter { $0.status != .resolved }.count
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

private struct CompareProbesCell: View {
    @ObservedObject var manager: ServerConnectionManager

    var body: some View {
        Text("\(manager.monitors.filter { $0.isEnabled }.count) probes")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
    }
}

private struct CompareNetworkCell: View {
    @ObservedObject var manager: ServerConnectionManager

    var body: some View {
        let rx = manager.currentMetrics?.network.rxBytesPerSec ?? 0
        let tx = manager.currentMetrics?.network.txBytesPerSec ?? 0
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.blue)
                Text(FormatUtils.rate(rx))
                    .foregroundColor(.primary)
            }

            HStack(spacing: 2) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.green)
                Text(FormatUtils.rate(tx))
                    .foregroundColor(.primary)
            }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

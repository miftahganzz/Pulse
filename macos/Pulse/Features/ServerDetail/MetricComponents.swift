import SwiftUI

public struct CPUMetricCard: View {
    let cpu: CPUMetrics

    public var body: some View {
        MetricCardView(
            title: "CPU (\(cpu.cores) Cores)",
            systemImage: "cpu",
            subtitle: String(format: "%.1f%%", cpu.usagePercent)
        ) {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(cpuColor(cpu.usagePercent))
                            .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(cpu.usagePercent / 100.0))), height: 8)
                    }
                }
                .frame(height: 8)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("User")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f%%", cpu.userPercent))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("System")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f%%", cpu.systemPercent))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Steal")
                            .font(.system(size: 10))
                            .foregroundColor(cpu.stealPercent > 5.0 ? .red : .secondary)
                        Text(String(format: "%.1f%%", cpu.stealPercent))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(cpu.stealPercent > 5.0 ? .red : .primary)
                    }
                    Spacer()
                }
            }
        }
    }

    private func cpuColor(_ pct: Double) -> Color {
        if pct > 85 { return .red }
        if pct > 70 { return .orange }
        return .blue
    }
}

public struct MemoryMetricCard: View {
    let mem: MemoryMetrics

    public var body: some View {
        MetricCardView(
            title: "Memory",
            systemImage: "memorychip",
            subtitle: "\(FormatUtils.bytes(mem.usedBytes)) / \(FormatUtils.bytes(mem.totalBytes))"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(memColor(mem.usagePercent))
                            .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(mem.usagePercent / 100.0))), height: 8)
                    }
                }
                .frame(height: 8)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Usage")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f%%", mem.usagePercent))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Available")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(FormatUtils.bytes(mem.availableBytes))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    if mem.swapTotalBytes > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Swap")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text("\(FormatUtils.bytes(mem.swapUsedBytes)) / \(FormatUtils.bytes(mem.swapTotalBytes))")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    private func memColor(_ pct: Double) -> Color {
        if pct > 90 { return .red }
        if pct > 75 { return .orange }
        return .green
    }
}

public struct DiskMetricCard: View {
    let disk: DiskMountItem

    public var body: some View {
        MetricCardView(
            title: "Disk (\(disk.mountPoint))",
            systemImage: "internaldrive",
            subtitle: "\(FormatUtils.bytes(disk.usedBytes)) / \(FormatUtils.bytes(disk.totalBytes))"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(diskColor(disk.usagePercent))
                            .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(disk.usagePercent / 100.0))), height: 8)
                    }
                }
                .frame(height: 8)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Usage")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f%%", disk.usagePercent))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Free")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(FormatUtils.bytes(disk.freeBytes))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    if disk.readBytesPerSec > 0 || disk.writeBytesPerSec > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Disk I/O")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text("R: \(FormatUtils.rate(disk.readBytesPerSec)) W: \(FormatUtils.rate(disk.writeBytesPerSec))")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    private func diskColor(_ pct: Double) -> Color {
        if pct > 90 { return .red }
        if pct > 80 { return .orange }
        return .purple
    }
}

public struct NetworkMetricCard: View {
    let network: NetworkMetrics

    public var body: some View {
        MetricCardView(
            title: "Network I/O",
            systemImage: "network",
            subtitle: "Total Interface Rate"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 24) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: 16))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Download")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(FormatUtils.rate(network.rxBytesPerSec))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        }
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 16))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Upload")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(FormatUtils.rate(network.txBytesPerSec))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        }
                    }

                    Spacer()
                }

                HStack(spacing: 16) {
                    Text("Total: ↓ \(FormatUtils.bytes(network.totalRxBytes))  ↑ \(FormatUtils.bytes(network.totalTxBytes))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)

                    if network.errors > 0 {
                        Text("Errors: \(network.errors)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.red)
                    }
                }
            }
        }
    }
}

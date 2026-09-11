import SwiftUI

public struct CPUMetricCard: View {
    let cpu: CPUMetrics

    public var body: some View {
        MetricCardView(
            title: "CPU (\(cpu.cores) Cores)",
            systemImage: "cpu",
            tintColor: cpuColor(cpu.usagePercent),
            subtitle: String(format: "%.1f%%", cpu.usagePercent)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Prominent Usage & Progress Bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(String(format: "%.1f", cpu.usagePercent))
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("%")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)

                        Spacer()
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 6)

                            Capsule()
                                .fill(cpuColor(cpu.usagePercent))
                                .frame(width: max(4, min(geo.size.width, geo.size.width * CGFloat(cpu.usagePercent / 100.0))), height: 6)
                        }
                    }
                    .frame(height: 6)
                }

                // Stats Columns
                HStack(spacing: 0) {
                    MetricStatColumn(label: "User", value: String(format: "%.1f%%", cpu.userPercent))
                    Divider().frame(height: 18).opacity(0.3)
                    MetricStatColumn(label: "System", value: String(format: "%.1f%%", cpu.systemPercent))
                    Divider().frame(height: 18).opacity(0.3)
                    MetricStatColumn(
                        label: "Steal",
                        value: String(format: "%.1f%%", cpu.stealPercent),
                        highlightColor: cpu.stealPercent > 5.0 ? .red : nil
                    )
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
            tintColor: memColor(mem.usagePercent),
            subtitle: "\(FormatUtils.bytes(mem.usedBytes)) / \(FormatUtils.bytes(mem.totalBytes))"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Prominent Usage & Progress Bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(String(format: "%.1f", mem.usagePercent))
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("%")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)

                        Spacer()
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 6)

                            Capsule()
                                .fill(memColor(mem.usagePercent))
                                .frame(width: max(4, min(geo.size.width, geo.size.width * CGFloat(mem.usagePercent / 100.0))), height: 6)
                        }
                    }
                    .frame(height: 6)
                }

                // Stats Columns
                HStack(spacing: 0) {
                    MetricStatColumn(label: "Used", value: FormatUtils.bytes(mem.usedBytes))
                    Divider().frame(height: 18).opacity(0.3)
                    MetricStatColumn(label: "Available", value: FormatUtils.bytes(mem.availableBytes))
                    if mem.swapTotalBytes > 0 {
                        Divider().frame(height: 18).opacity(0.3)
                        MetricStatColumn(label: "Swap", value: FormatUtils.bytes(mem.swapUsedBytes))
                    }
                }
            }
        }
    }

    private func memColor(_ pct: Double) -> Color {
        if pct > 90 { return .red }
        if pct > 75 { return .orange }
        return .indigo
    }
}

public struct DiskMetricCard: View {
    let disk: DiskMountItem

    public var body: some View {
        MetricCardView(
            title: "Disk (\(disk.mountPoint))",
            systemImage: "internaldrive",
            tintColor: diskColor(disk.usagePercent),
            subtitle: "\(FormatUtils.bytes(disk.usedBytes)) / \(FormatUtils.bytes(disk.totalBytes))"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Prominent Usage & Progress Bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(String(format: "%.1f", disk.usagePercent))
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("%")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)

                        Spacer()
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 6)

                            Capsule()
                                .fill(diskColor(disk.usagePercent))
                                .frame(width: max(4, min(geo.size.width, geo.size.width * CGFloat(disk.usagePercent / 100.0))), height: 6)
                        }
                    }
                    .frame(height: 6)
                }

                // Stats Columns
                HStack(spacing: 0) {
                    MetricStatColumn(label: "Used", value: FormatUtils.bytes(disk.usedBytes))
                    Divider().frame(height: 18).opacity(0.3)
                    MetricStatColumn(label: "Free", value: FormatUtils.bytes(disk.freeBytes))
                    if disk.readBytesPerSec > 0 || disk.writeBytesPerSec > 0 {
                        Divider().frame(height: 18).opacity(0.3)
                        MetricStatColumn(
                            label: "I/O Rate",
                            value: "↓\(FormatUtils.rate(disk.readBytesPerSec)) ↑\(FormatUtils.rate(disk.writeBytesPerSec))"
                        )
                    }
                }
            }
        }
    }

    private func diskColor(_ pct: Double) -> Color {
        if pct > 90 { return .red }
        if pct > 80 { return .orange }
        return .teal
    }
}

public struct NetworkMetricCard: View {
    let network: NetworkMetrics

    public var body: some View {
        MetricCardView(
            title: "Network I/O",
            systemImage: "network",
            tintColor: .green,
            subtitle: "All Interfaces"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    // Download Block
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.blue)
                            .frame(width: 22, height: 22)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Download")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(FormatUtils.rate(network.rxBytesPerSec))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().frame(height: 28).opacity(0.3)

                    // Upload Block
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.green)
                            .frame(width: 22, height: 22)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Upload")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(FormatUtils.rate(network.txBytesPerSec))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 8) {
                    Text("Total: ↓ \(FormatUtils.bytes(network.totalRxBytes)) · ↑ \(FormatUtils.bytes(network.totalTxBytes))")
                        .font(.system(size: 11, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(.secondary)

                    Spacer()

                    if network.errors > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 10))
                            Text("\(network.errors) errors")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
    }
}

private struct MetricStatColumn: View {
    let label: String
    let value: String
    var highlightColor: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(highlightColor ?? .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


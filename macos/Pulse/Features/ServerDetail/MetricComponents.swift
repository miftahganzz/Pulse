import SwiftUI

public struct MiniSparklineView: View {
    let points: [Double]
    let color: Color
    let minBound: Double
    let maxBound: Double

    public init(points: [Double], color: Color, minBound: Double = 0.0, maxBound: Double = 100.0) {
        self.points = points
        self.color = color
        self.minBound = minBound
        self.maxBound = maxBound
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            if points.count >= 2 {
                let range = max(1.0, maxBound - minBound)
                let step = w / CGFloat(points.count - 1)

                let path = Path { p in
                    for (index, val) in points.enumerated() {
                        let clampedVal = max(minBound, min(maxBound, val))
                        let normalizedY = 1.0 - CGFloat((clampedVal - minBound) / range)
                        let pt = CGPoint(x: CGFloat(index) * step, y: normalizedY * (h - 2) + 1)
                        if index == 0 {
                            p.move(to: pt)
                        } else {
                            p.addLine(to: pt)
                        }
                    }
                }

                let areaPath = Path { p in
                    p.addPath(path)
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h))
                    p.closeSubpath()
                }

                ZStack {
                    areaPath
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.18), color.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    path
                        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            } else if let single = points.first {
                let range = max(1.0, maxBound - minBound)
                let clamped = max(minBound, min(maxBound, single))
                let normalizedY = 1.0 - CGFloat((clamped - minBound) / range)
                let y = normalizedY * (h - 2) + 1

                Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: w, y: y))
                }
                .stroke(color.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .clipped()
    }
}

public struct CPUMetricCard: View {
    let cpu: CPUMetrics
    let history: [Double]
    let loadAvg: LoadAvgMetrics?

    public init(cpu: CPUMetrics, history: [Double] = [], loadAvg: LoadAvgMetrics? = nil) {
        self.cpu = cpu
        self.history = history
        self.loadAvg = loadAvg
    }

    public var body: some View {
        MetricCardView(
            title: "CPU (\(cpu.cores) Cores)",
            systemImage: "cpu",
            tintColor: cpuColor(cpu.usagePercent),
            subtitle: String(format: "%.1f%%", cpu.usagePercent)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Top Header: Primary Usage & Sparkline
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(String(format: "%.1f", cpu.usagePercent))
                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text("%")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }

                        if let load = loadAvg {
                            Text("Load: \(String(format: "%.2f, %.2f, %.2f", load.load1, load.load5, load.load15))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    if !history.isEmpty {
                        VStack(alignment: .trailing, spacing: 2) {
                            MiniSparklineView(points: history, color: cpuColor(cpu.usagePercent))
                                .frame(width: 86, height: 28)
                                .background(Color.primary.opacity(0.02))
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                            Text("60s trend")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                }

                // Progress Bar
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
    let history: [Double]

    public init(mem: MemoryMetrics, history: [Double] = []) {
        self.mem = mem
        self.history = history
    }

    public var body: some View {
        MetricCardView(
            title: "Memory",
            systemImage: "memorychip",
            tintColor: memColor(mem.usagePercent),
            subtitle: "\(FormatUtils.bytes(mem.usedBytes)) / \(FormatUtils.bytes(mem.totalBytes))"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Top Header: Primary Usage & Sparkline
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(String(format: "%.1f", mem.usagePercent))
                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text("%")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }

                        Text("\(FormatUtils.bytes(mem.usedBytes)) of \(FormatUtils.bytes(mem.totalBytes))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if !history.isEmpty {
                        VStack(alignment: .trailing, spacing: 2) {
                            MiniSparklineView(points: history, color: memColor(mem.usagePercent))
                                .frame(width: 86, height: 28)
                                .background(Color.primary.opacity(0.02))
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                            Text("60s trend")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                }

                // Progress Bar
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

                // Stats Columns
                HStack(spacing: 0) {
                    MetricStatColumn(label: "Used", value: FormatUtils.bytes(mem.usedBytes))
                    Divider().frame(height: 18).opacity(0.3)
                    MetricStatColumn(label: "Available", value: FormatUtils.bytes(mem.availableBytes))
                    if mem.swapTotalBytes > 0 {
                        Divider().frame(height: 18).opacity(0.3)
                        MetricStatColumn(
                            label: "Swap",
                            value: FormatUtils.bytes(mem.swapUsedBytes),
                            highlightColor: mem.swapUsedBytes > 0 ? .orange : nil
                        )
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

    public init(disk: DiskMountItem) {
        self.disk = disk
    }

    public var body: some View {
        MetricCardView(
            title: "Storage (\(disk.mountPoint))",
            systemImage: "internaldrive",
            tintColor: diskColor(disk.usagePercent),
            subtitle: "\(FormatUtils.bytes(disk.freeBytes)) Free"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Usage Headline
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(String(format: "%.1f", disk.usagePercent))
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("%")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(disk.filesystem.uppercased())
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                // Storage Capacity Bar
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

                // Stats Columns
                HStack(spacing: 0) {
                    MetricStatColumn(label: "Used", value: FormatUtils.bytes(disk.usedBytes))
                    Divider().frame(height: 18).opacity(0.3)
                    MetricStatColumn(label: "Free", value: FormatUtils.bytes(disk.freeBytes))
                    Divider().frame(height: 18).opacity(0.3)
                    if disk.readBytesPerSec > 0 || disk.writeBytesPerSec > 0 {
                        MetricStatColumn(
                            label: "I/O Rate",
                            value: "↓\(FormatUtils.rate(disk.readBytesPerSec)) ↑\(FormatUtils.rate(disk.writeBytesPerSec))"
                        )
                    } else {
                        MetricStatColumn(label: "Total", value: FormatUtils.bytes(disk.totalBytes))
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

    public init(network: NetworkMetrics) {
        self.network = network
    }

    public var body: some View {
        MetricCardView(
            title: "Network Throughput",
            systemImage: "network",
            tintColor: .green,
            subtitle: "All Interfaces"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Tier 1: Primary Throughput Headline (matches Disk headline height)
                HStack(alignment: .firstTextBaseline) {
                    let totalRate = network.rxBytesPerSec + network.txBytesPerSec
                    let rateString = FormatUtils.rate(totalRate)
                    let parts = rateString.split(separator: " ")
                    let num = parts.first.map(String.init) ?? "0"
                    let unit = parts.dropFirst().joined(separator: " ")

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(num)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(unit.isEmpty ? "B/s" : unit)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.blue)
                            Text(FormatUtils.rate(network.rxBytesPerSec))
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundColor(.primary)
                        }

                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.green)
                            Text(FormatUtils.rate(network.txBytesPerSec))
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundColor(.primary)
                        }
                    }
                }

                // Tier 2: Throughput Split Activity Bar (height 6 matches Disk bar)
                GeometryReader { geo in
                    let total = max(1.0, network.rxBytesPerSec + network.txBytesPerSec)
                    let rxRatio = CGFloat(network.rxBytesPerSec / total)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(network.txBytesPerSec > 0 ? Color.green.opacity(0.8) : Color.primary.opacity(0.06))
                            .frame(height: 6)

                        Capsule()
                            .fill(network.rxBytesPerSec > 0 ? Color.blue : Color.clear)
                            .frame(width: max(network.rxBytesPerSec > 0 ? 4 : 0, min(geo.size.width, geo.size.width * rxRatio)), height: 6)
                    }
                }
                .frame(height: 6)

                // Tier 3: 3 Stats Columns (matches Disk 3-column stats with height 18 dividers)
                HStack(spacing: 0) {
                    MetricStatColumn(label: "Downloaded", value: FormatUtils.bytes(network.totalRxBytes))
                    Divider().frame(height: 18).opacity(0.3)
                    MetricStatColumn(label: "Uploaded", value: FormatUtils.bytes(network.totalTxBytes))
                    Divider().frame(height: 18).opacity(0.3)
                    if network.errors > 0 {
                        MetricStatColumn(
                            label: "Errors",
                            value: "\(network.errors) drops",
                            highlightColor: .red
                        )
                    } else {
                        MetricStatColumn(label: "Health", value: "0 dropped")
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


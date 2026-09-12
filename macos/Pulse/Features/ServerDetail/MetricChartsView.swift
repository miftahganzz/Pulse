import SwiftUI
import Charts

public struct MetricChartsView: View {
    let history: [HistoricalDataPoint]
    @State private var selectedMetric = 0 // 0: CPU, 1: RAM, 2: Network

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Historical Trends")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                Picker("", selection: $selectedMetric) {
                    Text("CPU").tag(0)
                    Text("Memory").tag(1)
                    Text("Network").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }

            if history.count < 2 {
                VStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Collecting metric snapshots (10s intervals)...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    switch selectedMetric {
                    case 0:
                        cpuChart
                    case 1:
                        memoryChart
                    case 2:
                        networkChart
                    default:
                        EmptyView()
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
            }
        }
    }

    private var cpuChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CPU Utilization (%)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                if let last = history.last {
                    Text(String(format: "Now: %.1f%%", last.cpuPercent))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
            }

            Chart(history) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("CPU %", point.cpuPercent)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.blue)

                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("CPU %", point.cpuPercent)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.25), Color.blue.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100])
            }
            .frame(height: 120)
        }
    }

    private var memoryChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("RAM Utilization (%)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                if let last = history.last {
                    Text(String(format: "Now: %.1f%%", last.memoryPercent))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
            }

            Chart(history) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("RAM %", point.memoryPercent)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.green)

                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("RAM %", point.memoryPercent)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.green.opacity(0.25), Color.green.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100])
            }
            .frame(height: 120)
        }
    }

    private var networkChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Network Throughput")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                if let last = history.last {
                    Text("↓ \(FormatUtils.rate(last.networkRxBytesPerSec))  ↑ \(FormatUtils.rate(last.networkTxBytesPerSec))")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
            }

            Chart(history) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Rx Rate", point.networkRxBytesPerSec),
                    series: .value("Stream", "Download")
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.blue)

                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Tx Rate", point.networkTxBytesPerSec),
                    series: .value("Stream", "Upload")
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.green)
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 120)
        }
    }
}

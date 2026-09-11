import Foundation

public struct HistoricalDataPoint: Identifiable, Codable, Sendable {
    public var id: Date { timestamp }
    public let timestamp: Date
    public let cpuPercent: Double
    public let memoryPercent: Double
    public let networkRxBytesPerSec: Double
    public let networkTxBytesPerSec: Double
    public let diskUsedBytes: Int64
    public let diskTotalBytes: Int64

    public init(
        timestamp: Date,
        cpuPercent: Double,
        memoryPercent: Double,
        networkRxBytesPerSec: Double,
        networkTxBytesPerSec: Double,
        diskUsedBytes: Int64 = 0,
        diskTotalBytes: Int64 = 0
    ) {
        self.timestamp = timestamp
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.networkRxBytesPerSec = networkRxBytesPerSec
        self.networkTxBytesPerSec = networkTxBytesPerSec
        self.diskUsedBytes = diskUsedBytes
        self.diskTotalBytes = diskTotalBytes
    }

    public var diskUsagePercent: Double {
        guard diskTotalBytes > 0 else { return 0.0 }
        return Double(diskUsedBytes) / Double(diskTotalBytes) * 100.0
    }
}

public struct TrendAnalysisResult: Sendable {
    public let cpuDelta: Double       // e.g. +4.2%
    public let memoryDelta: Double    // e.g. -1.5%
    public let diskDeltaBytes: Int64  // growth in bytes
    public let diskGrowthPerDayBytes: Double
    public let estimatedDaysToFull: Double? // nil if shrinking or stationary
}

public enum MetricsHistoryStore {
    private static let maxDataPoints = 8640 // up to 24h at 10s interval (or downsampled)

    public static func loadHistory(forServerId serverId: UUID) -> [HistoricalDataPoint] {
        let key = "pulse.history.\(serverId.uuidString)"
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([HistoricalDataPoint].self, from: data)
        } catch {
            return []
        }
    }

    public static func appendSnapshot(_ snapshot: MetricsSnapshot, forServerId serverId: UUID) -> [HistoricalDataPoint] {
        var existing = loadHistory(forServerId: serverId)

        var totalDiskUsed: Int64 = 0
        var totalDiskCapacity: Int64 = 0
        for d in snapshot.disks {
            totalDiskUsed += Int64(d.usedBytes)
            totalDiskCapacity += Int64(d.totalBytes)
        }

        let newPoint = HistoricalDataPoint(
            timestamp: snapshot.timestamp,
            cpuPercent: snapshot.cpu.usagePercent,
            memoryPercent: snapshot.memory.usagePercent,
            networkRxBytesPerSec: snapshot.network.rxBytesPerSec,
            networkTxBytesPerSec: snapshot.network.txBytesPerSec,
            diskUsedBytes: totalDiskUsed,
            diskTotalBytes: totalDiskCapacity
        )
        existing.append(newPoint)

        if existing.count > maxDataPoints {
            existing.removeFirst(existing.count - maxDataPoints)
        }

        let key = "pulse.history.\(serverId.uuidString)"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(existing) {
            UserDefaults.standard.set(data, forKey: key)
        }

        return existing
    }

    /// Calculates resource trends and estimated disk growth over available data points
    public static func analyzeTrends(for dataPoints: [HistoricalDataPoint]) -> TrendAnalysisResult {
        guard dataPoints.count >= 2, let first = dataPoints.first, let last = dataPoints.last else {
            return TrendAnalysisResult(
                cpuDelta: 0,
                memoryDelta: 0,
                diskDeltaBytes: 0,
                diskGrowthPerDayBytes: 0,
                estimatedDaysToFull: nil
            )
        }

        let cpuDelta = last.cpuPercent - first.cpuPercent
        let memoryDelta = last.memoryPercent - first.memoryPercent
        let diskDeltaBytes = last.diskUsedBytes - first.diskUsedBytes

        let timeDiffSeconds = last.timestamp.timeIntervalSince(first.timestamp)
        guard timeDiffSeconds > 60 else {
            return TrendAnalysisResult(
                cpuDelta: cpuDelta,
                memoryDelta: memoryDelta,
                diskDeltaBytes: diskDeltaBytes,
                diskGrowthPerDayBytes: 0,
                estimatedDaysToFull: nil
            )
        }

        // Daily rate of disk growth
        let dailyGrowthBytes = (Double(diskDeltaBytes) / timeDiffSeconds) * 86400.0

        var estimatedDays: Double? = nil
        if dailyGrowthBytes > 1024 * 1024 { // growing more than 1MB/day
            let remainingBytes = Double(last.diskTotalBytes - last.diskUsedBytes)
            if remainingBytes > 0 {
                estimatedDays = remainingBytes / dailyGrowthBytes
            }
        }

        return TrendAnalysisResult(
            cpuDelta: cpuDelta,
            memoryDelta: memoryDelta,
            diskDeltaBytes: diskDeltaBytes,
            diskGrowthPerDayBytes: dailyGrowthBytes,
            estimatedDaysToFull: estimatedDays
        )
    }
}

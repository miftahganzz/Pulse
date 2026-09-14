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
    public static let maxDataPoints = 360 // In-memory sliding buffer (e.g. 30-60m trend)

    /// Purges bloated legacy history from UserDefaults to eliminate disk thrashing on macOS
    public static func purgeLegacyUserDefaultsCache() {
        let keys = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix("pulse.history.") }
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    public static func loadHistory(forServerId serverId: UUID) -> [HistoricalDataPoint] {
        // Pure in-memory cache architecture; legacy keys are purged
        return []
    }

    /// Appends a new metric point purely in memory without disk or JSON overhead (O(1) execution)
    public static func appendSnapshot(_ snapshot: MetricsSnapshot, to existing: inout [HistoricalDataPoint]) {
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
    }

    /// Overload for existing callers returning modified array
    public static func appendSnapshot(_ snapshot: MetricsSnapshot, forServerId serverId: UUID, currentHistory: [HistoricalDataPoint] = []) -> [HistoricalDataPoint] {
        var updated = currentHistory
        appendSnapshot(snapshot, to: &updated)
        return updated
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

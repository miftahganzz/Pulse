import Foundation

public struct CPUMetrics: Codable, Equatable, Sendable {
    public let usagePercent: Double
    public let userPercent: Double
    public let systemPercent: Double
    public let idlePercent: Double
    public let stealPercent: Double
    public let cores: Int

    enum CodingKeys: String, CodingKey {
        case usagePercent = "usage_percent"
        case userPercent = "user_percent"
        case systemPercent = "system_percent"
        case idlePercent = "idle_percent"
        case stealPercent = "steal_percent"
        case cores
    }

    public init(
        usagePercent: Double = 0,
        userPercent: Double = 0,
        systemPercent: Double = 0,
        idlePercent: Double = 100,
        stealPercent: Double = 0,
        cores: Int = 1
    ) {
        self.usagePercent = usagePercent
        self.userPercent = userPercent
        self.systemPercent = systemPercent
        self.idlePercent = idlePercent
        self.stealPercent = stealPercent
        self.cores = cores
    }
}

public struct MemoryMetrics: Codable, Equatable, Sendable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let availableBytes: UInt64
    public let freeBytes: UInt64
    public let usagePercent: Double
    public let swapTotalBytes: UInt64
    public let swapUsedBytes: UInt64

    enum CodingKeys: String, CodingKey {
        case totalBytes = "total_bytes"
        case usedBytes = "used_bytes"
        case availableBytes = "available_bytes"
        case freeBytes = "free_bytes"
        case usagePercent = "usage_percent"
        case swapTotalBytes = "swap_total_bytes"
        case swapUsedBytes = "swap_used_bytes"
    }

    public init(
        totalBytes: UInt64 = 0,
        usedBytes: UInt64 = 0,
        availableBytes: UInt64 = 0,
        freeBytes: UInt64 = 0,
        usagePercent: Double = 0,
        swapTotalBytes: UInt64 = 0,
        swapUsedBytes: UInt64 = 0
    ) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
        self.freeBytes = freeBytes
        self.usagePercent = usagePercent
        self.swapTotalBytes = swapTotalBytes
        self.swapUsedBytes = swapUsedBytes
    }
}

public struct DiskMountItem: Identifiable, Codable, Equatable, Sendable {
    public var id: String { mountPoint }
    public let mountPoint: String
    public let filesystem: String
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let freeBytes: UInt64
    public let usagePercent: Double
    public let readBytesPerSec: Double
    public let writeBytesPerSec: Double

    enum CodingKeys: String, CodingKey {
        case mountPoint = "mount_point"
        case filesystem
        case totalBytes = "total_bytes"
        case usedBytes = "used_bytes"
        case freeBytes = "free_bytes"
        case usagePercent = "usage_percent"
        case readBytesPerSec = "read_bytes_per_sec"
        case writeBytesPerSec = "write_bytes_per_sec"
    }

    public init(
        mountPoint: String,
        filesystem: String = "ext4",
        totalBytes: UInt64 = 0,
        usedBytes: UInt64 = 0,
        freeBytes: UInt64 = 0,
        usagePercent: Double = 0,
        readBytesPerSec: Double = 0,
        writeBytesPerSec: Double = 0
    ) {
        self.mountPoint = mountPoint
        self.filesystem = filesystem
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.freeBytes = freeBytes
        self.usagePercent = usagePercent
        self.readBytesPerSec = readBytesPerSec
        self.writeBytesPerSec = writeBytesPerSec
    }
}

public struct NetworkMetrics: Codable, Equatable, Sendable {
    public let rxBytesPerSec: Double
    public let txBytesPerSec: Double
    public let totalRxBytes: UInt64
    public let totalTxBytes: UInt64
    public let rxPacketsPerSec: Double
    public let txPacketsPerSec: Double
    public let errors: UInt64

    enum CodingKeys: String, CodingKey {
        case rxBytesPerSec = "rx_bytes_per_sec"
        case txBytesPerSec = "tx_bytes_per_sec"
        case totalRxBytes = "total_rx_bytes"
        case totalTxBytes = "total_tx_bytes"
        case rxPacketsPerSec = "rx_packets_per_sec"
        case txPacketsPerSec = "tx_packets_per_sec"
        case errors
    }

    public init(
        rxBytesPerSec: Double = 0,
        txBytesPerSec: Double = 0,
        totalRxBytes: UInt64 = 0,
        totalTxBytes: UInt64 = 0,
        rxPacketsPerSec: Double = 0,
        txPacketsPerSec: Double = 0,
        errors: UInt64 = 0
    ) {
        self.rxBytesPerSec = rxBytesPerSec
        self.txBytesPerSec = txBytesPerSec
        self.totalRxBytes = totalRxBytes
        self.totalTxBytes = totalTxBytes
        self.rxPacketsPerSec = rxPacketsPerSec
        self.txPacketsPerSec = txPacketsPerSec
        self.errors = errors
    }
}

public struct LoadAvgMetrics: Codable, Equatable, Sendable {
    public let load1: Double
    public let load5: Double
    public let load15: Double

    public init(load1: Double = 0, load5: Double = 0, load15: Double = 0) {
        self.load1 = load1
        self.load5 = load5
        self.load15 = load15
    }
}

public struct MetricsSnapshot: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let cpu: CPUMetrics
    public let memory: MemoryMetrics
    public let disks: [DiskMountItem]
    public let network: NetworkMetrics
    public let loadAvg: LoadAvgMetrics
    public let uptimeSeconds: Int64

    enum CodingKeys: String, CodingKey {
        case timestamp
        case cpu
        case memory
        case disks
        case network
        case loadAvg = "load_avg"
        case uptimeSeconds = "uptime_seconds"
    }

    public init(
        timestamp: Date = Date(),
        cpu: CPUMetrics = CPUMetrics(),
        memory: MemoryMetrics = MemoryMetrics(),
        disks: [DiskMountItem] = [],
        network: NetworkMetrics = NetworkMetrics(),
        loadAvg: LoadAvgMetrics = LoadAvgMetrics(),
        uptimeSeconds: Int64 = 0
    ) {
        self.timestamp = timestamp
        self.cpu = cpu
        self.memory = memory
        self.disks = disks
        self.network = network
        self.loadAvg = loadAvg
        self.uptimeSeconds = uptimeSeconds
    }

    public var primaryDisk: DiskMountItem? {
        disks.first { $0.mountPoint == "/" } ?? disks.first
    }
}

public enum FormatUtils {
    public static func bytes(_ bytes: UInt64) -> String {
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useAll]
        bcf.countStyle = .memory
        return bcf.string(fromByteCount: Int64(bytes))
    }

    public static func rate(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1024 * 1024 * 1024 {
            return String(format: "%.1f GB/s", bytesPerSec / (1024 * 1024 * 1024))
        } else if bytesPerSec >= 1024 * 1024 {
            return String(format: "%.1f MB/s", bytesPerSec / (1024 * 1024))
        } else if bytesPerSec >= 1024 {
            return String(format: "%.1f KB/s", bytesPerSec / 1024)
        } else {
            return String(format: "%.0f B/s", bytesPerSec)
        }
    }

    public static func maskedAddress(_ address: String, isMasked: Bool = true) -> String {
        guard isMasked else { return address }
        let parts = address.split(separator: ".")
        if parts.count == 4 && parts.allSatisfy({ Int($0) != nil }) {
            return "\(parts[0]).\(parts[1]).•••.••"
        }
        if address.contains(".") {
            let components = address.split(separator: ".")
            if let first = components.first, components.count >= 2 {
                let prefix = first.prefix(4)
                let suffix = components.dropFirst().joined(separator: ".")
                return "\(prefix)•••••.\(suffix)"
            }
        }
        if address.count > 6 {
            return "\(address.prefix(4))••••"
        }
        return "••••••"
    }
}

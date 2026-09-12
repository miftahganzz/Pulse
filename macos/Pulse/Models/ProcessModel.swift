import Foundation

public struct ProcessItem: Identifiable, Codable, Equatable, Sendable {
    public var id: Int { pid }
    public let pid: Int
    public let ppid: Int
    public let name: String
    public let user: String
    public let cpuPercent: Double
    public let memoryRSSBytes: UInt64
    public let readBytesSec: Int64?
    public let writeBytesSec: Int64?
    public let openSockets: Int?
    public let state: String
    public let command: String

    enum CodingKeys: String, CodingKey {
        case pid
        case ppid
        case name
        case user
        case cpuPercent = "cpu_percent"
        case memoryRSSBytes = "memory_rss_bytes"
        case readBytesSec = "read_bytes_sec"
        case writeBytesSec = "write_bytes_sec"
        case openSockets = "open_sockets"
        case state
        case command
    }

    public init(
        pid: Int,
        ppid: Int = 0,
        name: String,
        user: String,
        cpuPercent: Double = 0.0,
        memoryRSSBytes: UInt64 = 0,
        readBytesSec: Int64? = nil,
        writeBytesSec: Int64? = nil,
        openSockets: Int? = nil,
        state: String = "Running",
        command: String = ""
    ) {
        self.pid = pid
        self.ppid = ppid
        self.name = name
        self.user = user
        self.cpuPercent = cpuPercent
        self.memoryRSSBytes = memoryRSSBytes
        self.readBytesSec = readBytesSec
        self.writeBytesSec = writeBytesSec
        self.openSockets = openSockets
        self.state = state
        self.command = command
    }

    public var formattedIO: String {
        guard let r = readBytesSec, let w = writeBytesSec, (r > 0 || w > 0) else { return "—" }
        return "↓ \(ByteCountFormatter.string(fromByteCount: r, countStyle: .file))/s  ↑ \(ByteCountFormatter.string(fromByteCount: w, countStyle: .file))/s"
    }
}

public struct ProcessesSnapshot: Codable, Equatable, Sendable {
    public let processes: [ProcessItem]
}

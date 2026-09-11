import Foundation

public struct ProcessItem: Identifiable, Codable, Equatable, Sendable {
    public var id: Int { pid }
    public let pid: Int
    public let ppid: Int
    public let name: String
    public let user: String
    public let cpuPercent: Double
    public let memoryRSSBytes: UInt64
    public let state: String
    public let command: String

    enum CodingKeys: String, CodingKey {
        case pid
        case ppid
        case name
        case user
        case cpuPercent = "cpu_percent"
        case memoryRSSBytes = "memory_rss_bytes"
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
        state: String = "Running",
        command: String = ""
    ) {
        self.pid = pid
        self.ppid = ppid
        self.name = name
        self.user = user
        self.cpuPercent = cpuPercent
        self.memoryRSSBytes = memoryRSSBytes
        self.state = state
        self.command = command
    }
}

public struct ProcessesSnapshot: Codable, Equatable, Sendable {
    public let processes: [ProcessItem]
}

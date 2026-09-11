import XCTest
@testable import Pulse

final class MetricsDecodingTests: XCTestCase {
    func testDecodeMetricsSnapshot() throws {
        let json = """
        {
            "type": "metrics.snapshot",
            "version": 1,
            "timestamp": "2026-09-11T00:00:00Z",
            "payload": {
                "timestamp": "2026-09-11T00:00:00Z",
                "cpu": {
                    "usage_percent": 14.5,
                    "user_percent": 8.0,
                    "system_percent": 6.5,
                    "idle_percent": 85.5,
                    "steal_percent": 0.0,
                    "cores": 4
                },
                "memory": {
                    "total_bytes": 17179869184,
                    "used_bytes": 8589934592,
                    "available_bytes": 8589934592,
                    "free_bytes": 4294967296,
                    "usage_percent": 50.0,
                    "swap_total_bytes": 0,
                    "swap_used_bytes": 0
                },
                "disks": [
                    {
                        "mount_point": "/",
                        "filesystem": "ext4",
                        "total_bytes": 500000000000,
                        "used_bytes": 200000000000,
                        "free_bytes": 300000000000,
                        "usage_percent": 40.0,
                        "read_bytes_per_sec": 102400.0,
                        "write_bytes_per_sec": 204800.0
                    },
                    {
                        "mount_point": "/data",
                        "filesystem": "ext4",
                        "total_bytes": 1000000000000,
                        "used_bytes": 400000000000,
                        "free_bytes": 600000000000,
                        "usage_percent": 40.0,
                        "read_bytes_per_sec": 0.0,
                        "write_bytes_per_sec": 0.0
                    }
                ],
                "network": {
                    "rx_bytes_per_sec": 512000.0,
                    "tx_bytes_per_sec": 128000.0,
                    "total_rx_bytes": 1000000000,
                    "total_tx_bytes": 500000000,
                    "rx_packets_per_sec": 100.0,
                    "tx_packets_per_sec": 50.0,
                    "errors": 0
                },
                "load_avg": {
                    "load1": 0.42,
                    "load5": 0.35,
                    "load15": 0.28
                },
                "uptime_seconds": 3600
            }
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(ProtocolEnvelope<MetricsSnapshot>.self, from: data)

        XCTAssertEqual(envelope.type, "metrics.snapshot")
        XCTAssertEqual(envelope.version, 1)

        let metrics = envelope.payload
        XCTAssertEqual(metrics.cpu.usagePercent, 14.5)
        XCTAssertEqual(metrics.cpu.cores, 4)
        XCTAssertEqual(metrics.memory.usagePercent, 50.0)
        XCTAssertEqual(metrics.disks.count, 2)
        XCTAssertEqual(metrics.disks[0].mountPoint, "/")
        XCTAssertEqual(metrics.disks[1].mountPoint, "/data")
        XCTAssertEqual(metrics.primaryDisk?.mountPoint, "/")
        XCTAssertEqual(metrics.network.rxBytesPerSec, 512000.0)
        XCTAssertEqual(metrics.loadAvg.load1, 0.42)
        XCTAssertEqual(metrics.uptimeSeconds, 3600)
    }

    func testMetricsHistoryAppendAndRetention() {
        let serverId = UUID()
        var snapshot = MetricsSnapshot()
        let history = MetricsHistoryStore.appendSnapshot(snapshot, forServerId: serverId)

        XCTAssertFalse(history.isEmpty)
        XCTAssertEqual(history.last?.cpuPercent, snapshot.cpu.usagePercent)
    }
}

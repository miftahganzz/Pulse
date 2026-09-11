import XCTest
@testable import Pulse

final class ProcessAndServiceTests: XCTestCase {
    func testDecodeProcessesSnapshot() throws {
        let json = """
        {
            "type": "processes.snapshot",
            "version": 1,
            "timestamp": "2026-09-11T00:00:00Z",
            "payload": {
                "processes": [
                    {
                        "pid": 1042,
                        "ppid": 1,
                        "name": "node",
                        "user": "app",
                        "cpu_percent": 18.4,
                        "memory_rss_bytes": 440401920,
                        "state": "Running",
                        "command": "node server.js"
                    }
                ]
            }
        }
        """

        let data = json.data(using: .utf8)!
        let envelope = try JSONDecoder().decode(ProtocolEnvelope<ProcessesSnapshot>.self, from: data)

        XCTAssertEqual(envelope.type, "processes.snapshot")
        XCTAssertEqual(envelope.payload.processes.count, 1)

        let proc = envelope.payload.processes[0]
        XCTAssertEqual(proc.pid, 1042)
        XCTAssertEqual(proc.name, "node")
        XCTAssertEqual(proc.cpuPercent, 18.4)
        XCTAssertEqual(proc.state, "Running")
    }

    func testDecodeServicesSnapshot() throws {
        let json = """
        {
            "type": "services.snapshot",
            "version": 1,
            "timestamp": "2026-09-11T00:00:00Z",
            "payload": {
                "services": [
                    {
                        "name": "nginx.service",
                        "description": "A high performance web server and reverse proxy",
                        "load_state": "loaded",
                        "active_state": "active",
                        "sub_state": "running"
                    },
                    {
                        "name": "redis.service",
                        "description": "Redis in-memory data structure store",
                        "load_state": "loaded",
                        "active_state": "failed",
                        "sub_state": "failed"
                    }
                ]
            }
        }
        """

        let data = json.data(using: .utf8)!
        let envelope = try JSONDecoder().decode(ProtocolEnvelope<ServicesSnapshot>.self, from: data)

        XCTAssertEqual(envelope.type, "services.snapshot")
        XCTAssertEqual(envelope.payload.services.count, 2)

        let nginx = envelope.payload.services[0]
        XCTAssertTrue(nginx.isRunning)
        XCTAssertFalse(nginx.isFailed)

        let redis = envelope.payload.services[1]
        XCTAssertFalse(redis.isRunning)
        XCTAssertTrue(redis.isFailed)
    }
}

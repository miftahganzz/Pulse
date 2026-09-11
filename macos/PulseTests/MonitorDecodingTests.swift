import XCTest
@testable import Pulse

final class MonitorDecodingTests: XCTestCase {
    func testDiscoveredServiceDecoding() throws {
        let json = """
        {
            "timestamp": "2026-09-11T08:00:00Z",
            "services": [
                {
                    "id": "nginx.service",
                    "provider_type": "systemd",
                    "name": "nginx.service",
                    "description": "Nginx HTTP Server",
                    "status": "active (running)",
                    "metadata": {
                        "active_state": "active",
                        "load_state": "loaded"
                    }
                },
                {
                    "id": "c123456",
                    "provider_type": "docker",
                    "name": "postgres",
                    "description": "Image: postgres:15",
                    "status": "running",
                    "metadata": {
                        "image": "postgres:15"
                    }
                }
            ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(DiscoveryResultPayload.self, from: json)

        XCTAssertEqual(payload.services.count, 2)
        XCTAssertEqual(payload.services[0].id, "nginx.service")
        XCTAssertEqual(payload.services[0].providerType, "systemd")
        XCTAssertEqual(payload.services[1].name, "postgres")
        XCTAssertEqual(payload.services[1].providerType, "docker")
    }

    func testHealthCheckResultDecoding() throws {
        let json = """
        [
            {
                "id": "probe-http",
                "status": "healthy",
                "message": "HTTP 200 OK (24 ms)",
                "latency_ms": 24,
                "last_checked": "2026-09-11T08:05:00Z"
            },
            {
                "id": "probe-tcp",
                "status": "down",
                "message": "TCP connect failed: connection refused",
                "latency_ms": 12,
                "last_checked": "2026-09-11T08:05:00Z"
            }
        ]
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let results = try decoder.decode([HealthCheckResultItem].self, from: json)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].id, "probe-http")
        XCTAssertEqual(results[0].status, "healthy")
        XCTAssertEqual(results[0].latencyMs, 24)
        XCTAssertEqual(results[1].status, "down")
    }

    func testMonitorStorePersistence() throws {
        let serverId = UUID()
        let monitors = [
            MonitorItem(serverId: serverId, name: "API Gate", type: .http, target: "https://api.test/health"),
            MonitorItem(serverId: serverId, name: "Database", type: .tcp, target: "127.0.0.1:5432")
        ]

        MonitorStore.saveMonitors(monitors, forServerId: serverId)
        let loaded = MonitorStore.loadMonitors(forServerId: serverId)

        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].name, "API Gate")
        XCTAssertEqual(loaded[0].type, .http)
        XCTAssertEqual(loaded[1].name, "Database")
        XCTAssertEqual(loaded[1].type, .tcp)

        let ignored: Set<String> = ["service-a", "service-b"]
        MonitorStore.saveIgnored(ignored, forServerId: serverId)
        let loadedIgnored = MonitorStore.loadIgnored(forServerId: serverId)

        XCTAssertEqual(loadedIgnored, ignored)
    }
}

import XCTest
@testable import Pulse

final class SecurityDecodingTests: XCTestCase {
    func testDecodeSecuritySnapshot() throws {
        let json = """
        {
            "type": "security.ports_snapshot",
            "version": 1,
            "timestamp": "2026-09-11T19:50:00Z",
            "payload": {
                "ports": [
                    {
                        "port": 6379,
                        "protocol": "tcp",
                        "ip": "0.0.0.0",
                        "process_name": "redis-server",
                        "pid": 1024,
                        "exposure": "public",
                        "is_sensitive": true,
                        "recommendation": "Redis database exposed publicly. Bind to 127.0.0.1 or Tailscale."
                    },
                    {
                        "port": 5432,
                        "protocol": "tcp",
                        "ip": "127.0.0.1",
                        "process_name": "postgres",
                        "pid": 1100,
                        "exposure": "localhost",
                        "is_sensitive": false
                    },
                    {
                        "port": 22,
                        "protocol": "tcp",
                        "ip": "0.0.0.0",
                        "process_name": "sshd",
                        "pid": 800,
                        "exposure": "public",
                        "is_sensitive": false
                    }
                ],
                "firewall": {
                    "is_active": true,
                    "type": "ufw",
                    "default_incoming": "deny"
                },
                "public_count": 2,
                "sensitive_count": 1
            }
        }
        """

        let data = json.data(using: .utf8)!
        let env = try JSONDecoder().decode(ProtocolEnvelope<SecuritySnapshot>.self, from: data)

        XCTAssertEqual(env.type, "security.ports_snapshot")
        XCTAssertEqual(env.payload.ports.count, 3)
        XCTAssertEqual(env.payload.publicCount, 2)
        XCTAssertEqual(env.payload.sensitiveCount, 1)

        let redis = env.payload.ports[0]
        XCTAssertEqual(redis.port, 6379)
        XCTAssertEqual(redis.protocolType, "tcp")
        XCTAssertEqual(redis.processName, "redis-server")
        XCTAssertEqual(redis.pid, 1024)
        XCTAssertEqual(redis.exposure, .public)
        XCTAssertTrue(redis.isSensitive)
        XCTAssertNotNil(redis.recommendation)

        let postgres = env.payload.ports[1]
        XCTAssertEqual(postgres.port, 5432)
        XCTAssertEqual(postgres.exposure, .localhost)
        XCTAssertFalse(postgres.isSensitive)

        let fw = env.payload.firewall
        XCTAssertTrue(fw.isActive)
        XCTAssertEqual(fw.type, "ufw")
        XCTAssertEqual(fw.defaultIncoming, "deny")
    }

    func testPortExposureBadges() {
        XCTAssertEqual(PortExposure.public.displayTitle, "Public (0.0.0.0)")
        XCTAssertEqual(PortExposure.private.displayTitle, "Private / VPN")
        XCTAssertEqual(PortExposure.localhost.displayTitle, "Localhost Only")

        XCTAssertEqual(PortExposure.public.iconName, "globe")
        XCTAssertEqual(PortExposure.private.iconName, "lock.shield")
        XCTAssertEqual(PortExposure.localhost.iconName, "laptopcomputer")
    }
}

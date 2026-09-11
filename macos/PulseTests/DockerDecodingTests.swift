import XCTest
@testable import Pulse

final class DockerDecodingTests: XCTestCase {
    func testDecodeDockerStatusResponse() throws {
        let json = """
        {
            "available": true,
            "version": "24.0.7",
            "containers": [
                {
                    "id": "e3b0c44298fc",
                    "name": "redis-prod",
                    "image": "redis:7-alpine",
                    "state": "running",
                    "status": "Up 3 days",
                    "created_at": 1700000000,
                    "ports": ["0.0.0.0:6379->6379/tcp"]
                },
                {
                    "id": "a1b2c3d4e5f6",
                    "name": "postgres-staging",
                    "image": "postgres:16",
                    "state": "exited",
                    "status": "Exited (0) 2 hours ago",
                    "created_at": 1699990000,
                    "ports": []
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let status = try JSONDecoder().decode(DockerStatusResponse.self, from: data)

        XCTAssertTrue(status.available)
        XCTAssertEqual(status.version, "24.0.7")
        XCTAssertEqual(status.containers.count, 2)

        let redis = status.containers[0]
        XCTAssertEqual(redis.id, "e3b0c44298fc")
        XCTAssertEqual(redis.name, "redis-prod")
        XCTAssertTrue(redis.isRunning)
        XCTAssertFalse(redis.isPaused)
        XCTAssertEqual(redis.ports, ["0.0.0.0:6379->6379/tcp"])

        let postgres = status.containers[1]
        XCTAssertEqual(postgres.name, "postgres-staging")
        XCTAssertFalse(postgres.isRunning)
    }

    func testDecodeDockerLogsResponse() throws {
        let json = """
        {
            "container_id": "e3b0c44298fc",
            "logs": "1:M 11 Sep 00:00:00.000 * Ready to accept connections tcp\\n"
        }
        """

        let data = json.data(using: .utf8)!
        let res = try JSONDecoder().decode(DockerLogsResponse.self, from: data)

        XCTAssertEqual(res.containerId, "e3b0c44298fc")
        XCTAssertTrue(res.logs.contains("Ready to accept connections"))
    }
}

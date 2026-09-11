import XCTest
@testable import Pulse

final class Phase7InfrastructureTests: XCTestCase {
    func testPhase7MonitorTypesAndSFsymbols() {
        let types: [MonitorType] = [.mysql, .mongodb, .nginx, .caddy, .cloudflared, .custom]
        for t in types {
            XCTAssertFalse(t.displayName.isEmpty)
            XCTAssertFalse(t.sfSymbol.isEmpty)
        }
    }

    func testTrendAnalysisAndDiskGrowth() {
        let now = Date()
        let p1 = HistoricalDataPoint(
            timestamp: now.addingTimeInterval(-3600), // 1 hour ago
            cpuPercent: 20.0,
            memoryPercent: 50.0,
            networkRxBytesPerSec: 1000,
            networkTxBytesPerSec: 1000,
            diskUsedBytes: 50 * 1024 * 1024 * 1024, // 50 GB
            diskTotalBytes: 100 * 1024 * 1024 * 1024 // 100 GB
        )

        let p2 = HistoricalDataPoint(
            timestamp: now,
            cpuPercent: 25.0,
            memoryPercent: 52.0,
            networkRxBytesPerSec: 2000,
            networkTxBytesPerSec: 2000,
            diskUsedBytes: 51 * 1024 * 1024 * 1024, // 51 GB (+1 GB in 1 hr)
            diskTotalBytes: 100 * 1024 * 1024 * 1024
        )

        let result = MetricsHistoryStore.analyzeTrends(for: [p1, p2])
        XCTAssertEqual(result.cpuDelta, 5.0, accuracy: 0.01)
        XCTAssertEqual(result.memoryDelta, 2.0, accuracy: 0.01)
        XCTAssertEqual(result.diskDeltaBytes, 1 * 1024 * 1024 * 1024)
        XCTAssertGreaterThan(result.diskGrowthPerDayBytes, 0)
        XCTAssertNotNil(result.estimatedDaysToFull)
    }

    func testServiceDependencyStoreCycleAndDedup() {
        let serverId = UUID()
        let dep1 = ServiceDependency(serverId: serverId, sourceMonitorId: "api", targetMonitorId: "postgres", type: .requires)
        let depDuplicate = ServiceDependency(serverId: serverId, sourceMonitorId: "api", targetMonitorId: "postgres", type: .requires)
        let depSelfLoop = ServiceDependency(serverId: serverId, sourceMonitorId: "api", targetMonitorId: "api", type: .requires)

        var list = DependencyStore.addDependency(dep1, forServerId: serverId)
        XCTAssertTrue(list.contains(where: { $0.sourceMonitorId == "api" && $0.targetMonitorId == "postgres" }))

        list = DependencyStore.addDependency(depDuplicate, forServerId: serverId)
        let matches = list.filter { $0.sourceMonitorId == "api" && $0.targetMonitorId == "postgres" }
        XCTAssertEqual(matches.count, 1, "Should not add duplicate dependencies")

        list = DependencyStore.addDependency(depSelfLoop, forServerId: serverId)
        let selfLoops = list.filter { $0.sourceMonitorId == "api" && $0.targetMonitorId == "api" }
        XCTAssertEqual(selfLoops.count, 0, "Should reject self-loop dependencies")
    }

    func testMonitorHealthCheckRequestEncoding() throws {
        let req = MonitorHealthCheckRequest(
            id: "m-1",
            name: "API Health",
            type: "http",
            target: "https://api.movnix.web.id/health",
            expectedBody: "\"status\":\"ok\"",
            expectedCode: 200,
            expectedOutput: nil
        )

        let data = try JSONEncoder().encode(req)
        let str = String(data: data, encoding: .utf8)!
        XCTAssertTrue(str.contains("expected_body"))
        XCTAssertTrue(str.contains("expected_code"))
    }
}

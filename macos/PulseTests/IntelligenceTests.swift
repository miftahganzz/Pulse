import XCTest
@testable import Pulse

final class IntelligenceTests: XCTestCase {
    let serverId = UUID()

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "pulse.dependencies.\(serverId.uuidString)")
    }

    func testTransitiveDownstreamTraversal() {
        // Setup DAG:
        // api -> postgres
        // worker -> postgres
        // web -> api
        // Thus when postgres fails: blast radius is {api, worker, web} (count: 3)
        let dep1 = ServiceDependency(serverId: serverId, sourceMonitorId: "api", targetMonitorId: "postgres", type: .requires)
        let dep2 = ServiceDependency(serverId: serverId, sourceMonitorId: "worker", targetMonitorId: "postgres", type: .requires)
        let dep3 = ServiceDependency(serverId: serverId, sourceMonitorId: "web", targetMonitorId: "api", type: .requires)

        _ = DependencyStore.addDependency(dep1, forServerId: serverId)
        _ = DependencyStore.addDependency(dep2, forServerId: serverId)
        _ = DependencyStore.addDependency(dep3, forServerId: serverId)

        let downstream = IntelligenceEngine.shared.getTransitiveDownstream(serverId: serverId, rootMonitorId: "postgres")
        XCTAssertEqual(downstream.count, 3)
        XCTAssertTrue(downstream.contains("api"))
        XCTAssertTrue(downstream.contains("worker"))
        XCTAssertTrue(downstream.contains("web"))
    }

    func testDeterministicRootCauseAnalysisOnCascade() {
        // Scenario:
        // postgres crashes at T0
        // api crashes at T0 + 2s
        // web crashes at T0 + 4s
        let now = Date()
        let incPostgres = IncidentItem(
            serverId: serverId,
            monitorId: "postgres",
            title: "PostgreSQL Database",
            target: "localhost:5432",
            severity: .critical,
            status: .ongoing,
            startedAt: now,
            reason: "connection refused: 5432",
            consecutiveFailures: 3
        )

        let incApi = IncidentItem(
            serverId: serverId,
            monitorId: "api",
            title: "Movnix API",
            target: "movnix-api",
            severity: .critical,
            status: .ongoing,
            startedAt: now.addingTimeInterval(2.0),
            reason: "HTTP 500 Internal Server Error",
            consecutiveFailures: 2
        )

        let dep = ServiceDependency(serverId: serverId, sourceMonitorId: "api", targetMonitorId: "postgres", type: .requires)
        _ = DependencyStore.addDependency(dep, forServerId: serverId)

        let monitors = [
            MonitorItem(id: "postgres", serverId: serverId, name: "PostgreSQL Database", type: .postgres, target: "localhost:5432"),
            MonitorItem(id: "api", serverId: serverId, name: "Movnix API", type: .docker, target: "movnix-api")
        ]

        let analyzed = IntelligenceEngine.shared.analyzeRootCauses(
            serverId: serverId,
            incidents: [incPostgres, incApi],
            monitors: monitors
        )

        XCTAssertEqual(analyzed.count, 2)
        guard let postgresAnalysis = analyzed.first(where: { $0.monitorId == "postgres" })?.rootCauseAnalysis else {
            XCTFail("Missing root cause analysis on postgres")
            return
        }

        XCTAssertEqual(postgresAnalysis.suspectedRootCauseMonitorId, "postgres")
        XCTAssertEqual(postgresAnalysis.suspectedRootCauseName, "PostgreSQL Database")
        XCTAssertGreaterThanOrEqual(postgresAnalysis.confidenceScore, 75)
        XCTAssertEqual(postgresAnalysis.confidenceLevel, .high)
        XCTAssertEqual(postgresAnalysis.blastRadiusCount, 1)
        XCTAssertTrue(postgresAnalysis.affectedServiceNames.contains("Movnix API"))
        XCTAssertFalse(postgresAnalysis.evidenceList.isEmpty)

        // Verify downstream incident also points to Postgres as root cause
        guard let apiAnalysis = analyzed.first(where: { $0.monitorId == "api" })?.rootCauseAnalysis else {
            XCTFail("Missing root cause analysis on API")
            return
        }
        XCTAssertEqual(apiAnalysis.suspectedRootCauseMonitorId, "postgres")
        XCTAssertEqual(apiAnalysis.confidenceLevel, .high)
    }

    func testStatisticalAnomalyDetection() {
        // Normal baseline: around 20.0% CPU with little variance
        let history: [Double] = [19.5, 20.1, 20.4, 19.8, 20.0, 20.2, 19.9, 20.3, 20.1, 19.7]

        // Normal reading: 20.5% -> No anomaly
        let normalAnomaly = IntelligenceEngine.shared.detectAnomalies(metricName: "CPU", history: history, currentValue: 20.5)
        XCTAssertNil(normalAnomaly)

        // Huge spike: 85.0% -> Severe anomaly (|z| >= 2.0)
        let spikeAnomaly = IntelligenceEngine.shared.detectAnomalies(metricName: "CPU", history: history, currentValue: 85.0)
        XCTAssertNotNil(spikeAnomaly)
        XCTAssertEqual(spikeAnomaly?.metricName, "CPU")
        XCTAssertGreaterThan(spikeAnomaly?.zScore ?? 0, 2.0)
    }

    func testCrossServerOutageCorrelation() {
        let now = Date()
        let server1 = UUID()
        let server2 = UUID()
        let server3 = UUID()

        // 3 servers disconnect within 3 seconds
        let concurrentDisconnects: [UUID: Date] = [
            server1: now,
            server2: now.addingTimeInterval(1.2),
            server3: now.addingTimeInterval(2.8)
        ]

        let result = IntelligenceEngine.shared.detectConcurrentServerOutages(
            disconnectTimestamps: concurrentDisconnects,
            windowSeconds: 8.0
        )

        XCTAssertTrue(result.isCorrelated)
        XCTAssertNotNil(result.explanation)
        XCTAssertTrue(result.explanation?.contains("gateway") ?? false || result.explanation?.contains("simultaneously") ?? false)
    }
}

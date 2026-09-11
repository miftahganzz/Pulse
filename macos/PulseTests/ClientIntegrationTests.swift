import XCTest
@testable import Pulse

final class ClientIntegrationTests: XCTestCase, @unchecked Sendable, PulseAgentClientDelegate {
    var stateExpectation: XCTestExpectation?
    var identityExpectation: XCTestExpectation?
    var heartbeatExpectation: XCTestExpectation?
    var metricsExpectation: XCTestExpectation?
    var receivedIdentity: AgentIdentity?
    var receivedMetrics: MetricsSnapshot?

    private var didFulfillIdentity = false
    private var didFulfillMetrics = false
    private var agentProcess: Process?

    func client(_ client: PulseAgentClient, didUpdateState state: ConnectionState) {
        if state == .connected {
            stateExpectation?.fulfill()
        }
    }

    func client(_ client: PulseAgentClient, didReceiveIdentity identity: AgentIdentity) {
        self.receivedIdentity = identity
        if !didFulfillIdentity {
            didFulfillIdentity = true
            identityExpectation?.fulfill()
        }
    }

    func client(_ client: PulseAgentClient, didReceiveHeartbeat heartbeat: HeartbeatPayload) {
        heartbeatExpectation?.fulfill()
    }

    func client(_ client: PulseAgentClient, didReceiveMetrics metrics: MetricsSnapshot) {
        self.receivedMetrics = metrics
        if !didFulfillMetrics {
            didFulfillMetrics = true
            metricsExpectation?.fulfill()
        }
    }

    func client(_ client: PulseAgentClient, didFailWithError error: Error) {}

    override func setUp() {
        super.setUp()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/Users/miftah/Documents/pulse/agent/pulse-agent/bin/pulse-agent")
        proc.arguments = ["--config", "/Users/miftah/Documents/pulse/agent/pulse-agent/bin/test-agent.json"]
        try? proc.run()
        self.agentProcess = proc

        // Wait until port 8443 is open (up to 5 seconds)
        let start = Date()
        while Date().timeIntervalSince(start) < 5.0 {
            let sock = socket(AF_INET, SOCK_STREAM, 0)
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(8443).bigEndian
            inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)
            let res = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            close(sock)
            if res == 0 {
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    override func tearDown() {
        agentProcess?.terminate()
        agentProcess = nil
        super.tearDown()
    }

    func testLiveClientConnectionAndHeartbeat() {
        guard let tokenData = try? Data(contentsOf: URL(fileURLWithPath: "/Users/miftah/Documents/pulse/agent/pulse-agent/bin/test-agent.json")),
              let json = try? JSONSerialization.jsonObject(with: tokenData) as? [String: Any],
              let token = json["auth_token"] as? String else {
            XCTFail("Could not read test agent token")
            return
        }

        stateExpectation = expectation(description: "Connected to agent")
        identityExpectation = expectation(description: "Received identity")
        heartbeatExpectation = expectation(description: "Received heartbeat")
        metricsExpectation = expectation(description: "Received metrics snapshot")

        let client = PulseAgentClient(host: "127.0.0.1", port: 8443, token: token)
        client.delegate = self
        client.connect()

        wait(for: [stateExpectation!, identityExpectation!, heartbeatExpectation!, metricsExpectation!], timeout: 25.0)

        XCTAssertNotNil(receivedIdentity)
        XCTAssertEqual(receivedIdentity?.agentVersion, "0.1.0")

        XCTAssertNotNil(receivedMetrics)
        XCTAssertGreaterThan(receivedMetrics?.memory.totalBytes ?? 0, 0)
        XCTAssertGreaterThan(receivedMetrics?.disks.first?.totalBytes ?? 0, 0)

        client.disconnect()
    }
}

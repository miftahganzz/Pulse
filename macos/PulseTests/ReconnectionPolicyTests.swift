import XCTest
@testable import Pulse

final class ReconnectionPolicyTests: XCTestCase {
    func testExponentialBackoffSequence() {
        var policy = ReconnectionPolicy(backoffIntervals: [1.0, 2.0, 5.0, 10.0, 30.0])
        
        XCTAssertEqual(policy.nextInterval(), 1.0)
        XCTAssertEqual(policy.attempt, 1)
        XCTAssertEqual(policy.nextInterval(), 2.0)
        XCTAssertEqual(policy.attempt, 2)
        XCTAssertEqual(policy.nextInterval(), 5.0)
        XCTAssertEqual(policy.attempt, 3)
        XCTAssertEqual(policy.nextInterval(), 10.0)
        XCTAssertEqual(policy.attempt, 4)
        XCTAssertEqual(policy.nextInterval(), 30.0)
        XCTAssertEqual(policy.attempt, 5)
        
        // Stays at max interval
        XCTAssertEqual(policy.nextInterval(), 30.0)
        XCTAssertEqual(policy.attempt, 6)

        policy.reset()
        XCTAssertEqual(policy.attempt, 0)
        XCTAssertEqual(policy.nextInterval(), 1.0)
    }

    func testConnectionStateDisplay() {
        XCTAssertEqual(ConnectionState.disconnected.displayTitle, "Disconnected")
        XCTAssertEqual(ConnectionState.connecting.displayTitle, "Connecting...")
        XCTAssertEqual(ConnectionState.connected.displayTitle, "Connected")
        XCTAssertTrue(ConnectionState.connected.isConnected)
        XCTAssertFalse(ConnectionState.disconnected.isConnected)
    }
}

import Foundation

public enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int, nextRetrySeconds: Int)
    case offline(reason: OfflineReason)

    public enum OfflineReason: String, Equatable, Sendable {
        case noNetwork = "No Network Connection"
        case hostUnreachable = "Server Unreachable"
    }

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var isOffline: Bool {
        switch self {
        case .disconnected, .reconnecting, .offline:
            return true
        case .connecting, .connected:
            return false
        }
    }

    public var displayTitle: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .reconnecting(let attempt, _):
            return "Reconnecting (\(attempt))..."
        case .offline(let reason):
            switch reason {
            case .noNetwork:
                return "Offline — Please connect to network"
            case .hostUnreachable:
                return "Server Offline"
            }
        }
    }

    public var displayStatus: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .reconnecting:
            return "Reconnecting"
        case .offline(let reason):
            return reason.rawValue
        }
    }
}

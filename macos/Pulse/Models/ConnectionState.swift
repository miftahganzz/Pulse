import Foundation

public enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int, nextRetrySeconds: Int)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var isOffline: Bool {
        switch self {
        case .disconnected, .reconnecting:
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
        case .reconnecting(let attempt, let nextRetry):
            return "Reconnecting (Attempt \(attempt), retry in \(nextRetry)s)..."
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
        }
    }
}

import SwiftUI

public struct ServerStatusBadge: View {
    public let state: ConnectionState

    public init(state: ConnectionState) {
        self.state = state
    }

    public var body: some View {
        HStack(spacing: 5) {
            if case .offline(let reason) = state, reason == .noNetwork {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(statusColor)
            } else {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
            }

            Text(state.displayTitle)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.12))
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch state {
        case .connected:
            return .green
        case .connecting:
            return .blue
        case .reconnecting:
            return .orange
        case .offline:
            return .orange
        case .disconnected:
            return .secondary
        }
    }
}

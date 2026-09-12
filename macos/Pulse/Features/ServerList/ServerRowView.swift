import SwiftUI

@MainActor
public struct ServerRowView: View {
    let server: ServerModel
    let manager: ServerConnectionManager

    public init(server: ServerModel, manager: ServerConnectionManager) {
        self.server = server
        self.manager = manager
    }

    public var body: some View {
        HStack(spacing: 10) {
            if case .offline(let reason) = manager.state, reason == .noNetwork {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(statusColor)
                    .frame(width: 8, height: 8)
            } else {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(server.name)
                        .font(.system(size: 13, weight: .medium))

                    let activeIncidents = manager.incidents.filter { $0.status != .resolved }
                    if !activeIncidents.isEmpty {
                        Text("\(activeIncidents.count)")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.2))
                            .foregroundColor(.red)
                            .cornerRadius(3)
                    }
                }

                HStack(spacing: 4) {
                    Text(verbatim: "\(server.address):\(server.port)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)

                    if let cpu = manager.currentMetrics?.cpu.usagePercent, manager.state.isConnected {
                        Text("• \(Int(cpu))% CPU")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    // Custom tags
                    ForEach(server.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(.accentColor)
                            .cornerRadius(3)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(server.name), \(statusDescription)")
    }

    private var statusDescription: String {
        let activeIncidents = manager.incidents.filter { $0.status != .resolved }
        if !activeIncidents.isEmpty {
            return "\(activeIncidents.count) active incidents"
        }
        return manager.state.displayStatus
    }

    private var statusColor: Color {
        let activeIncidents = manager.incidents.filter { $0.status != .resolved }
        if !activeIncidents.isEmpty {
            return .red
        }
        switch manager.state {
        case .connected:    return .green
        case .connecting:   return .blue
        case .reconnecting: return .orange
        case .offline:      return .orange
        case .disconnected: return .secondary
        }
    }
}

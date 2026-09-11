import SwiftUI

public struct ActivityLogView: View {
    @ObservedObject var manager: ServerConnectionManager

    public init(manager: ServerConnectionManager) {
        self.manager = manager
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Action Audit Log")
                        .font(.headline)
                    Text("Recorded operations and service actions executed on this server.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !manager.auditLogs.isEmpty {
                    Button("Clear History") {
                        manager.clearActivityLogs()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if manager.auditLogs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("No actions recorded yet.")
                        .font(.system(size: 13, weight: .medium))
                    Text("Actions performed like restarting containers or reloading PM2 will be logged here.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            } else {
                List(manager.auditLogs) { log in
                    HStack(spacing: 12) {
                        Image(systemName: iconForStatus(log.status))
                            .foregroundColor(colorForStatus(log.status))
                            .font(.system(size: 14))
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(log.actionName.uppercased())
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.12))
                                    .cornerRadius(3)

                                Text(log.target)
                                    .font(.system(size: 12, weight: .semibold))

                                Text("by \(log.actor)")
                                    .font(.system(size: 9, weight: .medium))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(log.actor == "Automation" ? Color.purple.opacity(0.15) : Color.blue.opacity(0.15))
                                    .foregroundColor(log.actor == "Automation" ? .purple : .blue)
                                    .cornerRadius(3)

                                Spacer()

                                if let ver = log.verification {
                                    Text(ver)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(ver.contains("Recovered") ? .green : .secondary)
                                }

                                Text("\(log.durationMs) ms")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)

                                Text(formattedDate(log.timestamp))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Text(log.message)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
                .cornerRadius(8)
            }
        }
        .padding(16)
    }

    private func iconForStatus(_ status: String) -> String {
        switch status.lowercased() {
        case "success": return "checkmark.circle.fill"
        case "timeout": return "clock.badge.exclamationmark"
        default: return "xmark.circle.fill"
        }
    }

    private func colorForStatus(_ status: String) -> Color {
        switch status.lowercased() {
        case "success": return .green
        case "timeout": return .orange
        default: return .red
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

import SwiftUI

public struct ServiceDetailSheet: View {
    @ObservedObject var manager: ServerConnectionManager
    let monitor: MonitorItem
    @Environment(\.dismiss) private var dismiss

    @State private var selectedAction: String = ""
    @State private var actionMessage: String? = nil
    @State private var isPerformingAction = false
    @State private var activePreview: ActionPreviewDetails? = nil

    public init(manager: ServerConnectionManager, monitor: MonitorItem) {
        self.manager = manager
        self.monitor = monitor
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: monitor.type.iconName)
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(monitor.name)
                            .font(.system(size: 18, weight: .bold))

                        HStack(spacing: 4) {
                            Circle()
                                .fill(monitor.status.color)
                                .frame(width: 8, height: 8)
                            Text(monitor.status.displayName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(monitor.status.color)
                        }
                    }

                    Text(monitor.target)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Details & Metrics
            VStack(alignment: .leading, spacing: 12) {
                Text("Health & Diagnostics")
                    .font(.headline)

                VStack(spacing: 8) {
                    infoRow(label: "Provider Type", value: monitor.type.displayName)
                    infoRow(label: "Target", value: monitor.target)
                    if let latency = monitor.latencyMs {
                        infoRow(label: "Round-trip Latency", value: "\(latency) ms")
                    }
                    if let msg = monitor.message, !msg.isEmpty {
                        infoRow(label: "Status Message", value: msg)
                    }
                    if let lastChecked = monitor.lastChecked {
                        infoRow(label: "Last Checked", value: formattedDate(lastChecked))
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            // Actions & Remediation Section
            let availableActions = actionsForMonitor(monitor)
            if !availableActions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Service Operations")
                            .font(.headline)

                        Spacer()

                        if let vStatus = manager.verificationStatuses[monitor.id] {
                            HStack(spacing: 4) {
                                Image(systemName: vStatus.sfSymbol)
                                    .font(.system(size: 11))
                                Text(vStatus.displayName)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(vStatus.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(vStatus.color.opacity(0.12))
                            .cornerRadius(4)
                        }
                    }

                    if let actionMsg = actionMessage {
                        Text(actionMsg)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                    }

                    HStack(spacing: 10) {
                        ForEach(availableActions, id: \.self) { act in
                            Button {
                                let preview = RemediationEngine.shared.buildActionPreview(
                                    actionId: act,
                                    targetName: monitor.name,
                                    serverName: manager.serverName,
                                    monitorId: monitor.id,
                                    currentStatus: monitor.status
                                )
                                activePreview = preview
                            } label: {
                                HStack {
                                    if isPerformingAction && selectedAction == act {
                                        ProgressView().scaleEffect(0.6)
                                    }
                                    Text(labelForAction(act))
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(tintForAction(act))
                            .disabled(isPerformingAction)
                        }
                    }
                }

                // Remediation Policy Config
                VStack(alignment: .leading, spacing: 8) {
                    Text("Auto-Remediation Policy")
                        .font(.headline)

                    HStack(spacing: 12) {
                        Image(systemName: "bolt.shield.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatic Recovery Gate")
                                .font(.system(size: 12, weight: .semibold))
                            Text("When failed 2+ consecutive probes, trigger restart after safety checks.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: {
                                manager.remediationPolicies.first(where: { $0.monitorId == monitor.id })?.enabled ?? false
                            },
                            set: { enabled in
                                var policy = manager.remediationPolicies.first(where: { $0.monitorId == monitor.id }) ?? RemediationPolicy(
                                    serverId: manager.serverId,
                                    monitorId: monitor.id,
                                    actionId: availableActions.first ?? "restart",
                                    approvalMode: .manual
                                )
                                policy.enabled = enabled
                                manager.saveRemediationPolicy(policy)
                            }
                        ))
                        .toggleStyle(.switch)
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.04))
                    .cornerRadius(6)
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 500, height: 480)
        .sheet(item: $activePreview) { preview in
            ActionPreviewSheet(preview: preview) {
                performAction(preview.actionId)
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
        }
    }

    private func actionsForMonitor(_ item: MonitorItem) -> [String] {
        switch item.type {
        case .docker:
            return ["docker.restart", "docker.stop", "docker.start"]
        case .pm2:
            return ["pm2.restart", "pm2.reload", "pm2.stop"]
        case .systemd:
            return ["systemd.restart", "systemd.stop"]
        default:
            return []
        }
    }

    private func labelForAction(_ act: String) -> String {
        let parts = act.split(separator: ".")
        if parts.count == 2 {
            return parts[1].capitalized
        }
        return act.capitalized
    }

    private func tintForAction(_ act: String) -> Color {
        if act.contains("stop") {
            return .red
        } else if act.contains("reload") {
            return .blue
        }
        return .orange
    }

    private func performAction(_ action: String) {
        isPerformingAction = true
        actionMessage = "Executing \(labelForAction(action))..."

        manager.executeServiceAction(action: action, target: monitor.target, monitorId: monitor.id) { result in
            Task { @MainActor in
                self.isPerformingAction = false
                switch result {
                case .success(let msg):
                    self.actionMessage = "✓ \(msg)"
                case .failure(let err):
                    self.actionMessage = "✗ Error: \(err.localizedDescription)"
                }
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

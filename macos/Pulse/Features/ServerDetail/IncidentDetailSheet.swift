import SwiftUI

public struct IncidentDetailSheet: View {
    let incident: IncidentItem
    @ObservedObject var manager: ServerConnectionManager
    @Environment(\.dismiss) private var dismiss
    @State private var activePreview: ActionPreviewDetails? = nil

    public init(incident: IncidentItem, manager: ServerConnectionManager) {
        self.incident = incident
        self.manager = manager
    }

    private var targetMonitor: MonitorItem? {
        if let monId = incident.monitorId {
            return manager.monitors.first(where: { $0.id == monId })
        }
        return nil
    }

    private var recommendedActionId: String? {
        guard let mon = targetMonitor else { return nil }
        switch mon.type {
        case .docker: return "docker.restart"
        case .pm2: return "pm2.reload"
        case .systemd: return "systemd.restart"
        default: return nil
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Sheet Header
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: incident.severity.sfSymbol)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(incident.severity.color)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(incident.title)
                            .font(.system(size: 15, weight: .bold))
                        Text("Target: \(incident.target)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Remediation Recommendation Card
                    if incident.status != .resolved, let mon = targetMonitor, let actionId = recommendedActionId {
                        HStack(spacing: 12) {
                            Image(systemName: "bolt.shield.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.orange)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Remediation Recommended")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Automated diagnostic recommends executing **\(actionId)** to restore service.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button {
                                activePreview = RemediationEngine.shared.buildActionPreview(
                                    actionId: actionId,
                                    targetName: mon.name,
                                    serverName: manager.serverName,
                                    monitorId: mon.id,
                                    currentStatus: mon.status
                                )
                            } label: {
                                Label("Review & Execute", systemImage: "play.circle.fill")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .controlSize(.small)
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                        )
                        .cornerRadius(8)
                    }

                    // 1. Root Cause Analysis Card (Deterministic Intelligence)
                    if let rca = incident.rootCauseAnalysis {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "brain.head.profile")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.purple)

                                Text("Intelligence & Root Cause")
                                    .font(.system(size: 13, weight: .bold))

                                Spacer()

                                HStack(spacing: 4) {
                                    Image(systemName: rca.confidenceLevel.sfSymbol)
                                        .font(.system(size: 11))
                                    Text("\(rca.confidenceLevel.displayName) (\(rca.confidenceScore)%)")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(rca.confidenceLevel.color.opacity(0.15))
                                .foregroundColor(rca.confidenceLevel.color)
                                .cornerRadius(4)
                            }

                            Divider()

                            HStack(alignment: .top, spacing: 16) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("PROBABLE ROOT CAUSE")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.secondary)
                                    Text(rca.suspectedRootCauseName)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.primary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 3) {
                                    Text("BLAST RADIUS")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.secondary)
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.triangle.pull")
                                            .font(.system(size: 11))
                                            .foregroundColor(.orange)
                                        Text("\(rca.blastRadiusCount) affected")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                }
                            }

                            if !rca.affectedServiceNames.isEmpty {
                                HStack(spacing: 4) {
                                    Text("Impacted:")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.secondary)
                                    ForEach(rca.affectedServiceNames, id: \.self) { name in
                                        Text(name)
                                            .font(.system(size: 10, weight: .medium))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.1))
                                            .cornerRadius(3)
                                    }
                                }
                            }

                            // Evidence Checklist
                            VStack(alignment: .leading, spacing: 5) {
                                Text("CORROBORATED EVIDENCE")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .padding(.top, 4)

                                ForEach(rca.evidenceList, id: \.self) { evidence in
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(.purple)
                                            .padding(.top, 2)
                                        Text(evidence)
                                            .font(.system(size: 11))
                                            .foregroundColor(.primary)
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .background(Color.purple.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.purple.opacity(0.25), lineWidth: 1)
                        )
                        .cornerRadius(8)
                    }

                    // 2. Incident Summary & State Card
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Incident Overview")
                            .font(.system(size: 13, weight: .bold))

                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                            GridRow {
                                Text("Status:")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(incident.status.color)
                                        .frame(width: 7, height: 7)
                                    Text(incident.status.displayName)
                                        .font(.system(size: 11, weight: .semibold))
                                }
                            }

                            GridRow {
                                Text("Severity:")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                HStack(spacing: 5) {
                                    Image(systemName: incident.severity.sfSymbol)
                                        .font(.system(size: 11))
                                        .foregroundColor(incident.severity.color)
                                    Text(incident.severity.displayName)
                                        .font(.system(size: 11, weight: .semibold))
                                }
                            }

                            GridRow {
                                Text("Downtime:")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Text(incident.formattedDuration)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            }

                            GridRow {
                                Text("Started At:")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Text(incident.startedAt.formatted(date: .abbreviated, time: .standard))
                                    .font(.system(size: 11))
                            }

                            if let recovered = incident.recoveredAt {
                                GridRow {
                                    Text("Recovered At:")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    Text(recovered.formatted(date: .abbreviated, time: .standard))
                                        .font(.system(size: 11))
                                }
                            }

                            GridRow {
                                Text("Probe Failures:")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Text("\(incident.consecutiveFailures) consecutive errors")
                                    .font(.system(size: 11))
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 3) {
                            Text("ERROR DETAILS")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                            Text(incident.reason)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.06))
                                .cornerRadius(6)
                        }
                    }
                    .padding(14)
                    .background(Color.secondary.opacity(0.04))
                    .cornerRadius(8)

                    // 3. Chronological Failure Timeline
                    if let rca = incident.rootCauseAnalysis, !rca.timelineEvents.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.secondary)
                                Text("Incident Event Sequence")
                                    .font(.system(size: 13, weight: .bold))
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(rca.timelineEvents) { event in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .frame(width: 60, alignment: .leading)

                                        Image(systemName: event.eventType.sfSymbol)
                                            .font(.system(size: 11))
                                            .foregroundColor(event.eventType.color)
                                            .frame(width: 14)

                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 5) {
                                                Text(event.serviceName)
                                                    .font(.system(size: 11, weight: .bold))
                                                if event.isRootCauseCandidate {
                                                    Text("FIRST FAILURE")
                                                        .font(.system(size: 8, weight: .heavy))
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(Color.red.opacity(0.18))
                                                        .foregroundColor(.red)
                                                        .cornerRadius(3)
                                                }
                                            }
                                            Text(event.detail)
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            .padding(12)
                            .background(Color.secondary.opacity(0.03))
                            .cornerRadius(6)
                        }
                        .padding(14)
                        .background(Color.secondary.opacity(0.04))
                        .cornerRadius(8)
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 460, minHeight: 480)
        .sheet(item: $activePreview) { preview in
            ActionPreviewSheet(preview: preview) {
                if let mon = targetMonitor {
                    manager.executeServiceAction(
                        action: preview.actionId,
                        target: mon.target,
                        monitorId: mon.id,
                        actor: "User"
                    )
                }
            }
        }
    }
}

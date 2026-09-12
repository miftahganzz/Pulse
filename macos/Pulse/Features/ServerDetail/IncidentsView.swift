import SwiftUI

public struct IncidentsView: View {
    @ObservedObject var manager: ServerConnectionManager
    @State private var filterStatus: IncidentFilter = .all
    @State private var showMutePopover = false
    @State private var showClearConfirm = false
    @State private var selectedIncident: IncidentItem? = nil

    public enum IncidentFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case active = "Active"
        case critical = "Critical"
        case resolved = "Resolved"

        public var id: String { rawValue }
    }

    public init(manager: ServerConnectionManager) {
        self.manager = manager
    }

    private var correlatedIncidents: [IncidentItem] {
        IntelligenceEngine.shared.analyzeRootCauses(
            serverId: manager.serverId,
            incidents: manager.incidents,
            monitors: manager.monitors
        )
    }

    private var filteredIncidents: [IncidentItem] {
        switch filterStatus {
        case .all:
            return correlatedIncidents
        case .active:
            return correlatedIncidents.filter { $0.status != .resolved }
        case .critical:
            return correlatedIncidents.filter { $0.severity == .critical }
        case .resolved:
            return correlatedIncidents.filter { $0.status == .resolved }
        }
    }

    private var activeIncidents: [IncidentItem] {
        correlatedIncidents.filter { $0.status != .resolved }
    }

    private var rootCauseIncident: IncidentItem? {
        activeIncidents.first(where: { inc in
            guard let rca = inc.rootCauseAnalysis else { return false }
            return rca.suspectedRootCauseMonitorId == inc.monitorId && rca.confidenceLevel != .unknown
        })
    }

    private var resolvedIncidents: [IncidentItem] {
        filteredIncidents.filter { $0.status == .resolved }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header & Maintenance Toolbar
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Incidents & Outages")
                            .font(.system(size: 18, weight: .bold))

                        if manager.alertPolicy.isEffectivelyMuted {
                            HStack(spacing: 5) {
                                Image(systemName: "bell.slash.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)

                                if let until = manager.alertPolicy.mutedUntil {
                                    Text("Alerts muted until \(until.formatted(date: .omitted, time: .shortened))")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.orange)
                                } else {
                                    Text("Alerts muted indefinitely")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.orange)
                                }

                                Button("Unmute") {
                                    manager.unmuteServer()
                                }
                                .buttonStyle(.link)
                                .font(.system(size: 11, weight: .semibold))
                            }
                        } else {
                            Text("Realtime downtime correlation & notification suppression")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    // Quick Mute / Maintenance Action
                    Menu {
                        Button("Mute for 15 Minutes") {
                            manager.muteServer(for: 15 * 60)
                        }
                        Button("Mute for 1 Hour (Maintenance)") {
                            manager.muteServer(for: 60 * 60)
                        }
                        Button("Mute for 4 Hours") {
                            manager.muteServer(for: 4 * 3600)
                        }
                        Divider()
                        Button(manager.isDeploymentWindowActive ? "End Deployment Window" : "Start Deployment Window (Pause Remediation)") {
                            manager.isDeploymentWindowActive.toggle()
                        }
                        if manager.alertPolicy.isEffectivelyMuted {
                            Divider()
                            Button("Unmute Notifications") {
                                manager.unmuteServer()
                            }
                        }
                    } label: {
                        Label(
                            manager.isDeploymentWindowActive ? "Deploying" : (manager.alertPolicy.isEffectivelyMuted ? "Muted" : "Maintenance Mode"),
                            systemImage: manager.isDeploymentWindowActive ? "shippingbox.fill" : (manager.alertPolicy.isEffectivelyMuted ? "bell.slash.fill" : "wrench.and.screwdriver")
                        )
                        .font(.system(size: 12))
                    }
                    .menuStyle(.borderedButton)

                    if !manager.incidents.filter({ $0.status == .resolved }).isEmpty {
                        Button {
                            showClearConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                        .help("Clear resolved incidents")
                        .confirmationDialog("Clear Resolved Incidents?", isPresented: $showClearConfirm) {
                            Button("Clear History", role: .destructive) {
                                manager.clearIncidentsHistory()
                            }
                            Button("Cancel", role: .cancel) {}
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                // 1. Active Incidents Section
                if !activeIncidents.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        // Root Cause Correlated Banner (Apple Style)
                        if let root = rootCauseIncident, let rca = root.rootCauseAnalysis, activeIncidents.count > 1 {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "brain.head.profile")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.purple)
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Intelligence Alert: Cascading Outage Detected")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.purple)

                                        Spacer()

                                        Text("\(rca.confidenceLevel.displayName) (\(rca.confidenceScore)%)")
                                            .font(.system(size: 10, weight: .heavy))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(rca.confidenceLevel.color.opacity(0.18))
                                            .foregroundColor(rca.confidenceLevel.color)
                                            .cornerRadius(4)
                                    }

                                    Text("Probable Root Cause: **\(rca.suspectedRootCauseName)** collapsed first, impacting \(rca.blastRadiusCount) downstream dependent services.")
                                        .font(.system(size: 11))
                                        .foregroundColor(.primary)

                                    Button {
                                        selectedIncident = root
                                    } label: {
                                        Label("Inspect Root Cause & Evidence", systemImage: "doc.text.magnifyingglass")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .buttonStyle(.link)
                                    .padding(.top, 2)
                                }
                            }
                            .padding(12)
                            .background(Color.purple.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                            )
                            .cornerRadius(8)
                        }

                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("Active Incidents (\(activeIncidents.count))")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.red)
                        }

                        ForEach(activeIncidents) { incident in
                            ActiveIncidentCard(incident: incident)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedIncident = incident
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                } else {
                    // All systems normal banner
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("All Monitored Services Operational")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                            Text("No active downtime or degraded services detected.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal, 16)
                }

                Divider()
                    .padding(.horizontal, 16)

                // 2. Incident History Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Incident Timeline")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.secondary)

                        Spacer()

                        Picker("", selection: $filterStatus) {
                            ForEach(IncidentFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                        .fixedSize()
                    }

                    if filteredIncidents.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "archivebox")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("No incidents matching filter")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(filteredIncidents) { incident in
                                IncidentHistoryRow(incident: incident)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedIncident = incident
                                    }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .sheet(item: $selectedIncident) { inc in
            IncidentDetailSheet(incident: inc, manager: manager)
        }
    }
}

// MARK: - Active Incident Card
private struct ActiveIncidentCard: View {
    let incident: IncidentItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: incident.severity.sfSymbol)
                .font(.system(size: 16))
                .foregroundColor(incident.severity.color)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(incident.title)
                        .font(.system(size: 14, weight: .bold))

                    Text(incident.severity.displayName.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(incident.severity.color.opacity(0.18))
                        .foregroundColor(incident.severity.color)
                        .cornerRadius(4)

                    Spacer()

                    Text("Downtime: \(incident.formattedDuration)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.red)
                }

                Text(incident.reason)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Text("Target: \(incident.target)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)

                    Text("• Started \(incident.startedAt.formatted(date: .omitted, time: .standard))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    if incident.consecutiveFailures > 1 {
                        Text("• \(incident.consecutiveFailures) consecutive failures")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(Color.red.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.red.opacity(0.25), lineWidth: 1)
        )
        .cornerRadius(8)
    }
}

// MARK: - Incident History Row
private struct IncidentHistoryRow: View {
    let incident: IncidentItem

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: incident.status == .resolved ? "checkmark.circle.fill" : incident.severity.sfSymbol)
                .font(.system(size: 14))
                .foregroundColor(incident.status == .resolved ? .green : incident.severity.color)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(incident.title)
                        .font(.system(size: 12, weight: .semibold))

                    Text(incident.target)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)

                    if incident.status == .resolved {
                        Text("RESOLVED")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .cornerRadius(3)
                    } else {
                        Text(incident.severity.displayName.uppercased())
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(incident.severity.color.opacity(0.15))
                            .foregroundColor(incident.severity.color)
                            .cornerRadius(3)
                    }
                }

                Text(incident.reason)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(incident.formattedDuration)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(incident.status == .resolved ? .primary : .red)

                Text(incident.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(6)
    }
}

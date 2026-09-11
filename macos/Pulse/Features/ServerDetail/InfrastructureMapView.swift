import SwiftUI

public struct InfrastructureMapView: View {
    @ObservedObject var manager: ServerConnectionManager
    @State private var showAddDependencySheet = false

    public init(manager: ServerConnectionManager) {
        self.manager = manager
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Infrastructure & Service Dependencies")
                            .font(.headline)
                        Text("Visualize relationships between services and external network components.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        showAddDependencySheet = true
                    } label: {
                        Label("Add Dependency", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                // Auto-Detected Suggestions Banner (Intelligence)
                if !manager.suggestedDependencies.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.purple)
                            Text("Suggested Dependencies (\(manager.suggestedDependencies.count))")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.purple)
                            Spacer()
                            Text("Auto-detected via open ports & active sockets")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        ForEach(manager.suggestedDependencies) { suggestion in
                            HStack(spacing: 12) {
                                Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                                    .font(.system(size: 13))
                                    .foregroundColor(.purple)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(suggestion.sourceName)
                                            .font(.system(size: 12, weight: .bold))
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(.secondary)
                                        Text(suggestion.targetName)
                                            .font(.system(size: 12, weight: .bold))
                                        Text("(\(suggestion.dependencyType))")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                    Text(suggestion.reason)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Button {
                                    manager.acceptSuggestedDependency(suggestion)
                                } label: {
                                    Label("Accept", systemImage: "checkmark")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.purple)
                                .controlSize(.small)

                                Button {
                                    manager.dismissSuggestedDependency(id: suggestion.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Dismiss suggestion")
                            }
                            .padding(10)
                            .background(Color.purple.opacity(0.06))
                            .cornerRadius(6)
                        }
                    }
                    .padding(14)
                    .background(Color.purple.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                    )
                    .cornerRadius(8)
                }

                Divider()

                if manager.dependencies.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("No Service Dependencies Defined")
                            .font(.system(size: 14, weight: .medium))
                        Text("Link your application services (e.g. movnix-api -> PostgreSQL, Redis) to track outage blast radius.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)

                        Button("Define First Dependency") {
                            showAddDependencySheet = true
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    // Dependency List & Visual Representation
                    VStack(spacing: 14) {
                        ForEach(manager.dependencies) { dep in
                            let source = manager.monitors.first(where: { $0.id == dep.sourceMonitorId })
                            let target = manager.monitors.first(where: { $0.id == dep.targetMonitorId })

                            HStack(spacing: 16) {
                                // Source Node Card
                                nodeCard(name: source?.name ?? dep.sourceMonitorId, type: source?.type ?? .process, status: source?.status ?? .unknown)

                                // Relationship Line & Arrow
                                VStack(spacing: 4) {
                                    HStack(spacing: 4) {
                                        Rectangle()
                                            .fill(Color.secondary.opacity(0.4))
                                            .frame(height: 2)
                                        Image(systemName: dep.type.sfSymbol)
                                            .font(.system(size: 11))
                                            .foregroundColor(.accentColor)
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.secondary)
                                        Rectangle()
                                            .fill(Color.secondary.opacity(0.4))
                                            .frame(height: 2)
                                    }
                                    .frame(width: 100)

                                    Text(dep.type.displayName)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                }

                                // Target Node Card
                                nodeCard(name: target?.name ?? dep.targetMonitorId, type: target?.type ?? .process, status: target?.status ?? .unknown)

                                Spacer()

                                Button(role: .destructive) {
                                    manager.removeDependency(id: dep.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                                .help("Remove Dependency")
                            }
                            .padding(12)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showAddDependencySheet) {
            AddDependencySheet(manager: manager)
        }
    }

    private func nodeCard(name: String, type: MonitorType, status: MonitorStatus) -> some View {
        HStack(spacing: 10) {
            Image(systemName: type.sfSymbol)
                .font(.system(size: 14))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(type.displayName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 180)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Add Dependency Sheet
struct AddDependencySheet: View {
    @ObservedObject var manager: ServerConnectionManager
    @Environment(\.dismiss) private var dismiss

    @State private var sourceId: String = ""
    @State private var targetId: String = ""
    @State private var type: DependencyType = .connectsTo

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Define Service Relationship")
                .font(.headline)

            if manager.monitors.count < 2 {
                Text("You need at least 2 active monitors to create a dependency.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Source Service")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Picker("", selection: $sourceId) {
                        Text("Select Service...").tag("")
                        ForEach(manager.monitors) { m in
                            Text(m.name).tag(m.id)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Relationship Type")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Picker("", selection: $type) {
                        ForEach(DependencyType.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Target Dependency")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Picker("", selection: $targetId) {
                        Text("Select Target...").tag("")
                        ForEach(manager.monitors.filter { $0.id != sourceId }) { m in
                            Text(m.name).tag(m.id)
                        }
                    }
                }
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Save Relationship") {
                    if !sourceId.isEmpty && !targetId.isEmpty && sourceId != targetId {
                        manager.addDependency(sourceMonitorId: sourceId, targetMonitorId: targetId, type: type)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(sourceId.isEmpty || targetId.isEmpty || sourceId == targetId)
            }
        }
        .padding(20)
        .frame(width: 400, height: 300)
        .onAppear {
            if let first = manager.monitors.first {
                sourceId = first.id
            }
            if manager.monitors.count > 1 {
                targetId = manager.monitors[1].id
            }
        }
    }
}

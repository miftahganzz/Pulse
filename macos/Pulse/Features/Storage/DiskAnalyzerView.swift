import SwiftUI

public struct DiskAnalyzerView: View {
    @ObservedObject var manager: ServerConnectionManager

    @State private var analysis: StorageAnalysis? = nil
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    @State private var confirmingAction: String? = nil
    @State private var actionTarget: String? = nil
    @State private var isExecuting: Bool = false
    @State private var actionResult: String? = nil

    public init(manager: ServerConnectionManager) {
        self.manager = manager
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header & Refresh
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Disk Space & Storage Analyzer")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Detailed breakdown of disk consumption and safe reclamation actions.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        loadAnalysis()
                    } label: {
                        HStack(spacing: 5) {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.6)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11))
                            }
                            Text("Scan Disk")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading)
                }

                if let err = errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                }

                if let res = actionResult {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(res)
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                        Spacer()
                        Button {
                            actionResult = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)
                }

                // Reclaimable Storage Card
                if let analysis = analysis {
                    reclaimableCard(analysis.reclaimable)
                    directoryBreakdown(analysis.directories)
                } else if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Analyzing filesystem usage on \(manager.serverName)...")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("Click 'Scan Disk' to inspect disk consumption breakdown")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                }
            }
            .padding(20)
        }
        .onAppear {
            if analysis == nil {
                loadAnalysis()
            }
        }
        .confirmationDialog(
            "Confirm Storage Cleanup",
            isPresented: Binding(get: { confirmingAction != nil }, set: { if !$0 { confirmingAction = nil } }),
            titleVisibility: .visible
        ) {
            Button("Confirm Cleanup", role: .destructive) {
                if let act = confirmingAction {
                    executeCleanup(action: act)
                }
            }
            Button("Cancel", role: .cancel) {
                confirmingAction = nil
            }
        } message: {
            Text("This will safely prune cache and logs. Persistent application databases are untouched.")
        }
    }

    // MARK: - Reclaimable Summary Card

    private func reclaimableCard(_ rec: ReclaimableSummaryItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Reclaimable Storage", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Potential: \(rec.totalHuman)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor)
            }

            Divider()

            HStack(spacing: 12) {
                cleanerButton(
                    title: "Vacuum Journals",
                    size: rec.journalLogsHuman,
                    icon: "clock.arrow.circlepath",
                    action: "storage.vacuum_journals"
                )

                cleanerButton(
                    title: "Prune Docker",
                    size: rec.dockerCacheHuman,
                    icon: "shippingbox",
                    action: "storage.docker_prune"
                )

                cleanerButton(
                    title: "Clean APT Cache",
                    size: rec.aptCacheHuman,
                    icon: "archivebox",
                    action: "storage.clean_apt"
                )
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func cleanerButton(title: String, size: String, icon: String, action: String) -> some View {
        Button {
            confirmingAction = action
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                    Spacer()
                    Text(size)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                Text("Tap to clean")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Directory Breakdown

    private func directoryBreakdown(_ dirs: [DirectoryUsageItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Directory Usage Breakdown")
                .font(.system(size: 13, weight: .semibold))

            let maxBytes = dirs.map(\.sizeBytes).max() ?? 1

            VStack(spacing: 8) {
                ForEach(dirs) { dir in
                    HStack(spacing: 12) {
                        Image(systemName: iconForCategory(dir.category))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(dir.path)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                Spacer()
                                Text(dir.sizeHuman)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            }

                            // Progress bar
                            GeometryReader { geo in
                                let fraction = min(max(Double(dir.sizeBytes) / Double(maxBytes), 0.05), 1.0)
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.secondary.opacity(0.12))
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(colorForCategory(dir.category))
                                        .frame(width: geo.size.width * fraction)
                                }
                            }
                            .frame(height: 5)
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        }
    }

    private func iconForCategory(_ cat: String) -> String {
        switch cat {
        case "logs": return "doc.text"
        case "docker": return "shippingbox"
        case "cache": return "archivebox"
        case "temp": return "trash"
        default: return "folder"
        }
    }

    private func colorForCategory(_ cat: String) -> Color {
        switch cat {
        case "logs": return .orange
        case "docker": return .blue
        case "cache": return .purple
        case "temp": return .red
        default: return .secondary
        }
    }

    // MARK: - Actions

    private func loadAnalysis() {
        isLoading = true
        errorMessage = nil
        manager.fetchStorageAnalysis { result in
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let data):
                    self.analysis = data
                case .failure(let err):
                    let currentVer = self.manager.identity?.agentVersion ?? "0.9.0"
                    let isOld = currentVer.hasPrefix("0.")
                    if isOld || err.localizedDescription.contains("404") {
                        self.errorMessage = "Disk Analyzer requires pulse-agent v1.0.0+ (Server is running v\(currentVer)). Please update pulse-agent."
                    } else {
                        self.errorMessage = "Failed to scan disk: \(err.localizedDescription)"
                    }
                }
            }
        }
    }

    private func executeCleanup(action: String) {
        isExecuting = true
        manager.executeAction(action: action, target: "system", actor: "Manual")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.isExecuting = false
            self.actionResult = "Action '\(action)' dispatched. Refreshing scan..."
            self.loadAnalysis()
        }
    }
}

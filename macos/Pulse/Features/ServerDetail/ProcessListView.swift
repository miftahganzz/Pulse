import SwiftUI

public struct ProcessListView: View {
    @ObservedObject var manager: ServerConnectionManager
    @State private var searchText = ""
    @State private var sortBy = "cpu"
    @State private var selectedProcessForKill: ProcessItem?
    @State private var killSignal: String = "SIGTERM"
    @State private var showKillConfirmation = false
    @State private var actionErrorMessage: String?
    @State private var showActionError = false

    public init(manager: ServerConnectionManager) {
        self.manager = manager
    }

    private var filteredProcesses: [ProcessItem] {
        if searchText.isEmpty {
            return manager.processes
        }
        return manager.processes.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.user.localizedCaseInsensitiveContains(searchText) ||
            $0.command.localizedCaseInsensitiveContains(searchText) ||
            String($0.pid).contains(searchText)
        }
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Filter and Sort Toolbar
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField("Search processes or PID...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

                HStack(spacing: 6) {
                    Text("Sort:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .fixedSize()

                    Picker("", selection: $sortBy) {
                        Text("CPU %").tag("cpu")
                        Text("Memory").tag("memory")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                    .onChange(of: sortBy) { newSort in
                        manager.refreshProcesses(sortBy: newSort)
                    }
                }

                Button(action: { manager.refreshProcesses(sortBy: sortBy) }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(manager.isLoadingProcesses)
            }

            if manager.isLoadingProcesses && manager.processes.isEmpty {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading processes...").foregroundColor(.secondary).font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: 200)
            } else if filteredProcesses.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "slash.circle")
                        .foregroundColor(.secondary)
                    Text("No processes match the filter.")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: 200)
            } else {
                Table(filteredProcesses) {
                    TableColumn("PID") { proc in
                        Text(verbatim: "\(proc.pid)")
                            .font(.system(size: 11, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    .width(min: 50, ideal: 60, max: 80)

                    TableColumn("Name") { proc in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(proc.name)
                                .font(.system(size: 12, weight: .medium))
                            if !proc.command.isEmpty && proc.command != proc.name {
                                Text(proc.command)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .width(min: 150, ideal: 220)

                    TableColumn("User") { proc in
                        Text(proc.user)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .width(min: 70, ideal: 80, max: 100)

                    TableColumn("CPU %") { proc in
                        Text(String(format: "%.1f%%", proc.cpuPercent))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(proc.cpuPercent > 50 ? .red : (proc.cpuPercent > 20 ? .orange : .primary))
                    }
                    .width(min: 65, ideal: 75, max: 90)

                    TableColumn("Memory") { proc in
                        Text(FormatUtils.bytes(proc.memoryRSSBytes))
                            .font(.system(size: 11, design: .monospaced))
                            .monospacedDigit()
                    }
                    .width(min: 75, ideal: 90, max: 110)

                    TableColumn("Disk / Net I/O") { proc in
                        Text(proc.formattedIO)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .width(min: 110, ideal: 140, max: 170)

                    TableColumn("State") { proc in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(stateColor(proc.state))
                                .frame(width: 5, height: 5)
                            Text(proc.state)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(stateColor(proc.state))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(stateColor(proc.state).opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .width(min: 75, ideal: 85, max: 95)

                    TableColumn("Actions") { proc in
                        Menu {
                            Button("Terminate (SIGTERM)") {
                                selectedProcessForKill = proc
                                killSignal = "SIGTERM"
                                showKillConfirmation = true
                            }
                            Button("Force Kill (SIGKILL)", role: .destructive) {
                                selectedProcessForKill = proc
                                killSignal = "SIGKILL"
                                showKillConfirmation = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 13))
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 30)
                    }
                    .width(min: 40, ideal: 50, max: 60)
                }
                .tableStyle(.bordered)
            }
        }
        .onAppear {
            manager.refreshProcesses(sortBy: sortBy)
        }
        .confirmationDialog(
            "Process Action",
            isPresented: $showKillConfirmation,
            titleVisibility: .visible
        ) {
            if let proc = selectedProcessForKill {
                Button("\(killSignal == "SIGKILL" ? "Force Kill" : "Terminate") PID \(proc.pid) (\(proc.name))", role: killSignal == "SIGKILL" ? .destructive : .none) {
                    manager.killProcess(pid: proc.pid, signal: killSignal) { result in
                        Task { @MainActor in
                            if case .failure(let error) = result {
                                actionErrorMessage = error.localizedDescription
                                showActionError = true
                            }
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            if let proc = selectedProcessForKill {
                Text(verbatim: "Are you sure you want to send \(killSignal) to process \(proc.name) (PID \(proc.pid))?")
            }
        }
        .alert("Process Action Failed", isPresented: $showActionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "An unknown error occurred.")
        }
    }

    private func stateColor(_ state: String) -> Color {
        switch state.lowercased() {
        case "running":
            return .green
        case "sleeping", "idle":
            return .blue
        case "stopped", "zombie", "dead":
            return .red
        default:
            return .secondary
        }
    }
}

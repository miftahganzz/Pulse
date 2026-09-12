import SwiftUI

public struct DockerContainersView: View {
    @ObservedObject var manager: ServerConnectionManager
    @State private var searchText = ""
    @State private var activeActionContainerId: String?
    @State private var actionErrorMessage: String?
    @State private var showActionError = false
    
    // Log Viewer Sheet State
    @State private var selectedContainerForLogs: DockerContainerItem?
    @State private var containerLogs = ""
    @State private var isLoadingLogs = false
    @State private var showLogsSheet = false

    public init(manager: ServerConnectionManager) {
        self.manager = manager
    }

    private var filteredContainers: [DockerContainerItem] {
        if searchText.isEmpty {
            return manager.dockerContainers
        }
        return manager.dockerContainers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.image.localizedCaseInsensitiveContains(searchText) ||
            $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Header Bar
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField("Search containers by name, image, or ID...", text: $searchText)
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

                if let ver = manager.dockerVersion, !ver.isEmpty {
                    Text("v\(ver)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(Capsule())
                }


                Button(action: { manager.refreshDocker() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(manager.isLoadingDocker)
            }

            if manager.isLoadingDocker && manager.dockerContainers.isEmpty {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking Docker engine...").foregroundColor(.secondary).font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !manager.isDockerAvailable {
                VStack(spacing: 12) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("Docker Not Detected")
                        .font(.system(size: 15, weight: .semibold))
                    Text("No active Docker socket found at /var/run/docker.sock on this server.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            } else if filteredContainers.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "shippingbox.and.arrow.backward")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(searchText.isEmpty ? "No containers found." : "No containers match \"\(searchText)\"")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13, weight: .medium))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredContainers) {
                    TableColumn("ID") { c in
                        Text(c.id)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .width(min: 80, ideal: 95, max: 110)

                    TableColumn("Name") { c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name)
                                .font(.system(size: 12, weight: .medium))
                            Text(c.image)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .width(min: 160, ideal: 220)

                    TableColumn("State") { c in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(stateColor(c.state))
                                .frame(width: 5, height: 5)
                            Text(c.state)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(stateColor(c.state))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(stateColor(c.state).opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .width(min: 80, ideal: 90, max: 105)


                    TableColumn("Status") { c in
                        Text(c.status)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 100, ideal: 140)

                    TableColumn("Ports") { c in
                        Text(c.ports.joined(separator: ", "))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 100, ideal: 160)

                    TableColumn("Actions") { c in
                        HStack(spacing: 6) {
                            if activeActionContainerId == c.id {
                                ProgressView()
                                    .controlSize(.mini)
                                    .frame(width: 24, height: 24)
                            } else {
                                Button {
                                    openLogs(for: c)
                                } label: {
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.plain)
                                .help("View Logs")

                                Menu {
                                    if !c.isRunning {
                                        Button("Start") {
                                            executeContainerAction(id: c.id, action: "start")
                                        }
                                    }
                                    if c.isRunning {
                                        Button("Restart") {
                                            executeContainerAction(id: c.id, action: "restart")
                                        }
                                        Button("Stop", role: .destructive) {
                                            executeContainerAction(id: c.id, action: "stop")
                                        }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)
                                .frame(width: 24, height: 24)
                            }
                        }
                    }
                    .width(min: 60, ideal: 70, max: 80)
                }
                .tableStyle(.bordered)
            }
        }
        .onAppear {
            manager.refreshDocker()
        }
        .alert("Docker Action Failed", isPresented: $showActionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "An unknown error occurred.")
        }
        .sheet(isPresented: $showLogsSheet) {
            if let c = selectedContainerForLogs {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Logs: \(c.name)")
                                .font(.system(size: 14, weight: .semibold))
                            Text("\(c.image) (\(c.id))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(action: { fetchLogs(for: c) }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLoadingLogs)

                        Button("Done") {
                            showLogsSheet = false
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                    .padding(.horizontal)
                    .padding(.top)

                    Divider()

                    if isLoadingLogs {
                        VStack {
                            ProgressView()
                            Text("Fetching container logs...").font(.caption).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            Text(containerLogs.isEmpty ? "No logs available." : containerLogs)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .textSelection(.enabled)
                        }
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                }
                .frame(minWidth: 550, minHeight: 380)
            }
        }
    }

    private func executeContainerAction(id: String, action: String) {
        activeActionContainerId = id
        manager.controlDockerContainer(id: id, action: action) { result in
            Task { @MainActor in
                activeActionContainerId = nil
                if case .failure(let error) = result {
                    actionErrorMessage = error.localizedDescription
                    showActionError = true
                }
            }
        }
    }

    private func openLogs(for container: DockerContainerItem) {
        selectedContainerForLogs = container
        showLogsSheet = true
        fetchLogs(for: container)
    }

    private func fetchLogs(for container: DockerContainerItem) {
        isLoadingLogs = true
        manager.fetchDockerLogs(id: container.id, tail: 150) { result in
            Task { @MainActor in
                isLoadingLogs = false
                switch result {
                case .success(let logs):
                    containerLogs = logs
                case .failure(let error):
                    containerLogs = "Error loading logs: \(error.localizedDescription)"
                }
            }
        }
    }

    private func stateColor(_ state: String) -> Color {
        switch state.lowercased() {
        case "running":
            return .green
        case "restarting":
            return .yellow
        case "paused":
            return .orange
        case "exited", "dead":
            return .secondary
        default:
            return .secondary
        }
    }
}

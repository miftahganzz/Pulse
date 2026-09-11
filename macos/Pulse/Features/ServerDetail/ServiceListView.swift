import SwiftUI

public struct ServiceListView: View {
    @ObservedObject var manager: ServerConnectionManager
    @State private var searchText = ""
    @State private var activeServiceAction: [String: String] = [:] // serviceName: action
    @State private var actionErrorMessage: String?
    @State private var showActionError = false

    public init(manager: ServerConnectionManager) {
        self.manager = manager
    }

    private var filteredServices: [SystemServiceItem] {
        if searchText.isEmpty {
            return manager.services
        }
        return manager.services.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Search and Refresh Header
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField("Search systemd services...", text: $searchText)
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

                Button(action: { manager.refreshServices() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(manager.isLoadingServices)
            }

            if manager.isLoadingServices && manager.services.isEmpty {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Querying services...").foregroundColor(.secondary).font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: 200)
            } else if filteredServices.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "slash.circle")
                        .foregroundColor(.secondary)
                    Text("No services match the filter.")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: 200)
            } else {
                List(filteredServices) { svc in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(statusColor(svc))
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(svc.name)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                            if !svc.description.isEmpty && svc.description != svc.name {
                                Text(svc.description)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(statusColor(svc))
                                    .frame(width: 5, height: 5)
                                Text("\(svc.activeState) (\(svc.subState))")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(statusColor(svc))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(statusColor(svc).opacity(0.12))
                            .clipShape(Capsule())

                            if activeServiceAction[svc.name] != nil {
                                ProgressView()
                                    .controlSize(.mini)
                                    .frame(width: 24, height: 24)
                            } else {
                                Menu {
                                    if !svc.isRunning {
                                        Button("Start") {
                                            executeAction(on: svc.name, action: "start")
                                        }
                                    }
                                    if svc.isRunning {
                                        Button("Restart") {
                                            executeAction(on: svc.name, action: "restart")
                                        }
                                        Button("Stop", role: .destructive) {
                                            executeAction(on: svc.name, action: "stop")
                                        }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.system(size: 13))
                                }
                                .menuStyle(.borderlessButton)
                                .frame(width: 24, height: 24)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .onAppear {
            manager.refreshServices()
        }
        .alert("Service Action Failed", isPresented: $showActionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "An unknown error occurred.")
        }
    }

    private func executeAction(on serviceName: String, action: String) {
        activeServiceAction[serviceName] = action
        manager.controlService(name: serviceName, action: action) { result in
            Task { @MainActor in
                activeServiceAction.removeValue(forKey: serviceName)
                if case .failure(let error) = result {
                    actionErrorMessage = error.localizedDescription
                    showActionError = true
                }
            }
        }
    }

    private func statusColor(_ svc: SystemServiceItem) -> Color {
        if svc.isFailed {
            return .red
        }
        if svc.isRunning {
            return .green
        }
        return .secondary
    }
}


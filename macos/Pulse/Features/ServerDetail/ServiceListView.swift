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
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search systemd services...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))

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
                    Image(systemName: "gearshape.2")
                        .foregroundColor(.secondary)
                    Text("No services found.")
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
                            Text("\(svc.activeState) (\(svc.subState))")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(statusColor(svc))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(statusColor(svc).opacity(0.1))
                                .cornerRadius(4)

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


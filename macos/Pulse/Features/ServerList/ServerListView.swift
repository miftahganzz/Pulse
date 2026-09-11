import SwiftUI

@MainActor
public struct ServerListView: View {
    @ObservedObject private var store = ServerStore.shared
    @ObservedObject private var pool = ServerConnectionPool.shared
    @ObservedObject private var navState = NavigationState.shared
    @ObservedObject private var settings = AppSettingsStore.shared

    @State private var showAddServerSheet = false
    @State private var serverToEdit: ServerModel?
    @State private var isShowingLaunchMotion = true

    public init() {}

    private var selectedServer: ServerModel? {
        store.servers.first { $0.id.uuidString == navState.selectedServerId }
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $navState.selectedServerId) {
                // Section 1: Overview
                Section {
                    NavigationLink(value: "ALL_SERVERS") {
                        HStack(spacing: 8) {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 13))
                                .foregroundColor(.accentColor)
                            Text("All Servers")
                                .font(.system(size: 13, weight: .medium))

                            Spacer()

                            if pool.activeIncidentsCount > 0 {
                                Text("\(pool.activeIncidentsCount)")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.red.opacity(0.2))
                                    .foregroundColor(.red)
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .tag("ALL_SERVERS")

                    NavigationLink(value: "COMPARE_SERVERS") {
                        HStack(spacing: 8) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: 13))
                                .foregroundColor(.accentColor)
                            Text("Compare Servers")
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                    .tag("COMPARE_SERVERS")
                }

                // Section 2: Individual Servers
                Section("Servers") {
                    ForEach(store.servers) { server in
                        let mgr = pool.manager(for: server)
                        NavigationLink(value: server.id.uuidString) {
                            ServerRowView(server: server, manager: mgr)
                        }
                        .tag(server.id.uuidString)
                        .contextMenu {
                            Button("Open") {
                                navState.selectedServerId = server.id.uuidString
                            }
                            Button("Reconnect") {
                                mgr.connect()
                            }
                            Divider()
                            if mgr.alertPolicy.isEffectivelyMuted {
                                Button("Unmute Notifications") {
                                    mgr.unmuteServer()
                                }
                            } else {
                                Button("Mute for 1 Hour") {
                                    mgr.muteServer(for: 3600)
                                }
                            }
                            Divider()
                            Button("Delete Server", role: .destructive) {
                                deleteServer(server)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 320)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: { navState.showCommandPalette = true }) {
                        Label("Quick Search", systemImage: "magnifyingglass")
                    }
                    .help("Quick Search (⌘K)")
                    .keyboardShortcut("k", modifiers: .command)

                    Button(action: { showAddServerSheet = true }) {
                        Label("Add Server", systemImage: "plus")
                    }
                    .help("Add Server")

                    Button(action: { navState.showSettings = true }) {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Settings (⌘,)")
                    .keyboardShortcut(",", modifiers: .command)
                }
            }
        } detail: {
            if store.servers.isEmpty {
                OnboardingView {
                    showAddServerSheet = true
                }
            } else if navState.selectedServerId == "ALL_SERVERS" {
                AllServersOverviewView(selectedServer: Binding(
                    get: { selectedServer },
                    set: { navState.selectedServerId = $0?.id.uuidString ?? "ALL_SERVERS" }
                ))
            } else if navState.selectedServerId == "COMPARE_SERVERS" {
                ServerCompareView()
            } else if let server = selectedServer {
                ServerDetailView(manager: pool.manager(for: server))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Select a Server")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: Binding(
            get: { showAddServerSheet || navState.showAddServerSheet },
            set: { newValue in
                showAddServerSheet = newValue
                navState.showAddServerSheet = newValue
                if !newValue {
                    navState.pendingServerDraft = nil
                }
            }
        )) {
            AddServerSheet(draft: navState.pendingServerDraft)
        }
        .sheet(isPresented: $navState.showSettings) {
            AppSettingsView()
        }
        .sheet(isPresented: $navState.showCommandPalette) {
            QuickCommandPalette(
                onSelectServer: { server in
                    navState.selectedServerId = server.id.uuidString
                },
                onSelectAllServers: {
                    navState.selectedServerId = "ALL_SERVERS"
                },
                onOpenSettings: {
                    navState.showSettings = true
                }
            )
        }
        .onAppear {
            if store.servers.isEmpty {
                navState.selectedServerId = "ALL_SERVERS"
            }
        }
        .overlay {
            if isShowingLaunchMotion && settings.showLaunchMotion {
                AppLaunchMotionView(
                    isPresented: $isShowingLaunchMotion,
                    onAddServerRequested: {
                        showAddServerSheet = true
                    }
                )
                .transition(.opacity)
                .zIndex(999)
            }
        }
    }

    private func deleteServer(_ server: ServerModel) {
        if navState.selectedServerId == server.id.uuidString {
            navState.selectedServerId = "ALL_SERVERS"
        }
        pool.remove(serverId: server.id)
        store.deleteServer(server)
    }
}

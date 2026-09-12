import SwiftUI

@main
struct PulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var settings = AppSettingsStore.shared
    @ObservedObject private var pool = ServerConnectionPool.shared

    init() {
        NotificationService.shared.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            ServerListView()
                .frame(minWidth: 780, idealWidth: 960, maxWidth: 1280,
                       minHeight: 500, idealHeight: 640, maxHeight: 860)
                .preferredColorScheme(colorScheme)
                .onOpenURL { url in
                    NavigationState.shared.handleDeepLink(url: url)
                }
        }
        .commands {
            SidebarCommands()

            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    UpdateManager.shared.checkForUpdates()
                }
            }

            CommandGroup(after: .newItem) {
                Button("Add Server...") {
                    NavigationState.shared.showAddServerSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NavigationState.shared.showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu("Navigation") {
                Button("All Servers") {
                    NavigationState.shared.navigateToAllServers()
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Overview") {
                    NavigationState.shared.selectedDetailTab = 0
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Services & Monitors") {
                    NavigationState.shared.selectedDetailTab = 1
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Incidents") {
                    NavigationState.shared.selectedDetailTab = 2
                }
                .keyboardShortcut("4", modifiers: .command)

                Button("Compare Servers") {
                    NavigationState.shared.selectedServerId = "COMPARE_SERVERS"
                }
                .keyboardShortcut("5", modifiers: .command)

                Button("Infrastructure Map") {
                    NavigationState.shared.selectedDetailTab = 7
                }
                .keyboardShortcut("6", modifiers: .command)

                Divider()

                Button("Quick Search...") {
                    NavigationState.shared.showCommandPalette = true
                }
                .keyboardShortcut("k", modifiers: .command)
            }

            CommandMenu("View") {
                Button("Reconnect All Servers") {
                    pool.reconnectAll()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .help) {
                Button("Pulse Docs") {
                    NavigationState.shared.showDocs = true
                }
                .keyboardShortcut("/", modifiers: .command)
            }
        }

        // Docs window — fixed content size, no fullscreen
        Window("Pulse Docs", id: "pulse-docs") {
            DocsView()
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarExtraView()
        } label: {
            let count = pool.activeIncidentsCount
            if count > 0 {
                Label("Pulse (\(count))", systemImage: "exclamationmark.octagon.fill")
            } else {
                Label("Pulse", systemImage: "waveform.path.ecg")
            }
        }
        .menuBarExtraStyle(.menu)
    }

    private var colorScheme: ColorScheme? {
        switch settings.theme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private func openSettingsWindow() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Pool connects automatically on startup
        ServerConnectionPool.shared.syncWithStore()

        // Disable fullscreen on all windows — Pulse has fixed max sizes
        DispatchQueue.main.async {
            NSApp.windows.forEach { window in
                // NSWindowCollectionBehaviorFullScreenNone (1 << 9)
                let fullScreenNone = NSWindow.CollectionBehavior(rawValue: 1 << 9)
                window.collectionBehavior.insert(fullScreenNone)
            }
        }

        // Handle sleep / wake notifications to prevent fake incidents
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWorkspaceWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWorkspaceDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleWorkspaceWillSleep() {
        PulseLog.agent.info("Mac is going to sleep: pausing connection monitoring")
    }

    @objc private func handleWorkspaceDidWake() {
        PulseLog.agent.info("Mac woke up from sleep: reconnecting all servers")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            ServerConnectionPool.shared.reconnectAll()
        }
    }

    // Keep app alive in background if keepRunningInBackground is true
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return !AppSettingsStore.shared.keepRunningInBackground
    }
}

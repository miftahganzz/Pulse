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
                .frame(minWidth: 860, idealWidth: 960, maxWidth: 1040,
                       minHeight: 560, idealHeight: 640, maxHeight: 720)
                .preferredColorScheme(colorScheme)
                .onOpenURL { url in
                    NavigationState.shared.handleDeepLink(url: url)
                }
        }
        .windowResizability(.contentSize)
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Pool connects automatically on startup
        ServerConnectionPool.shared.syncWithStore()

        // Disable fullscreen and zoom on all windows — Pulse has fixed compact bounds
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidBecomeKey(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        DispatchQueue.main.async {
            self.disableFullScreenMenuItems()
            NSApp.windows.forEach { self.configureFixedWindow($0) }
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

    @objc private func handleAppDidBecomeActive() {
        disableFullScreenMenuItems()
        NSApp.windows.forEach { configureFixedWindow($0) }
    }

    @objc private func handleWindowDidBecomeKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            configureFixedWindow(window)
        }
    }

    private func disableFullScreenMenuItems() {
        guard let mainMenu = NSApp.mainMenu else { return }
        for item in mainMenu.items {
            if let submenu = item.submenu {
                for subItem in submenu.items {
                    if subItem.action == #selector(NSWindow.toggleFullScreen(_:)) {
                        subItem.target = nil
                        subItem.isEnabled = false
                        subItem.isHidden = true
                    }
                }
            }
        }
    }

    private func configureFixedWindow(_ window: NSWindow) {
        guard !(window is NSPanel) else { return }

        // Exit fullscreen immediately if window was restored in fullscreen mode
        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }

        // Hard lock window size in AppKit
        window.maxSize = NSSize(width: 1040, height: 720)
        window.minSize = NSSize(width: 860, height: 560)

        // Clamp current frame if it exceeds limits
        var currentFrame = window.frame
        var frameChanged = false
        if currentFrame.width > 1040 {
            currentFrame.size.width = 1040
            frameChanged = true
        }
        if currentFrame.height > 720 {
            currentFrame.size.height = 720
            frameChanged = true
        }
        if currentFrame.width < 860 {
            currentFrame.size.width = 860
            frameChanged = true
        }
        if currentFrame.height < 560 {
            currentFrame.size.height = 560
            frameChanged = true
        }
        if frameChanged {
            window.setFrame(currentFrame, display: true, animate: false)
        }

        // Remove fullscreen collection capability
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        let fullScreenNone = NSWindow.CollectionBehavior(rawValue: 1 << 9)
        window.collectionBehavior.insert(fullScreenNone)
        window.styleMask.remove(.fullScreen)

        // Disable and hide green zoom / fullscreen button
        if let zoomBtn = window.standardWindowButton(.zoomButton) {
            zoomBtn.isEnabled = false
            zoomBtn.isHidden = true
        }

        window.delegate = self
    }

    // Clamp resize interactions to the fixed bounds
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let clampedW = min(max(frameSize.width, 860), 1040)
        let clampedH = min(max(frameSize.height, 560), 720)
        return NSSize(width: clampedW, height: clampedH)
    }

    // Ensure zoom button remains hidden after resize
    func windowDidResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            if let zoomBtn = window.standardWindowButton(.zoomButton) {
                zoomBtn.isEnabled = false
                zoomBtn.isHidden = true
            }
        }
    }

    // Prevent double-clicking titlebar from maximizing
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        return false
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            window.toggleFullScreen(nil)
        }
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

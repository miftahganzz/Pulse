import SwiftUI

public struct AppSettingsView: View {
    @ObservedObject private var settings = AppSettingsStore.shared
    @ObservedObject private var updateManager = UpdateManager.shared
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header with title and explicit Close button
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.accentColor)
                    Text("Settings")
                        .font(.system(size: 15, weight: .bold))
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Settings Tabs
            TabView {
                generalTab
                    .tabItem {
                        Label("General", systemImage: "gearshape")
                    }

                notificationsTab
                    .tabItem {
                        Label("Notifications", systemImage: "bell")
                    }

                appearanceTab
                    .tabItem {
                        Label("Appearance", systemImage: "paintbrush")
                    }

                advancedTab
                    .tabItem {
                        Label("Advanced", systemImage: "slider.horizontal.3")
                    }
            }
            .padding(16)
        }
        .frame(width: 520, height: 380)
    }

    private var generalTab: some View {
        Form {
            Section("Startup & Background") {
                Toggle("Launch Pulse at login", isOn: $settings.launchAtLogin)
                Toggle("Show icon in Menu Bar", isOn: $settings.showInMenuBar)
                Toggle("Show CPU & RAM metrics in Menu Bar", isOn: $settings.showMetricsInMenuBar)
                Toggle("Keep Pulse monitoring in background when window is closed (⌘W)", isOn: $settings.keepRunningInBackground)
                Toggle("Show startup motion animation", isOn: $settings.showLaunchMotion)

                Divider()

                Button("Replay Welcome & Feature Tour") {
                    settings.resetWelcomeGuide()
                }
            }

            Section("Software Updates") {
                Toggle("Automatically check for updates", isOn: $updateManager.automaticallyChecksForUpdates)

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Pulse v1.0.2 (Build 12)")
                            .font(.system(size: 12, weight: .medium))
                        if let lastCheck = updateManager.lastUpdateCheckDate {
                            Text("Last checked: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        } else {
                            Text("Checks automatically in background")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button("Check Now") {
                        updateManager.checkForUpdates()
                    }
                    .disabled(!updateManager.canCheckForUpdates)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var notificationsTab: some View {
        Form {
            Section {
                Toggle(isOn: $settings.notifyCritical) {
                    HStack(spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.red)
                        Text("Notify on Critical incidents")
                    }
                }

                Toggle(isOn: $settings.notifyWarning) {
                    HStack(spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.orange)
                        Text("Notify on Warning or Degraded states")
                    }
                }

                Toggle(isOn: $settings.notifyRecovery) {
                    HStack(spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.green)
                        Text("Notify when a service or server recovers")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var appearanceTab: some View {
        Form {
            Section {
                Picker("App Appearance:", selection: $settings.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .pickerStyle(.radioGroup)

                Text("Select between macOS System default, Light, or Dark mode.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var advancedTab: some View {
        Form {
            Section {
                Picker("Metrics polling interval:", selection: $settings.metricIntervalSeconds) {
                    Text("5 seconds (Fast)").tag(5)
                    Text("10 seconds (Default)").tag(10)
                    Text("30 seconds (Eco)").tag(30)
                }

                Picker("Health check probe interval:", selection: $settings.healthCheckIntervalSeconds) {
                    Text("15 seconds").tag(15)
                    Text("30 seconds (Default)").tag(30)
                    Text("60 seconds").tag(60)
                }
            } footer: {
                Text("Pulse stores all connection keys and database credentials safely inside the Apple Keychain.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
    }
}

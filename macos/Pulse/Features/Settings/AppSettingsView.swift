import SwiftUI

public struct AppSettingsView: View {
    @ObservedObject private var settings = AppSettingsStore.shared
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
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
        .padding(20)
        .frame(width: 480, height: 320)
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch Pulse at login", isOn: $settings.launchAtLogin)
                Toggle("Show icon in Menu Bar", isOn: $settings.showInMenuBar)
                Toggle("Keep Pulse monitoring in background when window is closed (⌘W)", isOn: $settings.keepRunningInBackground)
            }
        }
        .padding(10)
    }

    private var notificationsTab: some View {
        Form {
            Section {
                Toggle("Notify on Critical incidents (🔴)", isOn: $settings.notifyCritical)
                Toggle("Notify on Warning / Degraded states (🟠)", isOn: $settings.notifyWarning)
                Toggle("Notify when service or server recovers (🟢)", isOn: $settings.notifyRecovery)
            }
        }
        .padding(10)
    }

    private var appearanceTab: some View {
        Form {
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
        .padding(10)
    }

    private var advancedTab: some View {
        Form {
            HStack {
                Text("Metrics polling interval:")
                Spacer()
                Picker("", selection: $settings.metricIntervalSeconds) {
                    Text("5 seconds (Fast)").tag(5)
                    Text("10 seconds (Default)").tag(10)
                    Text("30 seconds (Eco)").tag(30)
                }
                .frame(width: 170)
            }

            HStack {
                Text("Health check probe interval:")
                Spacer()
                Picker("", selection: $settings.healthCheckIntervalSeconds) {
                    Text("15 seconds").tag(15)
                    Text("30 seconds (Default)").tag(30)
                    Text("60 seconds").tag(60)
                }
                .frame(width: 170)
            }

            Divider()

            Text("Pulse stores all connection keys and database credentials safely inside the Apple Keychain.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(10)
    }
}

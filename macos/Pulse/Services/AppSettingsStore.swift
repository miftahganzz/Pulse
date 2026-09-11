import Foundation
import ServiceManagement

public enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    public var id: String { rawValue }
}

public final class AppSettingsStore: ObservableObject {
    public static let shared = AppSettingsStore()

    private let launchAtLoginKey = "pulse.settings.launch_at_login"
    private let showInMenuBarKey = "pulse.settings.show_in_menu_bar"
    private let keepRunningInBackgroundKey = "pulse.settings.keep_running_in_background"
    private let themeKey = "pulse.settings.theme"
    private let metricIntervalKey = "pulse.settings.metric_interval"
    private let healthCheckIntervalKey = "pulse.settings.health_check_interval"
    private let notifyCriticalKey = "pulse.settings.notify_critical"
    private let notifyWarningKey = "pulse.settings.notify_warning"
    private let notifyRecoveryKey = "pulse.settings.notify_recovery"
    private let showLaunchMotionKey = "pulse.settings.show_launch_motion"
    private let hasCompletedWelcomeGuideKey = "pulse.settings.has_completed_welcome_guide"

    @Published public var showLaunchMotion: Bool {
        didSet { UserDefaults.standard.set(showLaunchMotion, forKey: showLaunchMotionKey) }
    }

    @Published public var hasCompletedWelcomeGuide: Bool {
        didSet { UserDefaults.standard.set(hasCompletedWelcomeGuide, forKey: hasCompletedWelcomeGuideKey) }
    }

    @Published public var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: launchAtLoginKey)
            updateLaunchAtLogin(enabled: launchAtLogin)
        }
    }

    @Published public var showInMenuBar: Bool {
        didSet {
            UserDefaults.standard.set(showInMenuBar, forKey: showInMenuBarKey)
        }
    }

    @Published public var keepRunningInBackground: Bool {
        didSet {
            UserDefaults.standard.set(keepRunningInBackground, forKey: keepRunningInBackgroundKey)
        }
    }

    @Published public var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: themeKey)
        }
    }

    @Published public var metricIntervalSeconds: Int {
        didSet {
            UserDefaults.standard.set(metricIntervalSeconds, forKey: metricIntervalKey)
        }
    }

    @Published public var healthCheckIntervalSeconds: Int {
        didSet {
            UserDefaults.standard.set(healthCheckIntervalSeconds, forKey: healthCheckIntervalKey)
        }
    }

    @Published public var notifyCritical: Bool {
        didSet { UserDefaults.standard.set(notifyCritical, forKey: notifyCriticalKey) }
    }

    @Published public var notifyWarning: Bool {
        didSet { UserDefaults.standard.set(notifyWarning, forKey: notifyWarningKey) }
    }

    @Published public var notifyRecovery: Bool {
        didSet { UserDefaults.standard.set(notifyRecovery, forKey: notifyRecoveryKey) }
    }

    private init() {
        let defaults = UserDefaults.standard
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            if status == .enabled {
                self.launchAtLogin = true
            } else if status == .notRegistered {
                self.launchAtLogin = false
            } else {
                self.launchAtLogin = defaults.object(forKey: launchAtLoginKey) as? Bool ?? false
            }
        } else {
            self.launchAtLogin = defaults.object(forKey: launchAtLoginKey) as? Bool ?? false
        }
        self.showInMenuBar = defaults.object(forKey: showInMenuBarKey) as? Bool ?? true
        self.keepRunningInBackground = defaults.object(forKey: keepRunningInBackgroundKey) as? Bool ?? true

        let rawTheme = defaults.string(forKey: themeKey) ?? AppTheme.system.rawValue
        self.theme = AppTheme(rawValue: rawTheme) ?? .system

        self.metricIntervalSeconds = defaults.object(forKey: metricIntervalKey) as? Int ?? 10
        self.healthCheckIntervalSeconds = defaults.object(forKey: healthCheckIntervalKey) as? Int ?? 30

        self.notifyCritical = defaults.object(forKey: notifyCriticalKey) as? Bool ?? true
        self.notifyWarning = defaults.object(forKey: notifyWarningKey) as? Bool ?? true
        self.notifyRecovery = defaults.object(forKey: notifyRecoveryKey) as? Bool ?? true
        self.showLaunchMotion = defaults.object(forKey: showLaunchMotionKey) as? Bool ?? true
        self.hasCompletedWelcomeGuide = defaults.bool(forKey: hasCompletedWelcomeGuideKey)
    }

    public func resetWelcomeGuide() {
        hasCompletedWelcomeGuide = false
    }

    private func updateLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                PulseLog.agent.error("SMAppService toggle failed: \(error.localizedDescription)")
            }
        }
    }
}

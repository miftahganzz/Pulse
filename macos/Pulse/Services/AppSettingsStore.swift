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
    private let showMetricsInMenuBarKey = "pulse.settings.show_metrics_in_menu_bar"
    private let keepRunningInBackgroundKey = "pulse.settings.keep_running_in_background"
    private let themeKey = "pulse.settings.theme"
    private let metricIntervalKey = "pulse.settings.metric_interval"
    private let healthCheckIntervalKey = "pulse.settings.health_check_interval"
    private let notifyCriticalKey = "pulse.settings.notify_critical"
    private let notifyWarningKey = "pulse.settings.notify_warning"
    private let notifyRecoveryKey = "pulse.settings.notify_recovery"
    private let showLaunchMotionKey = "pulse.settings.show_launch_motion"
    private let hasCompletedWelcomeGuideKey = "pulse.settings.has_completed_welcome_guide"
    private let requireBiometricForDestructiveActionsKey = "pulse.settings.require_biometric_destructive"
    private let autoClearClipboardKey = "pulse.settings.auto_clear_clipboard"
    private let isIPMaskedKey = "pulse.settings.is_ip_masked"

    @Published public var isIPMasked: Bool {
        didSet { UserDefaults.standard.set(isIPMasked, forKey: isIPMaskedKey) }
    }

    @Published public var requireBiometricForDestructiveActions: Bool {
        didSet { UserDefaults.standard.set(requireBiometricForDestructiveActions, forKey: requireBiometricForDestructiveActionsKey) }
    }

    @Published public var autoClearClipboard: Bool {
        didSet { UserDefaults.standard.set(autoClearClipboard, forKey: autoClearClipboardKey) }
    }

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

    @Published public var showMetricsInMenuBar: Bool {
        didSet {
            UserDefaults.standard.set(showMetricsInMenuBar, forKey: showMetricsInMenuBarKey)
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
        self.showMetricsInMenuBar = defaults.object(forKey: showMetricsInMenuBarKey) as? Bool ?? false
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
        self.requireBiometricForDestructiveActions = defaults.bool(forKey: requireBiometricForDestructiveActionsKey)
        self.autoClearClipboard = defaults.object(forKey: autoClearClipboardKey) as? Bool ?? true
        self.isIPMasked = defaults.object(forKey: isIPMaskedKey) as? Bool ?? true
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

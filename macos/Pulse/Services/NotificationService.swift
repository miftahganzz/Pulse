import Foundation
import UserNotifications

public final class NotificationService: NSObject, @unchecked Sendable {
    public static let shared = NotificationService()
    public var isEnabled: Bool = true

    private override init() {
        super.init()
    }

    private var isSupportedEnvironment: Bool {
        guard isEnabled else { return false }
        let processName = ProcessInfo.processInfo.processName
        if processName.contains("xctest") || processName.contains("swift") {
            return false
        }
        guard let bundleId = Bundle.main.bundleIdentifier, !bundleId.isEmpty else {
            return false
        }
        return Bundle.main.bundlePath.hasSuffix(".app")
    }

    public func requestAuthorization() {
        guard isSupportedEnvironment else {
            PulseLog.agent.info("Skipping notification authorization in CLI / test environment")
            return
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                PulseLog.agent.error("Notification permission error: \(error.localizedDescription)")
            } else if granted {
                PulseLog.agent.info("Notification permission granted")
            }
        }
    }

    public func sendAlert(title: String, body: String, identifier: String, deepLinkURL: String? = nil) {
        guard isSupportedEnvironment else {
            PulseLog.agent.info("Skipping notification post in CLI / test environment: [\(title)] \(body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let link = deepLinkURL {
            content.userInfo = ["deepLink": link]
        }

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                PulseLog.agent.error("Failed to post notification: \(error.localizedDescription)")
            }
        }
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let linkString = response.notification.request.content.userInfo["deepLink"] as? String,
           let url = URL(string: linkString) {
            Task { @MainActor in
                NavigationState.shared.handleDeepLink(url: url)
            }
        }
        completionHandler()
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}

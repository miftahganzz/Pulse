import Foundation
import AppKit
import LocalAuthentication

public final class BiometricService: @unchecked Sendable {
    public static let shared = BiometricService()

    private init() {}

    public var isBiometricAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    public var biometricTypeDescription: String {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            if context.biometryType == .touchID {
                return "Touch ID"
            }
        }
        return "Touch ID / Password"
    }

    public func authenticate(reason: String, completion: @escaping @Sendable (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                DispatchQueue.main.async {
                    completion(success)
                }
            }
        } else {
            // If authentication policy cannot be evaluated (e.g. headless/CI), allow
            DispatchQueue.main.async {
                completion(true)
            }
        }
    }
}

public enum ClipboardSecurity {
    public static func copySensitive(_ text: String, autoClearSeconds: Int = 60) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        if AppSettingsStore.shared.autoClearClipboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(autoClearSeconds)) {
                if pb.string(forType: .string) == text {
                    pb.clearContents()
                    PulseLog.security.debug("Auto-cleared sensitive token from clipboard after \(autoClearSeconds)s")
                }
            }
        }
    }
}

import Foundation
import Security

public enum KeychainService {
    private static let serviceName = "com.pulse.app.tokens"

    public static func saveToken(_ token: String, forServerId id: UUID) throws {
        let account = id.uuidString
        guard let data = token.data(using: .utf8) else { return }

        // Remove existing item if present
        deleteToken(forServerId: id)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            PulseLog.security.error("Failed to save token in Keychain: \(status)")
            throw KeychainError.unhandledError(status: status)
        }
        PulseLog.security.debug("Successfully saved token for server \(id)")
    }

    public static func getToken(forServerId id: UUID) -> String? {
        let account = id.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    public static func deleteToken(forServerId id: UUID) {
        let account = id.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        PulseLog.security.debug("Deleted token from Keychain for server \(id)")
    }

    // MARK: - Database Credentials
    private static let dbPasswordServicePrefix = "com.pulse.app.db."

    public static func saveDatabasePassword(_ password: String, forMonitorId monitorId: String) throws {
        guard let data = password.data(using: .utf8) else { return }
        let service = dbPasswordServicePrefix + monitorId

        deleteDatabasePassword(forMonitorId: monitorId)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: monitorId,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            PulseLog.security.error("Failed to save DB password in Keychain: \(status)")
            throw KeychainError.unhandledError(status: status)
        }
    }

    public static func getDatabasePassword(forMonitorId monitorId: String) -> String? {
        let service = dbPasswordServicePrefix + monitorId
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: monitorId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let pass = String(data: data, encoding: .utf8) else {
            return nil
        }
        return pass
    }

    public static func deleteDatabasePassword(forMonitorId monitorId: String) {
        let service = dbPasswordServicePrefix + monitorId
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: monitorId
        ]
        SecItemDelete(query as CFDictionary)
    }
}

public enum KeychainError: Error {
    case unhandledError(status: OSStatus)
}

import Foundation
import Security

public enum KeychainService {
    private static let serviceName = "com.pulse.app.tokens"
    private static let tokenDefaultsKey = "pulse.server_tokens"
    private static let certDefaultsKey = "pulse.pinned_cert_fingerprints"
    private static let dbPassDefaultsKey = "pulse.db_passwords"

    // Thread-safe / in-memory fast caches
    private static let lock = NSLock()
    private static var inMemoryTokens: [UUID: String] = [:]
    private static var inMemoryCertFingerprints: [UUID: String] = [:]
    private static var inMemoryDbPasswords: [String: String] = [:]

    // MARK: - Server Auth Tokens

    public static func saveToken(_ token: String, forServerId id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }

        inMemoryTokens[id] = token

        var dict = UserDefaults.standard.dictionary(forKey: tokenDefaultsKey) as? [String: String] ?? [:]
        dict[id.uuidString] = token
        UserDefaults.standard.set(dict, forKey: tokenDefaultsKey)

        // Silently remove any legacy Keychain item to avoid system security prompts on rebuilds
        deleteLegacyKeychainItem(service: serviceName, account: id.uuidString)
        PulseLog.security.debug("Successfully saved token locally for server \(id)")
    }

    public static func getToken(forServerId id: UUID) -> String? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = inMemoryTokens[id], !cached.isEmpty {
            return cached
        }

        if let dict = UserDefaults.standard.dictionary(forKey: tokenDefaultsKey) as? [String: String],
           let token = dict[id.uuidString], !token.isEmpty {
            inMemoryTokens[id] = token
            return token
        }

        // Migration fallback: if item existed in old Keychain, retrieve it and migrate to local store
        if let legacy = readLegacyKeychainItem(service: serviceName, account: id.uuidString) {
            inMemoryTokens[id] = legacy
            var dict = UserDefaults.standard.dictionary(forKey: tokenDefaultsKey) as? [String: String] ?? [:]
            dict[id.uuidString] = legacy
            UserDefaults.standard.set(dict, forKey: tokenDefaultsKey)
            deleteLegacyKeychainItem(service: serviceName, account: id.uuidString)
            return legacy
        }

        return nil
    }

    public static func deleteToken(forServerId id: UUID) {
        lock.lock()
        defer { lock.unlock() }

        inMemoryTokens.removeValue(forKey: id)

        if var dict = UserDefaults.standard.dictionary(forKey: tokenDefaultsKey) as? [String: String] {
            dict.removeValue(forKey: id.uuidString)
            UserDefaults.standard.set(dict, forKey: tokenDefaultsKey)
        }

        deleteLegacyKeychainItem(service: serviceName, account: id.uuidString)
        PulseLog.security.debug("Deleted token for server \(id)")
    }

    // MARK: - Database Credentials
    private static let dbPasswordServicePrefix = "com.pulse.app.db."

    public static func saveDatabasePassword(_ password: String, forMonitorId monitorId: String) throws {
        lock.lock()
        defer { lock.unlock() }

        inMemoryDbPasswords[monitorId] = password

        var dict = UserDefaults.standard.dictionary(forKey: dbPassDefaultsKey) as? [String: String] ?? [:]
        dict[monitorId] = password
        UserDefaults.standard.set(dict, forKey: dbPassDefaultsKey)

        deleteLegacyKeychainItem(service: dbPasswordServicePrefix + monitorId, account: monitorId)
    }

    public static func getDatabasePassword(forMonitorId monitorId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = inMemoryDbPasswords[monitorId], !cached.isEmpty {
            return cached
        }

        if let dict = UserDefaults.standard.dictionary(forKey: dbPassDefaultsKey) as? [String: String],
           let pass = dict[monitorId], !pass.isEmpty {
            inMemoryDbPasswords[monitorId] = pass
            return pass
        }

        if let legacy = readLegacyKeychainItem(service: dbPasswordServicePrefix + monitorId, account: monitorId) {
            inMemoryDbPasswords[monitorId] = legacy
            var dict = UserDefaults.standard.dictionary(forKey: dbPassDefaultsKey) as? [String: String] ?? [:]
            dict[monitorId] = legacy
            UserDefaults.standard.set(dict, forKey: dbPassDefaultsKey)
            deleteLegacyKeychainItem(service: dbPasswordServicePrefix + monitorId, account: monitorId)
            return legacy
        }

        return nil
    }

    public static func deleteDatabasePassword(forMonitorId monitorId: String) {
        lock.lock()
        defer { lock.unlock() }

        inMemoryDbPasswords.removeValue(forKey: monitorId)

        if var dict = UserDefaults.standard.dictionary(forKey: dbPassDefaultsKey) as? [String: String] {
            dict.removeValue(forKey: monitorId)
            UserDefaults.standard.set(dict, forKey: dbPassDefaultsKey)
        }

        deleteLegacyKeychainItem(service: dbPasswordServicePrefix + monitorId, account: monitorId)
    }

    // MARK: - TLS Certificate Fingerprints (TOFU Pinning)
    private static let certFingerprintServicePrefix = "com.pulse.app.cert."

    public static func saveCertFingerprint(_ fingerprint: String, forServerId id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }

        inMemoryCertFingerprints[id] = fingerprint

        var dict = UserDefaults.standard.dictionary(forKey: certDefaultsKey) as? [String: String] ?? [:]
        dict[id.uuidString] = fingerprint
        UserDefaults.standard.set(dict, forKey: certDefaultsKey)

        deleteLegacyKeychainItem(service: certFingerprintServicePrefix + id.uuidString, account: id.uuidString)
    }

    public static func getCertFingerprint(forServerId id: UUID) -> String? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = inMemoryCertFingerprints[id], !cached.isEmpty {
            return cached
        }

        if let dict = UserDefaults.standard.dictionary(forKey: certDefaultsKey) as? [String: String],
           let fp = dict[id.uuidString], !fp.isEmpty {
            inMemoryCertFingerprints[id] = fp
            return fp
        }

        return nil
    }

    public static func deleteCertFingerprint(forServerId id: UUID) {
        lock.lock()
        defer { lock.unlock() }

        inMemoryCertFingerprints.removeValue(forKey: id)

        if var dict = UserDefaults.standard.dictionary(forKey: certDefaultsKey) as? [String: String] {
            dict.removeValue(forKey: id.uuidString)
            UserDefaults.standard.set(dict, forKey: certDefaultsKey)
        }

        deleteLegacyKeychainItem(service: certFingerprintServicePrefix + id.uuidString, account: id.uuidString)
    }

    // MARK: - Legacy Keychain Cleanup Helpers

    private static func deleteLegacyKeychainItem(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func readLegacyKeychainItem(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }
}

public enum KeychainError: Error {
    case unhandledError(status: OSStatus)
}

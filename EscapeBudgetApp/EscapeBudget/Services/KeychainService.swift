import Foundation
import Security

/// Secure storage service using iOS Keychain for sensitive settings.
/// Provides encrypted storage that persists across app reinstalls (unless explicitly deleted).
final class KeychainService {
    static let shared = KeychainService()

    private let serviceName = Bundle.main.bundleIdentifier ?? "com.escapebudget"

    private init() {}

    // MARK: - Public API

    /// Stores a boolean value securely in the Keychain
    func setBool(_ value: Bool, forKey key: KeychainKey) -> Bool {
        let data = Data([value ? 1 : 0])
        return set(data, forKey: key)
    }

    /// Retrieves a boolean value from the Keychain
    func getBool(forKey key: KeychainKey) -> Bool? {
        guard let data = get(forKey: key), let byte = data.first else {
            return nil
        }
        return byte == 1
    }

    /// Stores a string value securely in the Keychain
    func setString(_ value: String, forKey key: KeychainKey) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return set(data, forKey: key)
    }

    /// Retrieves a string value from the Keychain
    func getString(forKey key: KeychainKey) -> String? {
        guard let data = get(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Removes a value from the Keychain
    @discardableResult
    func remove(forKey key: KeychainKey) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Removes all values stored by this service
    func removeAll() {
        for key in KeychainKey.allCases {
            remove(forKey: key)
        }
    }

    // MARK: - Private Implementation

    private func set(_ data: Data, forKey key: KeychainKey) -> Bool {
        // First try to delete any existing item
        remove(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status != errSecSuccess {
            SecurityLogger.shared.logSecurityError(
                KeychainError.unableToStore(status),
                context: "keychain_set"
            )
        }

        return status == errSecSuccess
    }

    private func get(forKey key: KeychainKey) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess {
            return result as? Data
        } else if status != errSecItemNotFound {
            SecurityLogger.shared.logSecurityError(
                KeychainError.unableToRetrieve(status),
                context: "keychain_get"
            )
        }

        return nil
    }
}

// MARK: - Keychain Keys

enum KeychainKey: String, CaseIterable {
    case biometricsEnabled = "biometrics_enabled"
    case passcodeEnabled = "passcode_enabled"
    case passcodeHash = "passcode_hash"
    case lastAuthenticatedTimestamp = "last_auth_timestamp"
    case authFailureCount = "auth_failure_count"
    case appleUserID = "account.apple.user_id"
    case appleEmail = "account.apple.email"
    case premiumEntitlement = "premium.entitlement"
    case trialStartISO8601 = "premium.trial_start"
    case autoBackupPassword = "backup.auto.password"
}

// MARK: - Errors

private enum KeychainError: Error {
    case unableToStore(OSStatus)
    case unableToRetrieve(OSStatus)
}

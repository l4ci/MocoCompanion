import Foundation
import Security
import os

/// Lightweight wrapper around the macOS Keychain for storing a single credential.
enum KeychainHelper {
    private static let logger = Logger(category: "Keychain")

    /// Save a string value to the Keychain. Empty string deletes the entry.
    static func save(value: String, service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        SecItemDelete(query as CFDictionary)

        if value.isEmpty { return }

        var addQuery = query
        addQuery[kSecValueData as String] = Data(value.utf8)
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Keychain save failed: \(status)")
        }
    }

    /// Load a string value from the Keychain. Returns nil if not found or inaccessible.
    static func load(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecInteractionNotAllowed || status == errSecAuthFailed || status == -25293 {
            logger.warning("Keychain item has restrictive ACL (status \(status)) — deleting for re-creation")
            SecItemDelete(query as CFDictionary)
            return nil
        }

        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                logger.error("Keychain load failed: \(status)")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

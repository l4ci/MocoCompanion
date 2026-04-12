import Foundation
import Security
import os

/// Lightweight wrapper around the macOS Keychain for storing a single credential.
enum KeychainHelper {
    private static let logger = Logger(category: "Keychain")

    /// Save a string value to the Keychain. Empty string deletes the entry.
    static func save(value: String, service: String, account: String) {
        let searchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]

        if value.isEmpty {
            SecItemDelete(searchQuery as CFDictionary)
            return
        }

        let valueData = Data(value.utf8)
        var addQuery = searchQuery
        addQuery[kSecValueData as String] = valueData
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateAttrs: [String: Any] = [
                kSecValueData as String: valueData,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ]
            let updateStatus = SecItemUpdate(searchQuery as CFDictionary, updateAttrs as CFDictionary)
            if updateStatus != errSecSuccess {
                logger.error("Keychain update failed: \(updateStatus)")
            }
        default:
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
            kSecUseDataProtectionKeychain as String: true,
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

    /// One-time migration from legacy login.keychain to Data Protection Keychain.
    /// Reads from legacy (without kSecUseDataProtectionKeychain), writes to new store,
    /// then deletes the legacy item.
    static func migrateToDataProtectionKeychain(service: String, account: String) {
        let migrationKey = "keychain.migrated.\(service).\(account)"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        // Read from legacy keychain (without data protection flag)
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(legacyQuery as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data,
           let value = String(data: data, encoding: .utf8), !value.isEmpty {
            // Save to Data Protection Keychain (using the new save() which includes the flag)
            save(value: value, service: service, account: account)
            // Delete from legacy keychain
            SecItemDelete(legacyQuery as CFDictionary)
            logger.info("Migrated keychain item to Data Protection Keychain")
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }
}

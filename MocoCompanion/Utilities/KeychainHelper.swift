import Foundation
import Security
import os

/// Lightweight wrapper around the macOS Keychain for storing a single credential.
enum KeychainHelper {
    private static let logger = Logger(category: "Keychain")

    /// Under XCTest the real Keychain is off-limits: the test host shares the
    /// login keychain with the installed app, so a test writing `apiKey` would
    /// overwrite the user's real credential, and every rebuilt (ad-hoc signed)
    /// test host would trigger an access prompt that hangs the run. Tests get
    /// a process-local in-memory store instead.
    private static let isRunningTests = ProcessInfo.processInfo.isRunningTests
    nonisolated(unsafe) private static var inMemoryStore: [String: String] = [:]
    private static let inMemoryLock = NSLock()

    private static func inMemoryKey(_ service: String, _ account: String) -> String { "\(service)\u{1F}\(account)" }

    /// Save a string value to the Keychain. Empty string deletes the entry.
    static func save(value: String, service: String, account: String) {
        if isRunningTests {
            inMemoryLock.withLock {
                if value.isEmpty { inMemoryStore.removeValue(forKey: inMemoryKey(service, account)) }
                else { inMemoryStore[inMemoryKey(service, account)] = value }
            }
            return
        }
        let searchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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
        if isRunningTests {
            return inMemoryLock.withLock { inMemoryStore[inMemoryKey(service, account)] }
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                logger.error("Keychain load failed: \(status)")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// One-time recovery from the v0.5.0 data-protection-keychain migration.
    /// That migration moved items into the data protection keychain
    /// (kSecUseDataProtectionKeychain), which fails on some Developer ID
    /// signing configurations. This reads from the data protection keychain,
    /// writes back to the login keychain, and cleans up.
    static func recoverFromDataProtectionKeychain(service: String, account: String) {
        guard !isRunningTests else { return }
        let recoveryKey = "keychain.recovered.\(service).\(account)"
        guard !UserDefaults.standard.bool(forKey: recoveryKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: recoveryKey) }

        // If the login keychain already has the item, nothing to recover.
        if load(service: service, account: account) != nil { return }

        // Try to read from the data protection keychain.
        let dpQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(dpQuery as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data,
           let value = String(data: data, encoding: .utf8), !value.isEmpty {
            save(value: value, service: service, account: account)
            SecItemDelete(dpQuery as CFDictionary)
            logger.info("Recovered keychain item from data protection keychain")
        }
    }
}

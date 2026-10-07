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
    @discardableResult
    static func save(value: String, service: String, account: String) -> OSStatus {
        if isRunningTests {
            inMemoryLock.withLock {
                if value.isEmpty { inMemoryStore.removeValue(forKey: inMemoryKey(service, account)) }
                else { inMemoryStore[inMemoryKey(service, account)] = value }
            }
            return errSecSuccess
        }
        let searchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        if value.isEmpty {
            let status = SecItemDelete(searchQuery as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                logger.error("Keychain delete failed: \(status)")
            }
            return status
        }

        let valueData = Data(value.utf8)
        var addQuery = searchQuery
        addQuery[kSecValueData as String] = valueData
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return status
        case errSecDuplicateItem:
            let updateAttrs: [String: Any] = [
                kSecValueData as String: valueData,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ]
            let updateStatus = SecItemUpdate(searchQuery as CFDictionary, updateAttrs as CFDictionary)
            if updateStatus != errSecSuccess {
                logger.error("Keychain update failed: \(updateStatus)")
            }
            return updateStatus
        default:
            logger.error("Keychain save failed: \(status)")
            return status
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

    enum RecoveryRead: Equatable {
        case value(String)
        case notFound
        case failure(OSStatus)
    }

    enum RecoveryStep: Equatable {
        case readDestination, readSource, saveDestination, verifyDestination, cleanupSource
    }

    enum RecoveryStatus: Equatable {
        case skippedForTests, alreadyCompleted, noSource, recovered
        case destinationConflict
        case retry(RecoveryStep, OSStatus)
    }

    /// Small injectable boundary: tests exercise the production recovery decisions
    /// without touching either Keychain or the user's defaults.
    struct RecoveryOperations {
        var isCompleted: () -> Bool
        var markCompleted: () -> Void
        var readDestination: () -> RecoveryRead
        var readSource: () -> RecoveryRead
        var saveDestination: (String) -> OSStatus
        var deleteSource: () -> OSStatus
    }

    /// Failure leaves completion unset, so the next invocation retries. An existing
    /// different destination is never overwritten and its source is never deleted.
    static func recover(using operations: RecoveryOperations) -> RecoveryStatus {
        guard !operations.isCompleted() else { return .alreadyCompleted }

        let destination = operations.readDestination()
        if case .failure(let status) = destination {
            return .retry(.readDestination, status)
        }

        let value: String
        switch operations.readSource() {
        case .notFound:
            operations.markCompleted()
            return .noSource
        case .failure(let status):
            return .retry(.readSource, status)
        case .value(let source):
            guard !source.isEmpty else { return .retry(.readSource, errSecDecode) }
            value = source
        }

        switch destination {
        case .value(let existing):
            guard existing == value else { return .destinationConflict }
        case .notFound:
            let status = operations.saveDestination(value)
            guard status == errSecSuccess else { return .retry(.saveDestination, status) }
        case .failure(let status):
            return .retry(.readDestination, status)
        }

        // Read back even on a cleanup retry: a previous successful write alone
        // is not proof that the destination still contains the recovered value.
        switch operations.readDestination() {
        case .value(let verified):
            guard verified == value else { return .retry(.verifyDestination, errSecDecode) }
        case .notFound:
            return .retry(.verifyDestination, errSecItemNotFound)
        case .failure(let status):
            return .retry(.verifyDestination, status)
        }

        let cleanupStatus = operations.deleteSource()
        guard cleanupStatus == errSecSuccess || cleanupStatus == errSecItemNotFound else {
            return .retry(.cleanupSource, cleanupStatus)
        }
        operations.markCompleted()
        return .recovered
    }

    /// Raw Keychain boundary. Injected backends never touch Security APIs.
    struct CredentialBackend {
        var readDestination: () -> RecoveryRead
        var readSource: () -> RecoveryRead
        var saveDestination: (String) -> OSStatus
        var deleteDestination: () -> OSStatus
        var deleteSource: () -> OSStatus
    }

    struct ResetStatus: Equatable {
        let destination: OSStatus
        let source: OSStatus
    }

    /// Persists reset intent separately from physical deletion. A locked Keychain
    /// can reject deletion; that must never make a reset credential usable again.
    struct CredentialStore {
        private let defaults: UserDefaults
        private let recoveryKey: String
        private let resetKey: String
        private let backend: CredentialBackend

        init(service: String, account: String, defaults: UserDefaults, backend: CredentialBackend? = nil) {
            self.defaults = defaults
            self.recoveryKey = "keychain.recovered.v2.\(service).\(account)"
            self.resetKey = "keychain.explicitReset.\(service).\(account)"
            self.backend = backend ?? KeychainHelper.credentialBackend(service: service, account: account)
        }

        func load() -> String? {
            guard !defaults.bool(forKey: resetKey) else { return nil }
            guard case .value(let value) = backend.readDestination() else { return nil }
            return value
        }

        @discardableResult
        func save(_ value: String) -> OSStatus {
            let status = value.isEmpty ? backend.deleteDestination() : backend.saveDestination(value)
            // Only a successfully saved new credential supersedes reset intent.
            // Keep recovery completed: a surviving legacy copy is still obsolete.
            if !value.isEmpty && status == errSecSuccess {
                defaults.removeObject(forKey: resetKey)
            }
            return status
        }

        @discardableResult
        func recover() -> RecoveryStatus {
            let status = KeychainHelper.recover(using: RecoveryOperations(
                isCompleted: { defaults.bool(forKey: recoveryKey) || defaults.bool(forKey: resetKey) },
                markCompleted: { defaults.set(true, forKey: recoveryKey) },
                readDestination: backend.readDestination,
                readSource: backend.readSource,
                saveDestination: backend.saveDestination,
                deleteSource: backend.deleteSource
            ))
            switch status {
            case .recovered:
                logger.info("Recovered keychain item from data protection keychain")
            case .retry(let step, let code):
                logger.error("Keychain recovery deferred at \(String(describing: step)): \(code)")
            case .destinationConflict:
                logger.notice("Keychain recovery deferred: destination differs from source")
            default:
                break
            }
            return status
        }

        @discardableResult
        func reset() -> ResetStatus {
            // Persist intent before either deletion, including when cleanup fails.
            defaults.set(true, forKey: resetKey)
            defaults.set(true, forKey: recoveryKey)
            let destination = backend.deleteDestination()
            let source = backend.deleteSource()
            for (store, status) in [("login", destination), ("data protection", source)] {
                if status != errSecSuccess && status != errSecItemNotFound {
                    logger.error("Credential reset cleanup deferred for \(store): \(status)")
                }
            }
            return ResetStatus(destination: destination, source: source)
        }
    }

    private static func credentialBackend(service: String, account: String) -> CredentialBackend {
        if isRunningTests {
            return CredentialBackend(
                readDestination: {
                    load(service: service, account: account).map(RecoveryRead.value) ?? .notFound
                },
                readSource: { .notFound },
                saveDestination: { save(value: $0, service: service, account: account) },
                deleteDestination: { save(value: "", service: service, account: account) },
                deleteSource: { errSecItemNotFound }
            )
        }
        let loginQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        var dpQuery = loginQuery
        dpQuery[kSecUseDataProtectionKeychain as String] = true
        return CredentialBackend(
            readDestination: { readForRecovery(query: loginQuery) },
            readSource: { readForRecovery(query: dpQuery) },
            saveDestination: { save(value: $0, service: service, account: account) },
            deleteDestination: { SecItemDelete(loginQuery as CFDictionary) },
            deleteSource: { SecItemDelete(dpQuery as CFDictionary) }
        )
    }

    /// Recovery from the v0.5.0 data-protection-keychain migration. The login
    /// Keychain is intentional: DP fails on some Developer ID configurations.
    @discardableResult
    static func recoverFromDataProtectionKeychain(service: String, account: String) -> RecoveryStatus {
        guard !isRunningTests else { return .skippedForTests }
        return CredentialStore(service: service, account: account, defaults: .standard).recover()
    }

    private static func readForRecovery(query: [String: Any]) -> RecoveryRead {
        var readQuery = query
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(readQuery as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8), !value.isEmpty else {
                return .failure(errSecDecode)
            }
            return .value(value)
        case errSecItemNotFound:
            return .notFound
        default:
            return .failure(status)
        }
    }
}

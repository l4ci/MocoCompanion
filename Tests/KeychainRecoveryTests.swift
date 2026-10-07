import Foundation
import Security
import Testing
@testable import MocoCompanion

@Suite("Keychain recovery")
struct KeychainRecoveryTests {
    private final class Store {
        var source: KeychainHelper.RecoveryRead = .value("credential")
        var destination: KeychainHelper.RecoveryRead = .notFound
        var verification: KeychainHelper.RecoveryRead?
        var saveStatus: OSStatus = errSecSuccess
        var cleanupStatus: OSStatus = errSecSuccess
        var destinationCleanupStatus: OSStatus = errSecSuccess
        var completed = false
        var events: [String] = []
        var reads = 0

        func credentials(defaults: UserDefaults) -> KeychainHelper.CredentialStore {
            KeychainHelper.CredentialStore(service: "test", account: "key", defaults: defaults, backend: .init(
                readDestination: { self.events.append("readDestination"); return self.destination },
                readSource: { self.events.append("readSource"); return self.source },
                saveDestination: {
                    self.events.append("saveDestination")
                    if self.saveStatus == errSecSuccess { self.destination = .value($0) }
                    return self.saveStatus
                },
                deleteDestination: {
                    self.events.append("deleteDestination")
                    // Intent must already be durable before any cleanup is attempted.
                    #expect(defaults.bool(forKey: "keychain.explicitReset.test.key"))
                    #expect(defaults.bool(forKey: "keychain.recovered.v2.test.key"))
                    if self.destinationCleanupStatus == errSecSuccess || self.destinationCleanupStatus == errSecItemNotFound {
                        self.destination = .notFound
                    }
                    return self.destinationCleanupStatus
                },
                deleteSource: {
                    self.events.append("deleteSource")
                    if self.cleanupStatus == errSecSuccess || self.cleanupStatus == errSecItemNotFound {
                        self.source = .notFound
                    }
                    return self.cleanupStatus
                }
            ))
        }

        func recover() -> KeychainHelper.RecoveryStatus {
            reads = 0
            return KeychainHelper.recover(using: .init(
                isCompleted: { self.completed },
                markCompleted: {
                    self.events.append("complete")
                    self.completed = true
                },
                readDestination: {
                    self.events.append("readDestination")
                    self.reads += 1
                    return self.reads > 1 ? (self.verification ?? self.destination) : self.destination
                },
                readSource: {
                    self.events.append("readSource")
                    return self.source
                },
                saveDestination: { value in
                    self.events.append("saveDestination")
                    if self.saveStatus == errSecSuccess { self.destination = .value(value) }
                    return self.saveStatus
                },
                deleteSource: {
                    self.events.append("deleteSource")
                    if self.cleanupStatus == errSecSuccess || self.cleanupStatus == errSecItemNotFound {
                        self.source = .notFound
                    }
                    return self.cleanupStatus
                }
            ))
        }
    }

    @Test("Success verifies the destination before deleting and completing")
    func successfulRecovery() {
        let store = Store()
        #expect(store.recover() == .recovered)
        #expect(store.destination == .value("credential"))
        #expect(store.source == .notFound)
        #expect(store.completed)
        #expect(store.events == ["readDestination", "readSource", "saveDestination",
                                 "readDestination", "deleteSource", "complete"])
        store.events = []
        #expect(store.recover() == .alreadyCompleted)
        #expect(store.events.isEmpty)
    }

    @Test("Only a definitive missing source completes without copying")
    func missingSource() {
        let store = Store()
        store.source = .notFound
        #expect(store.recover() == .noSource)
        #expect(store.completed)
        #expect(store.events == ["readDestination", "readSource", "complete"])
    }

    @Test("Destination read failures are not treated as missing", arguments: [errSecInteractionNotAllowed, errSecAuthFailed])
    func destinationReadFailure(status: OSStatus) {
        let store = Store()
        store.destination = .failure(status)
        #expect(store.recover() == .retry(.readDestination, status))
        #expect(!store.completed)
        #expect(store.source == .value("credential"))
        #expect(store.events == ["readDestination"])
        store.destination = .notFound
        #expect(store.recover() == .recovered)
    }

    @Test("Source read failures remain retryable", arguments: [errSecInteractionNotAllowed, errSecAuthFailed, errSecDecode])
    func sourceReadFailure(status: OSStatus) {
        let store = Store()
        store.source = .failure(status)
        #expect(store.recover() == .retry(.readSource, status))
        #expect(!store.completed)
        #expect(store.events == ["readDestination", "readSource"])
        store.source = .value("credential")
        #expect(store.recover() == .recovered)
    }

    @Test("Empty source data is preserved, not passed to save-as-delete")
    func emptySource() {
        let store = Store()
        store.source = .value("")
        #expect(store.recover() == .retry(.readSource, errSecDecode))
        #expect(!store.completed)
        #expect(store.source == .value(""))
        #expect(store.events == ["readDestination", "readSource"])
    }

    @Test("Failed writes preserve the source and retry", arguments: [errSecInteractionNotAllowed, errSecAuthFailed, errSecDuplicateItem])
    func saveFailure(status: OSStatus) {
        let store = Store()
        store.saveStatus = status
        #expect(store.recover() == .retry(.saveDestination, status))
        #expect(!store.completed)
        #expect(store.source == .value("credential"))
        #expect(!store.events.contains("deleteSource"))
        store.saveStatus = errSecSuccess
        #expect(store.recover() == .recovered)
    }

    @Test("Verification failures never permit deletion", arguments: [
        KeychainHelper.RecoveryRead.failure(errSecInteractionNotAllowed),
        .notFound, .value("different"), .value("")
    ])
    func verificationFailure(read: KeychainHelper.RecoveryRead) {
        let store = Store()
        store.verification = read
        let expected: OSStatus
        switch read {
        case .failure(let status): expected = status
        case .notFound: expected = errSecItemNotFound
        case .value: expected = errSecDecode
        }
        #expect(store.recover() == .retry(.verifyDestination, expected))
        #expect(!store.completed)
        #expect(store.source == .value("credential"))
        #expect(!store.events.contains("deleteSource"))
        store.verification = nil
        store.events = []
        #expect(store.recover() == .recovered)
        #expect(!store.events.contains("saveDestination"))
    }

    @Test("Cleanup failures retry even when the destination now exists")
    func cleanupFailure() {
        let store = Store()
        store.cleanupStatus = errSecInteractionNotAllowed
        #expect(store.recover() == .retry(.cleanupSource, errSecInteractionNotAllowed))
        #expect(!store.completed)
        #expect(store.source == .value("credential"))
        #expect(store.destination == .value("credential"))
        store.cleanupStatus = errSecSuccess
        store.events = []
        #expect(store.recover() == .recovered)
        #expect(store.events == ["readDestination", "readSource", "readDestination", "deleteSource", "complete"])
    }

    @Test("Already removed source during cleanup is success")
    func cleanupNotFound() {
        let store = Store()
        store.cleanupStatus = errSecItemNotFound
        #expect(store.recover() == .recovered)
        #expect(store.completed)
    }

    @Test("An existing matching destination allows verified cleanup")
    func matchingDestination() {
        let store = Store()
        store.destination = .value("credential")
        #expect(store.recover() == .recovered)
        #expect(!store.events.contains("saveDestination"))
        #expect(store.completed)
    }

    @Test("Different credentials are both preserved, including after failed cleanup")
    func destinationConflict() {
        let store = Store()
        store.cleanupStatus = errSecInteractionNotAllowed
        #expect(store.recover() == .retry(.cleanupSource, errSecInteractionNotAllowed))
        store.destination = .value("newer-credential")
        store.events = []
        #expect(store.recover() == .destinationConflict)
        #expect(store.source == .value("credential"))
        #expect(store.destination == .value("newer-credential"))
        #expect(!store.completed)
        #expect(store.events == ["readDestination", "readSource"])
    }

    @Test("Reset suppresses both surviving copies across reload, regardless of cleanup results",
          arguments: [errSecSuccess, errSecItemNotFound, errSecInteractionNotAllowed, errSecAuthFailed],
          [errSecSuccess, errSecItemNotFound, errSecInteractionNotAllowed, errSecAuthFailed])
    func resetPreventsResurrection(destinationStatus: OSStatus, sourceStatus: OSStatus) {
        let suite = "com.mococompanion.tests.reset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = Store()
        store.destination = .value("newer-credential")
        store.destinationCleanupStatus = destinationStatus
        store.cleanupStatus = sourceStatus
        let credentials = store.credentials(defaults: defaults)
        #expect(credentials.recover() == .destinationConflict)
        store.events = []
        #expect(credentials.reset() == .init(destination: destinationStatus, source: sourceStatus))
        #expect(store.events == ["deleteDestination", "deleteSource"])

        // Recreate the store with another defaults instance, as on relaunch.
        let reloaded = store.credentials(defaults: UserDefaults(suiteName: suite)!)
        store.events = []
        #expect(reloaded.recover() == .alreadyCompleted)
        #expect(reloaded.load() == nil)
        #expect(store.events.isEmpty)

        // Failed reauthentication must not expose the undeleted old login item.
        store.saveStatus = errSecAuthFailed
        #expect(reloaded.save("replacement") == errSecAuthFailed)
        #expect(reloaded.load() == nil)
        store.saveStatus = errSecSuccess
        #expect(reloaded.save("replacement") == errSecSuccess)
        let signedIn = store.credentials(defaults: UserDefaults(suiteName: suite)!)
        #expect(signedIn.load() == "replacement")
        #expect(signedIn.recover() == .alreadyCompleted)
    }

    @Test("Explicit reset cancels a pending recovery cleanup retry")
    func resetAfterFailedRecoveryCleanup() {
        let suite = "com.mococompanion.tests.reset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = Store()
        store.cleanupStatus = errSecInteractionNotAllowed
        let credentials = store.credentials(defaults: defaults)
        #expect(credentials.recover() == .retry(.cleanupSource, errSecInteractionNotAllowed))
        #expect(credentials.load() == "credential")
        credentials.reset()
        // Once unlocked, the old source still cannot be imported.
        store.cleanupStatus = errSecSuccess
        store.events = []
        let reloaded = store.credentials(defaults: UserDefaults(suiteName: suite)!)
        #expect(reloaded.recover() == .alreadyCompleted)
        #expect(reloaded.load() == nil)
        #expect(store.events.isEmpty)
    }


    @Test("Ordinary recovery remains retryable across CredentialStore reloads")
    func recoveryWithoutResetStillRetries() {
        let suite = "com.mococompanion.tests.reset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = Store()
        store.cleanupStatus = errSecInteractionNotAllowed
        #expect(store.credentials(defaults: defaults).recover() == .retry(.cleanupSource, errSecInteractionNotAllowed))
        #expect(store.source == .value("credential"))
        store.cleanupStatus = errSecSuccess
        let reloaded = store.credentials(defaults: UserDefaults(suiteName: suite)!)
        #expect(reloaded.recover() == .recovered)
        #expect(store.source == .notFound)
        #expect(reloaded.load() == "credential")
        #expect(reloaded.recover() == .alreadyCompleted)
    }

}

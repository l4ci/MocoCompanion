import Testing
import Foundation
import Security
@testable import MocoCompanion

@Suite("SettingsStore", .serialized)
@MainActor
struct SettingsStoreTests {
    private let suiteName = "com.mococompanion.tests"

    /// Synchronous MainActor tests cannot interleave shared settings mutations.
    /// Preserve the test host's state without accessing the real app domain.
    private func withFreshStore(_ body: (SettingsStore, UserDefaults) -> Void) {
        // Initialize the backing suite before seeding or snapshotting it: its
        // first access deliberately clears any leftovers from previous runs.
        let previous = SettingsStore()
        let defaults = UserDefaults(suiteName: suiteName)!
        let savedDomain = defaults.persistentDomain(forName: suiteName)
        let savedAPIKey = previous.apiKey
        let savedBreadcrumbsEnabled = BreadcrumbTrail.shared.isEnabled
        defer {
            previous.apiKey = savedAPIKey
            defaults.removePersistentDomain(forName: suiteName)
            if let savedDomain {
                defaults.setPersistentDomain(savedDomain, forName: suiteName)
            }
            BreadcrumbTrail.shared.setEnabled(savedBreadcrumbsEnabled)
        }

        defaults.removePersistentDomain(forName: suiteName)
        previous.apiKey = ""
        body(SettingsStore(), defaults)
    }

    @Test("Reset restores every fresh-install preference immediately and after reload")
    func resetRestoresFreshInstallDefaults() {
        withFreshStore { settings, _ in
            expectFreshInstallDefaults(settings)

            settings.subdomain = "example"
            settings.apiKey = "test-api-key"
            settings.launchAtLogin = true
            settings.soundEnabled = false
            settings.appearance = "dark"
            settings.favoritesEnabled = false
            settings.autoCompleteEnabled = false
            settings.defaultTab = .search
            settings.entryFontSizeBoost = 3
            settings.panelPositionX = 123
            settings.panelPositionY = 456
            settings.hasSavedPanelPosition = true
            settings.panelResetSeconds = 120
            settings.hasSeenFirstUseHint = true
            settings.appLanguage = "de"
            settings.descriptionRequired = true
            settings.showKeyboardHints = false
            settings.workingHoursStart = 10
            settings.workingHoursEnd = 20
            settings.workingDays = [1, 7]
            settings.customShortcutKeyCode = 42
            settings.customShortcutModifiers = 256
            settings.defaultWindow = .timeline
            settings.autotrackerEnabled = true
            settings.autotrackerRetentionDays = 30
            settings.autotrackerExcludedApps = ["com.example.custom"]
            settings.calendarEnabled = true
            settings.rulesEnabled = true
            settings.windowTitleTrackingEnabled = true
            settings.selectedCalendarId = "test-calendar"
            settings.demoMode = true
            settings.apiLogLevel = .debug
            settings.appLogLevel = .error
            settings.breadcrumbsEnabled = true
            #expect(BreadcrumbTrail.shared.isEnabled)

            settings.resetAllData()

            expectFreshInstallDefaults(settings)
            #expect(!BreadcrumbTrail.shared.isEnabled)
            expectFreshInstallDefaults(SettingsStore())
            #expect(!BreadcrumbTrail.shared.isEnabled)

            // Reset remains safe and stable when invoked again.
            settings.resetAllData()
            expectFreshInstallDefaults(settings)
            expectFreshInstallDefaults(SettingsStore())
        }
    }

    @Test("Reset removes dynamic notification overrides from the active test suite")
    func resetClearsNotificationOverrides() {
        withFreshStore { settings, defaults in
            for type in NotificationCatalog.NotificationType.allCases {
                settings.setNotificationEnabled(type, enabled: !type.defaultEnabled)
                #expect(settings.isNotificationEnabled(type) == (type.isDismissible ? !type.defaultEnabled : true))
            }
            let customized = SettingsStore()
            for type in NotificationCatalog.NotificationType.allCases where type.isDismissible {
                #expect(customized.isNotificationEnabled(type) == !type.defaultEnabled)
            }
            // Also clear keys unknown to SettingsStore, including old migrations.
            defaults.set("timeline", forKey: "shortcutTarget")
            defaults.set(true, forKey: "notification.retiredType")

            settings.resetAllData()

            #expect(defaults.object(forKey: "shortcutTarget") == nil)
            #expect(defaults.object(forKey: "notification.retiredType") == nil)
            let reloaded = SettingsStore()
            for type in NotificationCatalog.NotificationType.allCases {
                #expect(settings.isNotificationEnabled(type) == type.defaultEnabled)
                #expect(reloaded.isNotificationEnabled(type) == type.defaultEnabled)
                #expect(defaults.object(forKey: "notification.\(type.rawValue)") == nil)
            }
        }
    }

    @Test("Reset in XCTest leaves the bundle domain untouched")
    func resetPreservesBundleDomain() {
        withFreshStore { settings, _ in
            guard let bundleID = Bundle.main.bundleIdentifier else {
                Issue.record("Expected a bundle identifier for the test host")
                return
            }
            #expect(bundleID != suiteName)
            // Only read the real domain; never seed or clear user preferences.
            let before = UserDefaults.standard.persistentDomain(forName: bundleID) ?? [:]
            settings.resetAllData()
            let after = UserDefaults.standard.persistentDomain(forName: bundleID) ?? [:]
            #expect(NSDictionary(dictionary: before).isEqual(to: after))
        }
    }

    @Test("Reset survives reload when either Keychain refuses cleanup", arguments: [false, true])
    func resetPreventsCredentialRecoveryAfterReload(loginDeletionFails: Bool) {
        withFreshStore { _, defaults in
            var login: KeychainHelper.RecoveryRead = .value("current-key")
            let legacy: KeychainHelper.RecoveryRead = .value("legacy-key")
            var sourceDeleteCalls = 0
            var loginDeleteCalls = 0
            var sourceReads = 0
            let backend = KeychainHelper.CredentialBackend(
                readDestination: { login },
                readSource: { sourceReads += 1; return legacy },
                saveDestination: { login = .value($0); return errSecSuccess },
                deleteDestination: {
                    loginDeleteCalls += 1
                    if loginDeletionFails { return errSecInteractionNotAllowed }
                    login = .notFound
                    return errSecSuccess
                },
                deleteSource: { sourceDeleteCalls += 1; return errSecAuthFailed }
            )
            func makeCredentials() -> KeychainHelper.CredentialStore {
                .init(service: "reset-test", account: "apiKey", defaults: defaults, backend: backend)
            }
            let settings = SettingsStore(credentials: makeCredentials())
            #expect(settings.apiKey == "current-key")
            #expect(sourceReads == 1) // Conflict preserves the legacy copy.
            settings.subdomain = "example"
            settings.resetAllData()
            #expect(sourceDeleteCalls == 1)
            #expect(loginDeleteCalls >= 1)
            #expect(legacy == .value("legacy-key"))
            #expect(settings.apiKey.isEmpty)
            let reloaded = SettingsStore(credentials: makeCredentials())
            #expect(reloaded.apiKey.isEmpty)
            #expect(!reloaded.isConfigured)
            #expect(sourceReads == 1)

            // Repeat reset, including domain clearing, without losing suppression.
            reloaded.resetAllData()
            #expect(SettingsStore(credentials: makeCredentials()).apiKey.isEmpty)
            #expect(sourceReads == 1)
            reloaded.apiKey = "replacement-key"
            #expect(SettingsStore(credentials: makeCredentials()).apiKey == "replacement-key")
            #expect(sourceReads == 1)
        }
    }

    private func expectFreshInstallDefaults(_ settings: SettingsStore) {
        #expect(settings.subdomain.isEmpty)
        #expect(settings.apiKey.isEmpty)
        #expect(!settings.isConfigured)
        #expect(!settings.launchAtLogin)
        #expect(settings.soundEnabled)
        #expect(settings.appearance == "auto")
        #expect(settings.favoritesEnabled)
        #expect(settings.autoCompleteEnabled)
        #expect(settings.defaultTab == .today)
        #expect(settings.entryFontSizeBoost == 0)
        #expect(settings.panelPositionX == 0)
        #expect(settings.panelPositionY == 0)
        #expect(!settings.hasSavedPanelPosition)
        #expect(settings.panelResetSeconds == 60)
        #expect(!settings.hasSeenFirstUseHint)
        #expect(settings.appLanguage == "system")
        #expect(!settings.descriptionRequired)
        #expect(settings.showKeyboardHints)
        #expect(settings.workingHoursStart == 8)
        #expect(settings.workingHoursEnd == 17)
        #expect(settings.workingDays == [2, 3, 4, 5, 6])
        #expect(settings.customShortcutKeyCode == 0)
        #expect(settings.customShortcutModifiers == 0)
        #expect(settings.defaultWindow == .panel)
        #expect(!settings.autotrackerEnabled)
        #expect(settings.autotrackerRetentionDays == 14)
        #expect(settings.autotrackerExcludedApps == ["com.1password.1password", "com.mococompanion.app"])
        #expect(!settings.calendarEnabled)
        #expect(!settings.rulesEnabled)
        #expect(!settings.windowTitleTrackingEnabled)
        #expect(settings.selectedCalendarId == nil)
        #expect(!settings.demoMode)
        #expect(settings.apiLogLevel == .info)
        #expect(settings.appLogLevel == .info)
        #expect(!settings.breadcrumbsEnabled)
    }
}

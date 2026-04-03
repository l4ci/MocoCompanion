import Foundation
import os

/// Persists user settings. API key goes to Keychain; other preferences to UserDefaults.
@Observable
@MainActor
final class SettingsStore {
    private static let logger = Logger(category: "Settings")
    private static let keychainService = "com.mococompanion.api"
    private static let keychainAccount = "apiKey"

    // MARK: - Keys

    private enum Key {
        static let subdomain = "mocoSubdomain"
        static let launchAtLogin = "launchAtLogin"
        static let workingHoursStart = "workingHoursStart"
        static let workingHoursEnd = "workingHoursEnd"
        static let workingDays = "workingDays"
        static let soundEnabled = "soundEnabled"
        static let customShortcutKeyCode = "customShortcutKeyCode"
        static let customShortcutModifiers = "customShortcutModifiers"
        static let appearance = "appearance"
        static let favoritesEnabled = "favoritesEnabled"
        static let autoCompleteEnabled = "autoCompleteEnabled"
        static let defaultTab = "defaultTab"
        static let apiLogLevel = "apiLogLevel"
        static let appLogLevel = "appLogLevel"
        static let entryFontSizeBoost = "entryFontSizeBoost"
        static let panelPositionX = "panelPositionX"
        static let panelPositionY = "panelPositionY"
        static let hasSavedPanelPosition = "hasSavedPanelPosition"
        static let panelResetSeconds = "panelResetSeconds"
        static let hasSeenFirstUseHint = "hasSeenFirstUseHint"
        static let appLanguage = "appLanguage"
    }

    // MARK: - Defaults Helper

    /// Read a value from UserDefaults with a fallback when the key is absent.
    /// Handles the `bool(forKey:)` problem where absent keys return `false`.
    private static func read<T>(_ key: String, default fallback: T) -> T {
        let defaults = UserDefaults.standard
        guard let value = defaults.object(forKey: key) else { return fallback }
        return value as? T ?? fallback
    }

    private static func save(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }

    // MARK: - Credentials

    var subdomain: String {
        didSet { Self.save(Key.subdomain, subdomain) }
    }

    var apiKey: String {
        didSet { KeychainHelper.save(value: apiKey, service: Self.keychainService, account: Self.keychainAccount) }
    }

    /// Whether both subdomain and API key are configured.
    var isConfigured: Bool {
        !subdomain.isEmpty && !apiKey.isEmpty
    }

    // MARK: - Preferences: General

    var launchAtLogin: Bool {
        didSet { Self.save(Key.launchAtLogin, launchAtLogin) }
    }

    var soundEnabled: Bool {
        didSet { Self.save(Key.soundEnabled, soundEnabled) }
    }

    /// Appearance mode: "auto", "light", or "dark".
    var appearance: String {
        didSet { Self.save(Key.appearance, appearance) }
    }

    /// Whether the favorites section is shown in the quick-entry popup.
    var favoritesEnabled: Bool {
        didSet { Self.save(Key.favoritesEnabled, favoritesEnabled) }
    }

    /// Whether inline description autocomplete is enabled.
    var autoCompleteEnabled: Bool {
        didSet { Self.save(Key.autoCompleteEnabled, autoCompleteEnabled) }
    }

    /// Default tab when opening the panel: "search" or "today".
    var defaultTab: String {
        didSet { Self.save(Key.defaultTab, defaultTab) }
    }

    /// Extra font-size boost for entry rows (0–3 points on top of the base size).
    var entryFontSizeBoost: Int {
        didSet { Self.save(Key.entryFontSizeBoost, entryFontSizeBoost) }
    }

    /// Panel width scaled proportionally to font-size boost.
    /// Base: 520pt at 15pt font. Scales linearly so text/width ratio stays constant.
    var panelWidth: CGFloat {
        520 * (15 + CGFloat(entryFontSizeBoost)) / 15
    }

    // MARK: - Panel Position (persisted across launches)

    var panelPositionX: Double {
        didSet { Self.save(Key.panelPositionX, panelPositionX) }
    }
    var panelPositionY: Double {
        didSet { Self.save(Key.panelPositionY, panelPositionY) }
    }
    var hasSavedPanelPosition: Bool {
        didSet { Self.save(Key.hasSavedPanelPosition, hasSavedPanelPosition) }
    }

    func savePanelPosition(_ origin: NSPoint) {
        panelPositionX = Double(origin.x)
        panelPositionY = Double(origin.y)
        hasSavedPanelPosition = true
    }

    /// Seconds after hiding before the panel resets to the default tab. Default: 60.
    var panelResetSeconds: Int {
        didSet { Self.save(Key.panelResetSeconds, panelResetSeconds) }
    }

    /// Whether the user has seen the first-use keyboard hint overlay.
    var hasSeenFirstUseHint: Bool {
        didSet { Self.save(Key.hasSeenFirstUseHint, hasSeenFirstUseHint) }
    }

    /// App language: "system" (follow macOS), "en", or "de".
    var appLanguage: String {
        didSet { Self.save(Key.appLanguage, appLanguage) }
    }

    /// The resolved Locale for formatting dates, numbers, and greetings.
    var resolvedLocale: Locale {
        switch appLanguage {
        case "en": Locale(identifier: "en")
        case "de": Locale(identifier: "de_DE")
        default: .current
        }
    }

    func resetPanelPosition() {
        hasSavedPanelPosition = false
    }

    // MARK: - Preferences: Work Schedule

    var workingHoursStart: Int {
        didSet { Self.save(Key.workingHoursStart, workingHoursStart) }
    }

    var workingHoursEnd: Int {
        didSet { Self.save(Key.workingHoursEnd, workingHoursEnd) }
    }

    /// Weekdays the user works, using Calendar weekday numbering (1=Sun, 2=Mon, ..., 7=Sat).
    var workingDays: Set<Int> {
        didSet { Self.save(Key.workingDays, Array(workingDays)) }
    }

    // MARK: - Preferences: Shortcut

    var customShortcutKeyCode: UInt32 {
        didSet { Self.save(Key.customShortcutKeyCode, Int(customShortcutKeyCode)) }
    }

    var customShortcutModifiers: UInt32 {
        didSet { Self.save(Key.customShortcutModifiers, Int(customShortcutModifiers)) }
    }

    /// Whether the user has set a custom shortcut (non-zero key code).
    var hasCustomShortcut: Bool {
        customShortcutKeyCode != 0
    }

    // MARK: - Preferences: Debug

    /// API log level (0=debug, 1=info, 2=warning, 3=error).
    var apiLogLevel: AppLogger.LogLevel {
        didSet {
            Self.save(Key.apiLogLevel, apiLogLevel.rawValue)
            Task { await AppLogger.shared.updateLogLevels(api: apiLogLevel, app: appLogLevel) }
        }
    }

    /// App log level (0=debug, 1=info, 2=warning, 3=error).
    var appLogLevel: AppLogger.LogLevel {
        didSet {
            Self.save(Key.appLogLevel, appLogLevel.rawValue)
            Task { await AppLogger.shared.updateLogLevels(api: apiLogLevel, app: appLogLevel) }
        }
    }

    // MARK: - Init

    init() {
        let loadedKey = KeychainHelper.load(service: Self.keychainService, account: Self.keychainAccount) ?? ""

        self.subdomain = Self.read(Key.subdomain, default: "")
        self.apiKey = loadedKey
        self.launchAtLogin = Self.read(Key.launchAtLogin, default: false)
        self.workingHoursStart = Self.read(Key.workingHoursStart, default: 8)
        self.workingHoursEnd = Self.read(Key.workingHoursEnd, default: 17)
        self.soundEnabled = Self.read(Key.soundEnabled, default: true)
        self.appearance = Self.read(Key.appearance, default: "auto")
        self.favoritesEnabled = Self.read(Key.favoritesEnabled, default: true)
        self.autoCompleteEnabled = Self.read(Key.autoCompleteEnabled, default: true)
        self.defaultTab = Self.read(Key.defaultTab, default: "today")
        self.entryFontSizeBoost = Self.read(Key.entryFontSizeBoost, default: 0)
        self.panelPositionX = Self.read(Key.panelPositionX, default: 0.0)
        self.panelPositionY = Self.read(Key.panelPositionY, default: 0.0)
        self.hasSavedPanelPosition = Self.read(Key.hasSavedPanelPosition, default: false)
        self.panelResetSeconds = Self.read(Key.panelResetSeconds, default: 60)
        self.hasSeenFirstUseHint = Self.read(Key.hasSeenFirstUseHint, default: false)
        self.appLanguage = Self.read(Key.appLanguage, default: "system")
        self.customShortcutKeyCode = UInt32(Self.read(Key.customShortcutKeyCode, default: 0) as Int)
        self.customShortcutModifiers = UInt32(Self.read(Key.customShortcutModifiers, default: 0) as Int)
        self.apiLogLevel = AppLogger.LogLevel(rawValue: Self.read(Key.apiLogLevel, default: 1)) ?? .info
        self.appLogLevel = AppLogger.LogLevel(rawValue: Self.read(Key.appLogLevel, default: 1)) ?? .info

        // Working days: stored as [Int], default Mon-Fri
        if let daysArray = UserDefaults.standard.object(forKey: Key.workingDays) as? [Int] {
            self.workingDays = Set(daysArray)
        } else {
            self.workingDays = [2, 3, 4, 5, 6]
        }

        // Migrate Keychain item to use kSecAttrAccessibleWhenUnlocked
        if !loadedKey.isEmpty {
            KeychainHelper.save(value: loadedKey, service: Self.keychainService, account: Self.keychainAccount)
        }
    }

    // MARK: - Reset

    /// Nuke all persisted data: Keychain API key, all UserDefaults entries for this app.
    /// After calling this, the app is in a fresh-install state.
    func resetAllData() {
        // 1. Delete API key from Keychain
        KeychainHelper.save(value: "", service: Self.keychainService, account: Self.keychainAccount)
        apiKey = ""

        // 2. Clear subdomain
        subdomain = ""

        // 3. Remove the entire UserDefaults domain for this app
        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
            UserDefaults.standard.synchronize()
        }

        // 4. Reset in-memory properties to defaults
        launchAtLogin = false
        soundEnabled = true
        appearance = "auto"
        favoritesEnabled = true
        autoCompleteEnabled = true
        defaultTab = "today"
        entryFontSizeBoost = 0
        hasSavedPanelPosition = false
        panelResetSeconds = 60
        hasSeenFirstUseHint = false
        appLanguage = "system"
        workingHoursStart = 8
        workingHoursEnd = 17
        workingDays = [2, 3, 4, 5, 6]
        customShortcutKeyCode = 0
        customShortcutModifiers = 0
        apiLogLevel = .info
        appLogLevel = .info

        Self.logger.info("All app data has been reset")
    }

    // MARK: - Notification Preferences

    /// Check if a notification type is enabled. Persistent notifications always return true.
    func isNotificationEnabled(_ type: NotificationCatalog.NotificationType) -> Bool {
        guard type.isDismissible else { return true }
        let key = "notification.\(type.rawValue)"
        return Self.read(key, default: type.defaultEnabled)
    }

    /// Set the enabled state for a notification type.
    func setNotificationEnabled(_ type: NotificationCatalog.NotificationType, enabled: Bool) {
        guard type.isDismissible else { return }
        let key = "notification.\(type.rawValue)"
        Self.save(key, enabled)
    }

}

// MARK: - Typed Projections
// Read-only value snapshots that scope settings by concern.
// Computed properties trigger @Observable tracking on the underlying stored properties.

struct SoundSettings: Sendable {
    let enabled: Bool
}

struct WorkScheduleSettings: Sendable {
    let hoursStart: Int
    let hoursEnd: Int
    let workingDays: Set<Int>

    /// Check if a given weekday + hour falls within working hours.
    func isWithinWorkingHours(weekday: Int, hour: Int) -> Bool {
        workingDays.contains(weekday) && hour >= hoursStart && hour < hoursEnd
    }
}

struct QuickEntrySettings: Sendable {
    let autoCompleteEnabled: Bool
    let favoritesEnabled: Bool
}

extension SettingsStore {
    var sound: SoundSettings {
        SoundSettings(enabled: soundEnabled)
    }

    var schedule: WorkScheduleSettings {
        WorkScheduleSettings(
            hoursStart: workingHoursStart,
            hoursEnd: workingHoursEnd,
            workingDays: workingDays
        )
    }

    var quickEntry: QuickEntrySettings {
        QuickEntrySettings(
            autoCompleteEnabled: autoCompleteEnabled,
            favoritesEnabled: favoritesEnabled
        )
    }
}

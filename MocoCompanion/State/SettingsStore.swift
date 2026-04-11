import Foundation
import os

// # Adding a new preference
//
// 1. Add the key string to the `private enum Key` block.
// 2. Add a stored `var` with `didSet { Self.save(Key.xxx, xxx) }`.
// 3. Initialize it in `init()` via `self.xxx = Self.read(Key.xxx, default: ...)`.
// 4. Reset it to its default in `resetAllData()`.
//
// The pattern is verbose but deliberate: every preference's persistence
// behaviour is explicit and co-located with its declaration. Batch
// updates are NOT supported — each `didSet` fires a separate
// UserDefaults write. If you need post-save validation or cross-field
// checks, add a dedicated method (e.g. `validateCalendarSelection`) and
// call it explicitly after setting related properties.
//
// ## Optional String preferences (e.g. `selectedCalendarId`)
//
// `Self.read(_:default:)` returns a non-optional `T`, so optional
// String preferences need two small deviations from the standard pattern:
//
// - **init**: use `UserDefaults.standard.string(forKey:)` directly
//   (returns nil when the key is absent).
// - **didSet**: branch on nil — call `Self.save` when a value is present,
//   `UserDefaults.standard.removeObject(forKey:)` when nil (storing NSNull
//   via `Self.save(nil)` would leave a junk entry in UserDefaults).
//
// ## Migration defaults
//
// When a new preference's sensible default depends on a *legacy* persisted
// value, read the legacy key first and pass it as the default:
//
//   let legacyFlag = Self.read(Key.legacyKey, default: false)
//   self.newPref = Self.read(Key.newPref, default: legacyFlag)
//
// (See `rulesEnabled` in `init()` for the canonical example.)

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
        static let autotrackerEnabled = "autotrackerEnabled"
        static let autotrackerRetentionDays = "autotrackerRetentionDays"
        static let autotrackerExcludedApps = "autotrackerExcludedApps"
        static let calendarEnabled = "calendarEnabled"
        static let rulesEnabled = "rulesEnabled"
        static let windowTitleTrackingEnabled = "windowTitleTrackingEnabled"
        static let selectedCalendarId = "selectedCalendarId"
        static let panelPositionX = "panelPositionX"
        static let panelPositionY = "panelPositionY"
        static let hasSavedPanelPosition = "hasSavedPanelPosition"
        static let panelResetSeconds = "panelResetSeconds"
        static let hasSeenFirstUseHint = "hasSeenFirstUseHint"
        static let appLanguage = "appLanguage"
        static let descriptionRequired = "descriptionRequired"
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

    private static func saveJSON<T: Encodable>(_ key: String, _ value: T) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func loadJSON<T: Decodable>(_ key: String, default fallback: T) -> T {
        guard let data = UserDefaults.standard.data(forKey: key) else { return fallback }
        return (try? JSONDecoder().decode(T.self, from: data)) ?? fallback
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

    /// Whether the Moco instance requires a non-empty description on activities.
    /// Auto-detected from API validation errors; can also be toggled manually.
    var descriptionRequired: Bool {
        didSet { Self.save(Key.descriptionRequired, descriptionRequired) }
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

    // MARK: - Preferences: Autotracker

    var autotrackerEnabled: Bool {
        didSet { Self.save(Key.autotrackerEnabled, autotrackerEnabled) }
    }

    var autotrackerRetentionDays: Int {
        didSet { Self.save(Key.autotrackerRetentionDays, autotrackerRetentionDays) }
    }

    /// Bundle IDs excluded from autotracker recording. Persisted as JSON array in UserDefaults.
    var autotrackerExcludedApps: [String] {
        didSet { Self.saveJSON(Key.autotrackerExcludedApps, autotrackerExcludedApps) }
    }

    func addExcludedApp(_ bundleId: String) {
        let trimmed = bundleId.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !autotrackerExcludedApps.contains(trimmed) else { return }
        autotrackerExcludedApps.append(trimmed)
    }

    func removeExcludedApp(_ bundleId: String) {
        autotrackerExcludedApps.removeAll { $0 == bundleId }
    }

    /// Whether the Timeline window shows a calendar column and fetches
    /// events from the user's selected calendar. Controls EventKit
    /// permission flow, the column's visibility, and calendar-rule firing.
    var calendarEnabled: Bool {
        didSet { Self.save(Key.calendarEnabled, calendarEnabled) }
    }

    /// Whether any rules fire at all, regardless of source. Gates both
    /// `app`- and `calendar`-type rules, the "Create rule" context menu
    /// items, the rule list entry in settings, and the Timeline toolbar's
    /// "Manage Rules" button.
    var rulesEnabled: Bool {
        didSet { Self.save(Key.rulesEnabled, rulesEnabled) }
    }

    /// Whether Autotracker captures focused-window titles alongside the
    /// frontmost app bundle. Requires Accessibility permission. Nested
    /// under `appRecordingEnabled` (no-op when parent is off).
    var windowTitleTrackingEnabled: Bool {
        didSet { Self.save(Key.windowTitleTrackingEnabled, windowTitleTrackingEnabled) }
    }

    /// EKCalendar.calendarIdentifier of the currently chosen calendar.
    /// Nil when calendar integration is enabled but the user hasn't
    /// picked one yet (shows "Pick a calendar" placeholder in the column).
    var selectedCalendarId: String? {
        didSet {
            if let id = selectedCalendarId {
                Self.save(Key.selectedCalendarId, id)
            } else {
                UserDefaults.standard.removeObject(forKey: Key.selectedCalendarId)
            }
        }
    }

    /// Canonical name for app-activity recording. Forwards to the
    /// legacy `autotrackerEnabled` property so existing persisted
    /// state and call sites keep working during the rename.
    var appRecordingEnabled: Bool {
        get { autotrackerEnabled }
        set { autotrackerEnabled = newValue }
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
        self.descriptionRequired = Self.read(Key.descriptionRequired, default: false)
        self.autotrackerEnabled = Self.read(Key.autotrackerEnabled, default: false)
        self.autotrackerRetentionDays = Self.read(Key.autotrackerRetentionDays, default: 14)
        self.autotrackerExcludedApps = Self.loadJSON(Key.autotrackerExcludedApps, default: [])
        self.calendarEnabled = Self.read(Key.calendarEnabled, default: false)
        // New users default rules off; existing users who had autotracker on
        // (= rules were implicitly active) keep them enabled.
        let existingAutotracker = Self.read(Key.autotrackerEnabled, default: false)
        self.rulesEnabled = Self.read(Key.rulesEnabled, default: existingAutotracker)
        self.windowTitleTrackingEnabled = Self.read(Key.windowTitleTrackingEnabled, default: false)
        self.selectedCalendarId = UserDefaults.standard.string(forKey: Key.selectedCalendarId)
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
        descriptionRequired = false
        autotrackerEnabled = false
        autotrackerRetentionDays = 14
        autotrackerExcludedApps = []
        calendarEnabled = false
        rulesEnabled = false
        windowTitleTrackingEnabled = false
        selectedCalendarId = nil

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

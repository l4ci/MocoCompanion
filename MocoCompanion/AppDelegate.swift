import AppKit
import SwiftUI
import UserNotifications
import os

/// Application delegate: lifecycle, hotkey, and controller wiring.
/// Menubar status item logic extracted to StatusItemController.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private static let logger = Logger(category: "AppDelegate")

    let panelController = PanelController()
    let appState = AppState()

    private var statusItemController: StatusItemController?
    private var hotKey: HotKey?
    private var settingsWindow: NSWindow?
    private var setupWizardWindow: NSWindow?
    private var autotrackerWindow: NSWindow?
    private var autotrackerViewModel: TimelineViewModel?
    private let updateChecker = UpdateChecker()

    // Background tasks
    private var backgroundPollingTask: Task<Void, Never>?
    private var timerSyncTask: Task<Void, Never>?
    private var periodicSyncTask: Task<Void, Never>?

    /// Convenience accessor for the timer service.
    var timerService: TimerService { appState.timerService }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock by default. Using setActivationPolicy instead of LSUIElement
        // so macOS registers the bundle properly — which is required for Notification
        // Center to resolve and display the app icon in notification banners.
        NSApp.setActivationPolicy(.accessory)

        // Enforce single instance
        let runningInstances = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if runningInstances.count > 1 {
            for app in runningInstances where app != NSRunningApplication.current {
                app.activate()
            }
            Self.logger.info("Another instance is already running — terminating")
            NSApp.terminate(nil)
            return
        }

        Task {
            await AppLogger.shared.updateLogLevels(api: appState.settings.apiLogLevel, app: appState.settings.appLogLevel)
            await AppLogger.shared.app("Application launched", level: .info, context: "Lifecycle")
        }

        panelController.appState = appState
        panelController.onShowAutotracker = { [weak self] in self?.showAutotrackerWindow() }
        updateHotKey()
        NotificationDispatcher.requestAuthorization()
        UNUserNotificationCenter.current().delegate = self

        // Status item controller
        let sic = StatusItemController(
            timerService: timerService,
            appState: appState,
            onShowPanel: { [weak self] in self?.panelController.toggle() },
            onNewTimer: { [weak self] in self?.panelController.showFresh() },
            onShowSettings: { [weak self] in self?.showSettings() },
            onShowAutotracker: { [weak self] in self?.showAutotrackerWindow() }
        )
        sic.setup()
        statusItemController = sic

        // First launch: show setup wizard if not configured
        if !appState.settings.isConfigured {
            Self.logger.info("First launch detected — showing setup wizard")
            showSetupWizard()
        }

        // Delayed health check — handles menubar managers (e.g. Bartender) that
        // can hide the status item or interfere with hotkey registration at startup.
        Task { [weak self] in
            for delay: Duration in [.seconds(2), .seconds(5), .seconds(10)] {
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled else { return }
                self.statusItemController?.verifyOrRecreate()
            }
        }

        Task {
            await appState.fetchSession()
            await appState.fetchProjects()
            await timerService.sync()
        }

        // Delayed update check — 5 seconds after launch to avoid blocking startup
        Task {
            try? await Task.sleep(for: .seconds(5))
            if let release = await updateChecker.checkForUpdate() {
                Self.logger.info("Update available: \(release.version)")
                let content = UNMutableNotificationContent()
                content.title = String(localized: "update.available")
                content.body = String(localized: "update.body \(release.version)")
                content.sound = .default
                content.userInfo = ["updateURL": release.url.absoluteString]

                let request = UNNotificationRequest(
                    identifier: "update-available",
                    content: content,
                    trigger: nil
                )
                try? await UNUserNotificationCenter.current().add(request)
            }
        }

        // Background managers — all monitors registered in AppState.monitorEngine
        // MonitorEngine handles polling, dedup, and lifecycle

        let logger = Self.logger
        backgroundPollingTask = repeatingTask(every: .seconds(600)) { [weak self] in
            guard let self else { return }
            await self.appState.fetchProjects()
            // Only refresh budgets when actively tracking — saves API calls at rest
            if case .running = await self.timerService.timerState {
                await self.appState.budgetService.refreshBudgets(projectIds: self.appState.relevantBudgetProjectIds)
            }
            logger.info("Background project poll completed")
        }

        timerSyncTask = repeatingTask(every: .seconds(60)) { [weak self] in
            guard let self else { return }
            // R013: only sync when a timer is active — avoids 1 API call/min at idle
            guard case .running = await self.timerService.timerState else { return }
            await self.timerService.sync()
        }

        periodicSyncTask = repeatingTask(every: .seconds(300)) { [weak self] in
            guard let self else { return }
            let today = DateUtilities.todayString()
            var dates = [today]
            if let yesterday = DateUtilities.yesterdayString() { dates.append(yesterday) }
            await self.appState.syncEngine.sync(dates: dates)
            logger.info("Periodic background sync completed")
        }

        // Autotracker: cleanup old records and start if enabled
        appState.autotracker.cleanup(olderThanDays: appState.settings.autotrackerRetentionDays)
        if appState.settings.autotrackerEnabled {
            appState.autotracker.start()
        }
    }

    /// Prevent the app from quitting when the last window closes — it lives in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Show the Dock icon while any regular window (settings, wizard) is open,
    /// hide it again when all windows are closed.
    func applicationDidBecomeActive(_ notification: Notification) {
        if hasVisibleRegularWindows {
            NSApp.setActivationPolicy(.regular)
        }
    }

    func applicationWillResignActive(_ notification: Notification) {
        if !hasVisibleRegularWindows {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Returns true if any regular (non-NSPanel) window is currently visible.
    /// NSPanel is used for the floating quick-entry panel — it never counts as a "real" window.
    private var hasVisibleRegularWindows: Bool {
        NSApp.windows.contains { $0.isVisible && !($0 is NSPanel) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusItemController?.teardown()
        appState.monitorEngine.stopAll()
        appState.autotracker.stop()
        backgroundPollingTask?.cancel()
        timerSyncTask?.cancel()
        periodicSyncTask?.cancel()
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Handle notification actions — opens update URL or autotracker window.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo

        if response.actionIdentifier == NotificationDispatcher.openAutotrackerActionId {
            let targetDateStr = userInfo["targetDate"] as? String
            await MainActor.run {
                self.showAutotrackerWindow(dateString: targetDateStr)
            }
            return
        }

        if let urlString = userInfo["updateURL"] as? String,
           let url = URL(string: urlString) {
            await MainActor.run {
                _ = NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Setup Wizard

    private func showSetupWizard() {
        if let existing = setupWizardWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let wizardView = SetupWizardView(
            settings: appState.settings,
            onComplete: { [weak self] in
                guard let self else { return }
                self.setupWizardWindow?.close()
                self.setupWizardWindow = nil
                Self.logger.info("Setup wizard completed — fetching session and projects")
                Task {
                    await self.appState.fetchSession()
                    await self.appState.fetchProjects()
                    await self.timerService.sync()
                    // Open the panel so the user sees the app immediately after setup
                    self.panelController.show()
                }
            }
        )

        let hostingView = NSHostingController(rootView: wizardView)

        let window = NSWindow(contentViewController: hostingView)
        window.title = String(localized: "setup.welcome")
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 450, height: 440))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        setupWizardWindow = window
        Self.logger.info("Setup wizard window opened")
    }

    // MARK: - Settings

    /// Public entry point for opening settings.
    func openSettings() {
        showSettings()
    }

    @objc func showSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            settings: appState.settings,
            appState: appState,
            onShortcutChanged: { [weak self] keyCode, modifiers in
                self?.updateHotKey(keyCode: keyCode, modifiers: modifiers)
            }
        )

        let hostingView = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingView)
        window.title = String(localized: "settings.windowTitle")
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 780, height: 580))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window
        Self.logger.info("Settings window opened")
    }

    // MARK: - Autotracker Window

    func showAutotrackerWindow() {
        showAutotrackerWindow(dateString: nil)
    }

    /// Show the autotracker window, optionally navigating to a specific date (YYYY-MM-DD).
    func showAutotrackerWindow(dateString: String?) {
        if let existing = autotrackerWindow, existing.isVisible {
            // If a target date was requested, navigate to it via the view model
            if let dateString, let date = Self.parseDate(dateString) {
                autotrackerViewModel?.selectDate(date)
            }
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let vm = TimelineViewModel(
            shadowEntryStore: appState.shadowEntryStore,
            autotracker: appState.autotracker,
            syncState: appState.syncState,
            workdayStartHour: appState.settings.workingHoursStart,
            workdayEndHour: appState.settings.workingHoursEnd
        )
        vm.deleteUndoManager = appState.deleteUndoManager
        vm.syncEngine = appState.syncEngine
        vm.onEntryChanged = { [weak self] in
            await self?.appState.activityService.refreshTodayStats()
        }
        vm.onRefresh = { [weak self] in
            guard let self else { return }
            let dateStr = TimelineGeometry.dateString(from: vm.selectedDate)
            await self.appState.syncEngine.sync(dates: [dateStr])
        }
        // Let TodayView mutations reach back into this window: when
        // DeleteUndoManager flips a row to pendingDelete, reload the
        // timeline so the entry disappears immediately. The closure holds
        // the viewmodel weakly so it becomes a no-op after a window close.
        appState.deleteUndoManager.onStoreChanged = { [weak vm] in
            await vm?.loadData()
        }
        appState.activityService.onStoreChanged = { [weak vm] in
            await vm?.loadData()
        }
        autotrackerViewModel = vm

        // Navigate to target date if specified
        if let dateString, let date = Self.parseDate(dateString) {
            vm.selectDate(date)
        }

        let timelineView = TimelineWindow(
            viewModel: vm,
            syncState: appState.syncState,
            projectCatalog: appState.catalog,
            autotracker: appState.autotracker,
            descriptionRequired: appState.settings.descriptionRequired,
            deleteUndoManager: appState.deleteUndoManager
        )

        let hostingView = NSHostingController(rootView: timelineView)

        let window = NSWindow(contentViewController: hostingView)
        window.title = "Autotracker"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 900, height: 700))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        autotrackerWindow = window
        Self.logger.info("Autotracker window opened")
    }

    private static func parseDate(_ s: String) -> Date? {
        let parts = s.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return Calendar.current.date(from: comps)
    }

    // MARK: - Hotkey

    /// Register or re-register the global hotkey.
    /// When called with no arguments, reads from settings. With arguments, uses provided values.
    private func updateHotKey(keyCode: UInt32? = nil, modifiers: UInt32? = nil) {
        let combo: KeyCombo
        if let keyCode, let modifiers {
            combo = KeyCombo(carbonKeyCode: keyCode, carbonModifiers: modifiers)
        } else if appState.settings.hasCustomShortcut {
            combo = KeyCombo(carbonKeyCode: appState.settings.customShortcutKeyCode, carbonModifiers: appState.settings.customShortcutModifiers)
        } else {
            combo = KeyCombo(key: .m, modifiers: [.command, .control, .option])
        }

        hotKey = HotKey(keyCombo: combo)
        hotKey?.keyDownHandler = { [weak self] in
            MainActor.assumeIsolated {
                self?.panelController.toggle()
            }
        }
        Self.logger.info("Global hotkey registered: \(combo.description)")
    }

    /// Create a repeating background task that runs an action at a fixed interval.
    /// The first execution happens after the initial delay, not immediately.
    private func repeatingTask(
        every interval: Duration,
        action: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { break }
                await action()
            }
        }
    }
}

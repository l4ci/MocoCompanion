import AppKit
import SwiftUI
import os

/// Owns the NSStatusItem, popover, context menu, and timer state observation.
/// Display logic is computed by MenuBarDisplayState — this class just applies it to AppKit.
@MainActor
final class StatusItemController {
    private static let logger = Logger(category: "StatusItem")

    private let timerService: TimerService
    private let appState: AppState
    private let onShowPanel: () -> Void
    private let onNewTimer: () -> Void
    private let onShowSettings: () -> Void
    private let onShowAutotracker: () -> Void

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var statusMenu: NSMenu?
    private var elapsedTimerTask: Task<Void, Never>?

    init(timerService: TimerService, appState: AppState, onShowPanel: @escaping () -> Void, onNewTimer: @escaping () -> Void, onShowSettings: @escaping () -> Void, onShowAutotracker: @escaping () -> Void) {
        self.timerService = timerService
        self.appState = appState
        self.onShowPanel = onShowPanel
        self.onNewTimer = onNewTimer
        self.onShowSettings = onShowSettings
        self.onShowAutotracker = onShowAutotracker
    }

    func setup() {
        configureStatusItem()
        setupPopover()
        setupMenu()
        startObservingTimerState()
        startObservingAppearance()
        Self.logger.info("Status item created")
    }

    /// Verify the status item is functional; recreate if a menubar manager
    /// (e.g. Bartender) captured or hid it during startup.
    func verifyOrRecreate() {
        if statusItem?.button?.window != nil {
            Self.logger.debug("Status item health check passed")
            return
        }
        Self.logger.warning("Status item not visible — recreating")
        configureStatusItem()
    }

    private func configureStatusItem() {
        if let existing = statusItem {
            NSStatusBar.system.removeStatusItem(existing)
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.image = MenuBarIconRenderer.makeIconWithDot(
                symbolName: "timer",
                dotColor: .systemRed,
                isDarkMenubar: button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua,
                accessibilityDescription: "Moco Timer"
            )
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    func teardown() {
        elapsedTimerTask?.cancel()
        appearanceObservation?.invalidate()
        appearanceObservation = nil
    }

    // MARK: - Popover & Menu

    private func setupPopover() {
        let pop = NSPopover()
        pop.contentSize = NSSize(width: 340, height: 300)
        pop.behavior = .transient
        pop.animates = true
        pop.contentViewController = NSHostingController(
            rootView: StatusPopoverView(
                timerService: timerService,
                activityService: appState.activityService,
                yesterdayWarning: Binding(
                    get: { [weak appState] in appState?.yesterdayService.warning },
                    set: { [weak appState] in appState?.yesterdayService.warning = $0 }
                )
            )
        )
        popover = pop
    }

    private func setupMenu() {
        let menu = NSMenu()

        let newTimerItem = NSMenuItem(title: String(localized: "menu.newTimer"), action: #selector(menuNewTimer), keyEquivalent: "n")
        newTimerItem.target = self
        menu.addItem(newTimerItem)

        let openMocoItem = NSMenuItem(title: String(localized: "menu.openBrowser"), action: #selector(menuOpenBrowser), keyEquivalent: "o")
        openMocoItem.target = self
        menu.addItem(openMocoItem)

        let autotrackerItem = NSMenuItem(title: String(localized: "menu.timeline"), action: #selector(menuAutotracker), keyEquivalent: "t")
        autotrackerItem.target = self
        menu.addItem(autotrackerItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: String(localized: "menu.settings"), action: #selector(menuSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: String(localized: "menu.quit"), action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusMenu = menu
    }

    // MARK: - Click Handling

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            onShowPanel()
        }
    }

    private func showContextMenu() {
        guard let statusItem, let statusMenu else { return }
        statusItem.menu = statusMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Menu Actions

    @objc private func menuNewTimer() {
        onNewTimer()
    }

    @objc private func menuAutotracker() {
        onShowAutotracker()
    }

    @objc private func menuSettings() {
        onShowSettings()
    }

    @objc private func menuOpenBrowser() {
        let subdomain = appState.settings.subdomain
        guard !subdomain.isEmpty else { return }
        if let url = URL(string: "https://\(subdomain).mocoapp.com") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func menuQuit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Timer State Observation

    /// Cached icon name to avoid recreating NSImage when unchanged.
    private var lastIconName: String?
    /// Cached dot color to avoid re-compositing when unchanged.
    private var lastDotColor: NSColor?
    /// Cached appearance to detect light/dark transitions.
    private var lastIsDark: Bool?
    /// KVO observation for menubar appearance changes.
    private var appearanceObservation: NSKeyValueObservation?

    /// Cached label portion ("project · task") for the currently running
    /// timer, so the 1 s elapsed refresh loop doesn't re-run the emoji
    /// scalar scan and truncation every tick — the label is constant for
    /// the duration of a run. Cleared on state transitions.
    private var cachedRunningLabel: String?
    /// Key that the cachedRunningLabel was computed for. Identifies the
    /// running timer so we can detect when to invalidate.
    private var cachedRunningKey: String?

    private func startObservingTimerState() {
        // One-shot observation tracking: read the state, and have `onChange`
        // re-subscribe for the *next* mutation. No polling loop.
        observeDisplayStateOnce()
    }

    /// Read the current display state inside `withObservationTracking`,
    /// apply it to the NSStatusItem, and install a one-shot `onChange`
    /// callback that re-enters this method when any dependency mutates.
    /// This is the canonical Observation re-subscribe pattern.
    private func observeDisplayStateOnce() {
        let state = withObservationTracking {
            MenuBarDisplayState.from(
                timerState: timerService.timerState,
                currentActivity: timerService.currentActivity,
                hasError: timerService.lastError != nil
            )
        } onChange: { [weak self] in
            // onChange fires from an arbitrary thread; re-enter on main.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeDisplayStateOnce()
            }
        }
        applyDisplayState(state)
        updateElapsedTimer(for: timerService.timerState)
    }

    /// Apply a pure display state to the NSStatusItem. Caches the icon to avoid re-allocation.
    private func applyDisplayState(_ state: MenuBarDisplayState) {
        guard let button = statusItem?.button else { return }

        let isDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Recreate NSImage when icon name, dot color, or appearance changes
        if state.iconName != lastIconName || state.dotColor != lastDotColor || isDark != lastIsDark {
            button.image = MenuBarIconRenderer.makeIconWithDot(
                symbolName: state.iconName,
                dotColor: state.dotColor,
                isDarkMenubar: isDark,
                accessibilityDescription: state.accessibilityDescription
            )
            lastIconName = state.iconName
            lastDotColor = state.dotColor
            lastIsDark = isDark
        }
        button.title = state.title

        // Cache the running label so refreshElapsed() can avoid the emoji
        // scan + truncation on every tick.
        refreshRunningLabelCache()
    }

    /// Update `cachedRunningLabel` to match the current timer state. Called
    /// from `applyDisplayState` after each mutation so the elapsed-refresh
    /// loop always reads a current label.
    private func refreshRunningLabelCache() {
        guard case .running(_, let projectName) = timerService.timerState else {
            cachedRunningLabel = nil
            cachedRunningKey = nil
            return
        }
        let taskName = timerService.currentActivity?.taskName
        let key = "\(projectName)\u{1F}\(taskName ?? "")"
        if key != cachedRunningKey {
            cachedRunningLabel = MenuBarDisplayState.runningLabel(
                projectName: projectName,
                taskName: taskName
            )
            cachedRunningKey = key
        }
    }

    /// Observe system appearance changes and re-render the icon.
    private func startObservingAppearance() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Force re-render by clearing the cache
                self.lastIsDark = nil
                let state = MenuBarDisplayState.from(
                    timerState: self.timerService.timerState,
                    currentActivity: self.timerService.currentActivity,
                    hasError: self.timerService.lastError != nil
                )
                self.applyDisplayState(state)
            }
        }
    }

    private func updateElapsedTimer(for state: TimerState) {
        switch state {
        case .running:
            guard elapsedTimerTask == nil else { return }
            elapsedTimerTask = Task { [weak self] in
                while !Task.isCancelled {
                    // When the panel is hidden, the user isn't staring at a
                    // fresh HH:MM — 10s precision is plenty for the menu bar
                    // label. When visible, refresh every second.
                    let interval: Duration = PanelVisibility.shared.isVisible
                        ? .seconds(1)
                        : .seconds(10)
                    try? await Task.sleep(for: interval)
                    guard !Task.isCancelled else { break }
                    self?.refreshElapsed()
                }
            }
        case .idle, .paused:
            elapsedTimerTask?.cancel()
            elapsedTimerTask = nil
        }
    }

    private func refreshElapsed() {
        guard let button = statusItem?.button else { return }
        guard case .running = timerService.timerState else { return }

        // Fast path: if we have a cached label, skip the full
        // MenuBarDisplayState.from() rebuild (which re-scans the project
        // name for emoji). Just recompose with a fresh elapsed string.
        if let label = cachedRunningLabel {
            let elapsed = MenuBarDisplayState.elapsedString(from: timerService.currentActivity)
            button.title = MenuBarDisplayState.runningTitle(label: label, elapsed: elapsed)
            return
        }

        // Fallback — state arrived via refreshElapsed before applyDisplayState
        // could populate the cache. Compute the full state, which will
        // also populate the cache for subsequent ticks.
        let displayState = MenuBarDisplayState.from(
            timerState: timerService.timerState,
            currentActivity: timerService.currentActivity,
            hasError: timerService.lastError != nil
        )
        button.title = displayState.title
        refreshRunningLabelCache()
    }
}

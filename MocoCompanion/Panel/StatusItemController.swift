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

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var statusMenu: NSMenu?
    private var observationTask: Task<Void, Never>?
    private var elapsedTimerTask: Task<Void, Never>?

    init(timerService: TimerService, appState: AppState, onShowPanel: @escaping () -> Void, onNewTimer: @escaping () -> Void, onShowSettings: @escaping () -> Void) {
        self.timerService = timerService
        self.appState = appState
        self.onShowPanel = onShowPanel
        self.onNewTimer = onNewTimer
        self.onShowSettings = onShowSettings
    }

    func setup() {
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

        setupPopover()
        setupMenu()
        startObservingTimerState()
        startObservingAppearance()

        Self.logger.info("Status item created")
    }

    func teardown() {
        observationTask?.cancel()
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
                    get: { [weak appState] in appState?.yesterdayWarning },
                    set: { [weak appState] in appState?.yesterdayWarning = $0 }
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

    private func startObservingTimerState() {
        observationTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                // Read state inside withObservationTracking — captures dependencies.
                // When any tracked property changes, the continuation resumes.
                let displayState: MenuBarDisplayState = await withCheckedContinuation { continuation in
                    let state = withObservationTracking {
                        MenuBarDisplayState.from(
                            timerState: self.timerService.timerState,
                            currentActivity: self.timerService.currentActivity,
                            hasError: self.timerService.lastError != nil
                        )
                    } onChange: {
                        // This fires on the NEXT change — resume to apply it.
                        // We return the current state and re-enter the loop.
                    }
                    continuation.resume(returning: state)
                }

                guard !Task.isCancelled else { break }
                self.applyDisplayState(displayState)
                self.updateElapsedTimer(for: self.timerService.timerState)

                // Yield briefly to avoid tight-looping if onChange fires synchronously.
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
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
                    try? await Task.sleep(for: .seconds(1))
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
        guard case .running(_, let projectName) = timerService.timerState else { return }

        let displayState = MenuBarDisplayState.from(
            timerState: timerService.timerState,
            currentActivity: timerService.currentActivity,
            hasError: timerService.lastError != nil
        )
        button.title = displayState.title
    }
}

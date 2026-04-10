import AppKit
import SwiftUI
import os

/// NSHostingView subclass that resizes its parent window to match SwiftUI content.
/// Anchors the top edge so the panel grows downward (Spotlight-like).
/// Uses deferred, coalesced updates to avoid layout feedback loops.
final class WindowTrackingHostingView<Content: View>: NSHostingView<Content> {
    private var resizePending = false
    private var isUpdatingConstraints = false

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        scheduleWindowResize()
    }

    override func updateConstraints() {
        isUpdatingConstraints = true
        super.updateConstraints()
        isUpdatingConstraints = false
    }

    private func scheduleWindowResize() {
        guard !resizePending else { return }
        resizePending = true

        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else {
                self?.resizePending = false
                return
            }

            // If this fires during a constraint pass (possible on macOS 26+),
            // re-defer to avoid re-entrant setNeedsUpdateConstraints crash.
            if self.isUpdatingConstraints {
                self.resizePending = false
                self.scheduleWindowResize()
                return
            }

            self.resizePending = false

            let ideal = self.fittingSize
            let current = window.frame

            guard abs(current.height - ideal.height) > 0.5 else { return }

            // Anchor top edge: shift origin so top stays put
            let topY = current.origin.y + current.height
            let newFrame = NSRect(
                x: current.origin.x,
                y: topY - ideal.height,
                width: current.width,
                height: ideal.height
            )
            window.setFrame(newFrame, display: true, animate: false)
        }
    }
}

/// Manages the FloatingPanel lifecycle: create, position, show/hide.
/// Preserves SwiftUI state across focus-loss hide/show cycles.
/// Resets state only on explicit dismiss (Escape) or after the reset timeout.
@MainActor
final class PanelController {
    private static let logger = Logger(category: "Panel")

    private var panel: FloatingPanel?
    private(set) var isVisible = false
    var appState: AppState?

    /// Timer that resets panel state after hiding (default: 60s from settings).
    private var resetTask: Task<Void, Never>?

    private var panelWidth: CGFloat {
        appState?.settings.panelWidth ?? 520
    }

    /// Callback invoked when the panel should reset to its default tab.
    /// Set by the hosting view to reset @State from outside SwiftUI.
    var onResetState: (() -> Void)?

    /// Callback wired by AppDelegate so CMD+T from the panel opens the Autotracker window.
    var onShowAutotracker: (() -> Void)?

    /// Toggle the panel: show if hidden, hide if visible.
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Show the panel with fresh state (reset to default tab).
    /// Used by "New Timer" menu action and other entry points that shouldn't
    /// restore a previous session.
    func showFresh() {
        resetTask?.cancel()
        resetTask = nil

        if let existing = panel {
            // Force a fresh hosting view regardless of dismissedExplicitly
            installHostingView(makePanelContentView(), in: existing)
            existing.dismissedExplicitly = false
        }

        show()
    }

    func show() {
        guard let panel = getOrCreatePanel() else { return }

        // Cancel any pending state reset — user came back in time
        resetTask?.cancel()
        resetTask = nil

        // If the panel was programmatically closed (success auto-close, Escape),
        // reset to fresh state. The dismissedExplicitly flag is set by close().
        if panel.dismissedExplicitly {
            installHostingView(makePanelContentView(), in: panel)
            panel.dismissedExplicitly = false
        }

        // Sync NSPanel appearance with the user's color scheme setting
        // so the AppKit layer matches the SwiftUI preferredColorScheme.
        updatePanelAppearance(panel)

        positionPanel(panel)

        // Hide cursor until the user moves the mouse — prevents hover conflicts
        // with keyboard navigation when the panel opens under the cursor.
        NSCursor.setHiddenUntilMouseMoves(true)

        panel.makeKeyAndOrderFront(nil)

        // Bring our app to the front just enough to make the panel key,
        // without showing a dock icon (LSUIElement handles that).
        NSApp.activate(ignoringOtherApps: true)

        isVisible = true
        Self.logger.debug("Panel shown")
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
        scheduleStateReset()
        Self.logger.debug("Panel hidden")
    }

    // MARK: - State Reset

    /// Schedule a state reset after the configured timeout.
    private func scheduleStateReset() {
        resetTask?.cancel()
        let seconds = appState?.settings.panelResetSeconds ?? 60
        guard seconds > 0 else { return }

        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.resetPanelState()
        }
    }

    /// Reset the panel to default state (recreate the hosting view).
    private func resetPanelState() {
        guard let panel, let appState else { return }
        installHostingView(makePanelContentView(), in: panel)
        Self.logger.info("Panel state reset after timeout")
    }

    // MARK: - Private

    private func getOrCreatePanel() -> FloatingPanel? {
        guard let appState else {
            Self.logger.error("PanelController.appState must be set before showing the panel")
            return nil
        }

        if let existing = panel {
            return existing
        }

        let newPanel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 52)
        )
        installHostingView(makePanelContentView(), in: newPanel)

        // Focus loss (click outside, app switch) — hide but preserve state
        newPanel.onFocusLost = { [weak self] in
            MainActor.assumeIsolated {
                self?.isVisible = false
                self?.scheduleStateReset()
            }
        }

        // When the panel closes explicitly (Escape), update our state
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newPanel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isVisible = false
                self?.scheduleStateReset()
            }
        }

        // Save position when panel is moved by the user
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: newPanel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                self.appState?.settings.savePanelPosition(panel.frame.origin)
            }
        }

        panel = newPanel
        return newPanel
    }

    private func installHostingView(_ view: PanelContentView?, in panel: FloatingPanel) {
        guard let view else { return }
        let hostingView = WindowTrackingHostingView(rootView: view)
        hostingView.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hostingView
    }

    private func makePanelContentView() -> PanelContentView? {
        guard let appState else { return nil }
        return PanelContentView(
            appState: appState,
            favoritesManager: appState.favoritesManager,
            onShowAutotracker: onShowAutotracker
        )
    }

    /// Sync the NSPanel's AppKit appearance with the user's appearance setting.
    /// Without this, NSHostingView inherits the system appearance, making
    /// `.preferredColorScheme(.dark)` ineffective for the window chrome and
    /// underlying AppKit rendering context.
    private func updatePanelAppearance(_ panel: FloatingPanel) {
        guard let setting = appState?.settings.appearance else { return }
        switch setting {
        case "dark":
            panel.appearance = NSAppearance(named: .darkAqua)
        case "light":
            panel.appearance = NSAppearance(named: .aqua)
        default:
            panel.appearance = nil  // follow system
        }
    }

    private func positionPanel(_ panel: FloatingPanel) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        if let settings = appState?.settings, settings.hasSavedPanelPosition {
            // Use saved position, but clamp to visible screen
            let x = max(screenFrame.minX, min(screenFrame.maxX - panelWidth, settings.panelPositionX))
            let y = max(screenFrame.minY, min(screenFrame.maxY - 52, settings.panelPositionY))
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            // Default: centered horizontally, ~30% from top (Spotlight-like)
            let x = screenFrame.midX - panelWidth / 2
            let y = screenFrame.maxY - screenFrame.height * 0.3
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}

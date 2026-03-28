import AppKit
import SwiftUI

/// A floating NSPanel subclass that behaves like Spotlight:
/// - Floats above all windows
/// - Captures keyboard focus
/// - Dismisses on Escape or click-outside
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Panel behavior
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow

        // Don't hide when the app isn't "active" — we're a menubar app
        // triggered by global hotkey from any app context
        hidesOnDeactivate = false

        // Visual
        isOpaque = false
        backgroundColor = .clear
    }

    /// Whether the panel was explicitly dismissed (Escape) vs just lost focus.
    var dismissedExplicitly = false

    /// Guard to prevent resignKey from overriding close() state.
    private var isClosing = false

    /// Called when the panel loses focus (resignKey) without explicit close.
    var onFocusLost: (() -> Void)?

    // MARK: - Key window support

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func resignKey() {
        super.resignKey()
        // Skip if we're inside close() — close handles its own state
        guard !isClosing else { return }
        // Focus lost (click outside, app switch) — just hide, preserve state
        dismissedExplicitly = false
        orderOut(nil)
        onFocusLost?()
    }

    override func close() {
        // Explicit close (Escape, programmatic) — mark for state reset
        isClosing = true
        dismissedExplicitly = true
        super.close()
        orderOut(nil)
        isClosing = false
    }

    override func keyDown(with event: NSEvent) {
        // Escape key dismisses explicitly
        if event.keyCode == 53 {
            close()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

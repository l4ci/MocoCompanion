import AppKit
import ApplicationServices
import Foundation
import os

/// Thin wrapper around the Accessibility trust APIs plus the
/// focused-window-title fetching helper. Kept separate from Autotracker
/// so the permission check is one line at call sites.
///
/// The Accessibility permission is system-level (System Settings →
/// Privacy & Security → Accessibility) and not an app entitlement —
/// nothing needs to be declared in Info.plist. When the user has not
/// granted access, `focusedWindowTitle(forProcess:)` returns nil and
/// callers treat that as "no title available".
@MainActor
enum AccessibilityPermission {
    private static let logger = Logger(category: "AccessibilityPermission")

    /// Current trust state. Returns false if the user has not granted
    /// access in System Settings → Privacy & Security → Accessibility.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user via the system dialog if trust hasn't been
    /// established yet. Returns the new trust state (usually unchanged
    /// until the user manually toggles the switch in System Settings
    /// and the app receives the AX change notification). Harmless to
    /// call when already trusted.
    @discardableResult
    static func requestAccess() -> Bool {
        // Using the string literal instead of kAXTrustedCheckOptionPrompt
        // because referencing the extern CFStringRef from a nonisolated
        // context trips Swift 6's strict concurrency check. The value is
        // stable and documented as "AXTrustedCheckOptionPrompt".
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Returns the focused window title of the given process if
    /// Accessibility access is granted and the process exposes a
    /// focused window. Nil in all other cases — callers treat nil
    /// as "no title available, don't include in the record".
    ///
    /// Declared `nonisolated` so the call can be made from a background
    /// task: the underlying AX reads can block for 50–200 ms against a
    /// slow app (Xcode, Chrome), and blocking the main actor on every
    /// app switch janks the panel UI. Callers wrap this in a time-boxed
    /// task via `capturefocusedWindowTitle(forProcess:budget:)`.
    nonisolated static func focusedWindowTitle(forProcess pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var focusedRef: CFTypeRef?
        let focusStatus = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusedRef)
        guard focusStatus == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        let axWindow = focusedRef as! AXUIElement

        var titleRef: CFTypeRef?
        let titleStatus = AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
        guard titleStatus == .success, let title = titleRef as? String else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Fetch the focused window title off the main actor with a hard
    /// time budget. If the AX call doesn't return within `budget`, this
    /// returns nil and the AX call continues in the background (harmless).
    /// Use this everywhere user-visible latency matters — i.e. every
    /// `NSWorkspace.didActivateApplicationNotification` handler.
    nonisolated static func capturefocusedWindowTitle(
        forProcess pid: pid_t,
        budget: Duration = .milliseconds(30)
    ) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask(priority: .userInitiated) {
                Self.focusedWindowTitle(forProcess: pid)
            }
            group.addTask {
                try? await Task.sleep(for: budget)
                return nil
            }
            defer { group.cancelAll() }
            return await group.next() ?? nil
        }
    }
}

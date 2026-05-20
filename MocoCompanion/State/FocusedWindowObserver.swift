import AppKit
@preconcurrency import ApplicationServices
import Foundation
import os

/// Wraps an AXObserver registered for `kAXFocusedWindowChangedNotification`
/// on a single application process. When the user moves focus between
/// windows inside that app — a Chrome tab change, an Outlook email opening,
/// an Xcode document switch — the AX server posts the notification on the
/// main run loop and `onChange` fires. Callers re-read the focused window
/// title in response.
///
/// One instance per frontmost PID. NSWorkspaceMonitor tears down the old
/// observer and creates a new one on every app activation; tearing down
/// the wrapper removes the run loop source so callbacks stop firing.
///
/// Title-change notifications (`kAXTitleChangedNotification`) are
/// deliberately *not* subscribed to — sites like Gmail and Slack flicker
/// their tab title with unread counters, which would create spurious
/// segments without representing a real attention shift.
@MainActor
final class FocusedWindowObserver {
    private static let logger = Logger(category: "FocusedWindowObserver")

    private let pid: pid_t
    private let onChange: @MainActor () -> Void
    private var observer: AXObserver?

    init?(pid: pid_t, onChange: @escaping @MainActor () -> Void) {
        self.pid = pid
        self.onChange = onChange

        guard AXIsProcessTrusted() else { return nil }

        var observerRef: AXObserver?
        let createStatus = AXObserverCreate(pid, Self.callback, &observerRef)
        guard createStatus == .success, let observerRef else {
            Self.logger.debug("AXObserverCreate failed for pid \(pid, privacy: .public) status=\(createStatus.rawValue, privacy: .public)")
            return nil
        }

        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let addStatus = AXObserverAddNotification(
            observerRef,
            app,
            kAXFocusedWindowChangedNotification as CFString,
            refcon
        )
        guard addStatus == .success else {
            Self.logger.debug("AXObserverAddNotification failed for pid \(pid, privacy: .public) status=\(addStatus.rawValue, privacy: .public)")
            return nil
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observerRef),
            .defaultMode
        )
        self.observer = observerRef
    }

    deinit {
        guard let observer else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
    }

    // C callback bridges to MainActor — the run loop source was added to
    // the main run loop, so we know we're on the main thread at fire time.
    private static let callback: AXObserverCallback = { _, _, _, refcon in
        guard let refcon else { return }
        let wrapper = Unmanaged<FocusedWindowObserver>.fromOpaque(refcon).takeUnretainedValue()
        MainActor.assumeIsolated {
            wrapper.onChange()
        }
    }
}

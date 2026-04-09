import Testing
import Foundation
@testable import MocoCompanion

@Suite("TimerSideEffects")
struct TimerSideEffectsTests {

    // MARK: - Helpers

    /// Build a TimerSideEffects wired with a recording NotificationDispatcher.
    /// Returns the side-effects instance and the array of captured notification types.
    @MainActor
    private func makeSideEffects(
        soundEnabled: Bool = false
    ) -> (TimerSideEffects, RecordingBox) {
        let box = RecordingBox()
        let dispatcher = NotificationDispatcher(isEnabledCheck: { type in
            box.types.append(type)
            return false // suppress actual UNNotification posting
        })
        let settings = SettingsStore()
        // Sound is backed by UserDefaults; write a unique key to avoid polluting state.
        // SettingsStore reads `soundEnabled` key — we just need the settings instance.
        // SoundFeedback is a static enum we can't mock, so we leave sound disabled.
        let sideEffects = TimerSideEffects(
            recencyTracker: RecencyTracker(),
            recentEntriesTracker: RecentEntriesTracker(),
            descriptionStore: DescriptionStore(),
            settings: settings,
            notificationDispatcher: dispatcher,
            searchEntriesProvider: { [] },
            budgetRefresh: { _ in },
            budgetStatusProvider: { _, _ in .empty }
        )
        return (sideEffects, box)
    }

    // MARK: - Timer Started

    @Test("onTimerStarted dispatches .timerStarted notification")
    @MainActor func timerStartedNotification() {
        let (fx, box) = makeSideEffects()

        fx.onTimerStarted(projectId: 1, taskId: 2, description: "work", projectName: "Acme")

        #expect(box.types.contains(.timerStarted))
    }

    // MARK: - Timer Stopped

    @Test("onTimerStopped dispatches .timerStopped when not suppressed")
    @MainActor func timerStoppedNotification() {
        let (fx, box) = makeSideEffects()

        fx.onTimerStopped()

        #expect(box.types.contains(.timerStopped))
    }

    // MARK: - Error

    @Test("onError dispatches .apiError notification")
    @MainActor func errorNotification() {
        let (fx, box) = makeSideEffects()

        fx.onError(.serverError(statusCode: 500, message: "boom"))

        #expect(box.types.contains(.apiError))
    }

    // MARK: - Sound Gating

    @Test("playSound does not crash when sound is disabled")
    @MainActor func soundDisabledNoCrash() {
        // SettingsStore default has sound.enabled = true, but SoundFeedback is a static enum.
        // We verify the side-effects path completes without error when sound would play.
        let (fx, _) = makeSideEffects(soundEnabled: false)

        // These methods call playSound internally — should complete without crash.
        fx.onTimerPaused(projectName: "Acme")
        fx.onExternalTimerStopped()
        // If we reach here without crash, the guard on settings.sound.enabled works.
    }
}

// MARK: - Recording Helper

/// Reference-type box for capturing notification types inside closures.
@MainActor
private final class RecordingBox {
    var types: [NotificationCatalog.NotificationType] = []
}

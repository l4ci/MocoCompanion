import Testing
import Foundation
@testable import MocoCompanion

/// Covers the AX window-title result-ordering fix in `NSWorkspaceMonitor`.
/// Each activation spawns an off-main AX title read; on rapid app
/// switching a slow read for an earlier activation could previously
/// resolve *after* a faster later one and overwrite it with stale
/// app/title data. `activationGeneration` guards against this — a result
/// is only reported to `handler` if no newer activation has started an AX
/// read in the meantime.
@MainActor
@Suite("NSWorkspaceMonitorTitleOrdering")
struct NSWorkspaceMonitorTests {

    /// Polls `condition` until it's true or `timeout` elapses. Used instead
    /// of a fixed `Task.sleep` so the test stays correct (rather than
    /// flaky) when the Swift concurrency thread pool is under heavy
    /// contention from the rest of a large parallel test run.
    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline { return }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func slowerEarlierActivationResultIsDroppedInFavorOfFasterLaterOne() async throws {
        let monitor = NSWorkspaceMonitor()
        var received: [(bundleId: String, appName: String, title: String?)] = []
        monitor.handler = { event in
            if case .appActivated(let bundleId, let appName, let title) = event {
                received.append((bundleId, appName, title))
            }
        }

        // First activation: a slow AX resolution (simulates a laggy AX read
        // for the app the user has already switched away from).
        monitor.titleResolver = { _ in
            try? await Task.sleep(for: .milliseconds(120))
            return "Stale Title"
        }
        monitor._testBeginTitleResolution(pid: 111, bundleId: "com.app.A", appName: "AppA")

        // Second activation arrives quickly after, with a fast resolver —
        // this is the app the user is actually looking at now.
        monitor.titleResolver = { _ in "Fresh Title" }
        monitor._testBeginTitleResolution(pid: 222, bundleId: "com.app.B", appName: "AppB")

        // Wait for the fast (second) activation to report...
        try await waitUntil { !received.isEmpty }
        // ...then wait past the slow resolver's delay too, so the guard has
        // had a chance to (correctly) drop its late, stale result.
        try await Task.sleep(for: .milliseconds(200))

        // Only the latest activation's result should have reached the
        // handler — the slower, earlier one must be dropped rather than
        // overwriting it.
        #expect(received.count == 1)
        #expect(received.first?.bundleId == "com.app.B")
        #expect(received.first?.appName == "AppB")
        #expect(received.first?.title == "Fresh Title")
    }

    @Test func nonOverlappingActivationsBothReportInOrder() async throws {
        let monitor = NSWorkspaceMonitor()
        var received: [String] = []
        monitor.handler = { event in
            if case .appActivated(let bundleId, _, _) = event {
                received.append(bundleId)
            }
        }

        monitor.titleResolver = { _ in "Title" }
        monitor._testBeginTitleResolution(pid: 1, bundleId: "com.app.A", appName: "AppA")
        try await waitUntil { received.count == 1 }

        monitor._testBeginTitleResolution(pid: 2, bundleId: "com.app.B", appName: "AppB")
        try await waitUntil { received.count == 2 }

        // When resolutions don't overlap, both activations report normally.
        #expect(received == ["com.app.A", "com.app.B"])
    }
}

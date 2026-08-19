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

        // Signaled by the slow resolver once it has actually produced its
        // (stale) result, so the test can wait for that exact moment instead
        // of guessing a wall-clock margin that has to outrun the resolver's
        // own delay — flaky under a large parallel test run's contention.
        var slowResolverSignalContinuation: AsyncStream<Void>.Continuation!
        let slowResolverDone = AsyncStream<Void> { slowResolverSignalContinuation = $0 }
        let slowResolverSignal = slowResolverSignalContinuation!

        // First activation: a slow AX resolution (simulates a laggy AX read
        // for the app the user has already switched away from).
        monitor.titleResolver = { _ in
            try? await Task.sleep(for: .milliseconds(120))
            slowResolverSignal.yield(())
            return "Stale Title"
        }
        monitor._testBeginTitleResolution(pid: 111, bundleId: "com.app.A", appName: "AppA")

        // Second activation arrives quickly after, with a fast resolver —
        // this is the app the user is actually looking at now.
        monitor.titleResolver = { _ in "Fresh Title" }
        monitor._testBeginTitleResolution(pid: 222, bundleId: "com.app.B", appName: "AppB")

        // Wait for the fast (second) activation to report...
        try await waitUntil { !received.isEmpty }
        // ...then wait for the slow resolver to have actually completed...
        var slowIterator = slowResolverDone.makeAsyncIterator()
        _ = await slowIterator.next()
        // ...and yield a handful of times so the guard's own MainActor hop
        // (queued immediately after the resolver returns) gets a chance to
        // run and (correctly) drop the stale result before we assert.
        for _ in 0..<50 { await Task.yield() }

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

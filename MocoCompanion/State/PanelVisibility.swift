import Foundation

/// Central panel-visibility publisher.
///
/// Services that poll, refresh, or otherwise wake on a timer listen to
/// `changes` (or read `isVisible` inside observation-tracked closures) and
/// pause work when the panel is hidden. Keeps the menu-bar utility
/// near-zero when the user isn't looking at it.
///
/// There is only ever one panel, so this is exposed as `shared`, but the
/// `init()` is internal to allow tests to construct their own instance.
@Observable
@MainActor
final class PanelVisibility {
    static let shared = PanelVisibility()

    private(set) var isVisible: Bool = false

    private var nextContinuationId: UInt64 = 0
    private var continuations: [UInt64: AsyncStream<Bool>.Continuation] = [:]

    init() {}

    /// Publish a new visibility state. No-op if the state is unchanged so
    /// subscribers don't see spurious transitions.
    func set(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        for cont in continuations.values {
            cont.yield(visible)
        }
    }

    /// Async stream of visibility changes. The stream yields the current
    /// value immediately on subscription so consumers can make an initial
    /// decision without racing the first change.
    var changes: AsyncStream<Bool> {
        AsyncStream { continuation in
            Task { @MainActor in
                let id = self.nextContinuationId
                self.nextContinuationId &+= 1
                self.continuations[id] = continuation
                // Send current value so subscribers don't have to wait for
                // the next change to know where they started.
                continuation.yield(self.isVisible)
                continuation.onTermination = { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.continuations.removeValue(forKey: id)
                    }
                }
            }
        }
    }
}

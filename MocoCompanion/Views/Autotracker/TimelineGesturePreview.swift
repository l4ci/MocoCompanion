import Foundation

/// State machine for an in-progress gesture-driven preview of a
/// timeline entry mutation — either a drag-to-move or a drag-to-resize.
/// Owned by `TimelineViewModel` and updated during pan gestures.
///
/// Transitions:
///   .idle → begin(…) → .active → update(…) → .active → clear() → .idle
///
/// The invariant that preview fields must be consistent when the phase
/// is `.active` is enforced by the `ActiveState` constructor and the
/// `begin` method. `clear()` atomically returns to `.idle`.
struct TimelineGesturePreview: Equatable, Sendable {

    // MARK: - Nested Types

    struct ActiveState: Equatable, Sendable {
        let entryKey: String
        var startMinutes: Int
        var durationMinutes: Int
        let columnIndex: Int
        let columnCount: Int

        /// Human-friendly duration label for the ghost block, e.g. "1h 30min".
        var durationLabel: String {
            let h = durationMinutes / 60
            let m = durationMinutes % 60
            if h > 0 && m > 0 { return "\(h)h \(m)min" }
            if h > 0 { return "\(h)h" }
            return "\(m)min"
        }
    }

    enum Phase: Equatable, Sendable {
        case idle
        case active(ActiveState)
    }

    // MARK: - State

    private(set) var phase: Phase = .idle

    /// Convenience accessor — `nil` when idle, the active state otherwise.
    var activeState: ActiveState? {
        if case .active(let s) = phase { return s }
        return nil
    }

    // MARK: - Transitions

    /// Begin a new preview. Replaces any existing active preview.
    mutating func begin(
        entryKey: String,
        startMinutes: Int,
        durationMinutes: Int,
        columnIndex: Int,
        columnCount: Int
    ) {
        phase = .active(ActiveState(
            entryKey: entryKey,
            startMinutes: startMinutes,
            durationMinutes: durationMinutes,
            columnIndex: columnIndex,
            columnCount: columnCount
        ))
    }

    /// Update the time window of the active preview. No-ops when idle.
    mutating func update(startMinutes: Int, durationMinutes: Int) {
        guard case .active(var state) = phase else { return }
        state.startMinutes = startMinutes
        state.durationMinutes = durationMinutes
        phase = .active(state)
    }

    /// Return to idle, discarding the preview.
    mutating func clear() {
        phase = .idle
    }
}

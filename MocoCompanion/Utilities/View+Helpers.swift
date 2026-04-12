import SwiftUI

// MARK: - Accessible Animation

/// Perform an animated state change that respects `accessibilityReduceMotion`.
/// Use instead of `withAnimation(reduceMotion ? .none : .easeInOut(duration: Theme.Motion.standard)) { ... }`.
func animateAccessibly(
    _ reduceMotion: Bool,
    _ animation: Animation = .easeInOut(duration: Theme.Motion.standard),
    _ body: () -> Void
) {
    withAnimation(reduceMotion ? .none : animation, body)
}

// MARK: - Delayed Focus

extension View {
    /// Schedule a focus change after a brief delay, working around SwiftUI's
    /// timing issues with focus assignment during view transitions.
    func setFocusAfterDelay<F: Hashable>(_ binding: FocusState<F?>.Binding, to value: F) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            binding.wrappedValue = value
        }
    }

    /// Schedule a boolean focus change after a brief delay.
    func setFocusAfterDelay(_ binding: FocusState<Bool>.Binding, to value: Bool = true) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            binding.wrappedValue = value
        }
    }
}

// MARK: - Accessible Animation Modifier

extension View {
    /// Apply `.animation()` that respects reduce-motion preference.
    func accessibleAnimation<V: Equatable>(
        _ reduceMotion: Bool,
        _ animation: Animation = .easeInOut(duration: Theme.Motion.standard),
        value: V
    ) -> some View {
        self.animation(reduceMotion ? .none : animation, value: value)
    }
}

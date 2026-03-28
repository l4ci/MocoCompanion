import Foundation

/// Thread-safe mutable value holder for sharing state between closures.
/// Replaces the weakSelf pattern in AppState.init — services capture the box
/// (stable lifetime), and AppState pushes updates through the value property.
@MainActor
final class ValueBox<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

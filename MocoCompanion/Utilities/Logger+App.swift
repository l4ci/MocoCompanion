import os

extension Logger {
    /// App-wide subsystem identifier.
    private static let appSubsystem = "com.mococompanion.app"

    /// Create a Logger with the app subsystem and the given category.
    init(category: String) {
        self.init(subsystem: Self.appSubsystem, category: category)
    }
}

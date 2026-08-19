import Foundation

extension ProcessInfo {
    /// True when the process is hosting an XCTest/Swift Testing run.
    ///
    /// The unit-test bundle is injected into the real app, so app code that
    /// would otherwise touch the user's Keychain, UserDefaults, or network
    /// checks this to stay out of the way.
    var isRunningTests: Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}

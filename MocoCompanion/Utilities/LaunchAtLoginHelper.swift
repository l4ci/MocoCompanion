import ServiceManagement
import os

/// Encapsulates SMAppService registration for launch-at-login.
enum LaunchAtLoginHelper {
    private static let logger = Logger(category: "LaunchAtLogin")

    static func update(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                logger.info("Registered launch at login")
            } else {
                try SMAppService.mainApp.unregister()
                logger.info("Unregistered launch at login")
            }
        } catch {
            logger.error("Launch at login update failed: \(error.localizedDescription)")
        }
    }
}

import SwiftUI

/// Debug settings tab: log levels, file management.
struct DebugSettingsTab: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "debug.apiLogLevel"), selection: $settings.apiLogLevel) {
                    ForEach(AppLogger.LogLevel.allCases, id: \.self) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Button(String(localized: "debug.openLog")) {
                        Task {
                            let path = await AppLogger.shared.apiLogPath
                            NSWorkspace.shared.open(path)
                        }
                    }
                    Button(String(localized: "debug.revealInFinder")) {
                        Task {
                            let path = await AppLogger.shared.apiLogPath
                            NSWorkspace.shared.activateFileViewerSelecting([path])
                        }
                    }
                    Spacer()
                    Button(String(localized: "debug.clear")) {
                        Task { await AppLogger.shared.clearLog(.api) }
                    }
                    .foregroundStyle(.red)
                }
            } header: {
                Text(String(localized: "debug.apiLog"))
            } footer: {
                Text(String(localized: "debug.apiLogDesc"))
            }

            Section {
                Picker(String(localized: "debug.appLogLevel"), selection: $settings.appLogLevel) {
                    ForEach(AppLogger.LogLevel.allCases, id: \.self) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Button(String(localized: "debug.openAppLog")) {
                        Task {
                            let path = await AppLogger.shared.appLogPath
                            NSWorkspace.shared.open(path)
                        }
                    }
                    Button(String(localized: "debug.revealInFinder")) {
                        Task {
                            let path = await AppLogger.shared.appLogPath
                            NSWorkspace.shared.activateFileViewerSelecting([path])
                        }
                    }
                    Spacer()
                    Button(String(localized: "debug.clear")) {
                        Task { await AppLogger.shared.clearLog(.app) }
                    }
                    .foregroundStyle(.red)
                }
            } header: {
                Text(String(localized: "debug.appLog"))
            } footer: {
                Text(String(localized: "debug.appLogDesc"))
            }

            Section {
                HStack {
                    Text(String(localized: "debug.logDir"))
                    Spacer()
                    Button(String(localized: "debug.open")) {
                        Task {
                            let dir = await AppLogger.shared.apiLogPath.deletingLastPathComponent()
                            NSWorkspace.shared.open(dir)
                        }
                    }
                }
            } header: {
                Text(String(localized: "debug.storage"))
            } footer: {
                Text(String(localized: "debug.rotationNote"))
            }
        }
        .formStyle(.grouped)
    }
}

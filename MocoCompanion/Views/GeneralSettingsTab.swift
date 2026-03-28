import SwiftUI

/// General settings tab: startup, working hours, sound, appearance, favorites.
struct GeneralSettingsTab: View {
    @Bindable var settings: SettingsStore
    var appState: AppState?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { newValue in
                        settings.launchAtLogin = newValue
                        LaunchAtLoginHelper.update(newValue)
                    }
                ))

                Picker("Default Tab", selection: $settings.defaultTab) {
                    Text("Track").tag("search")
                    Text("Log").tag("today")
                }

                Button(String(localized: "settings.resetPosition")) {
                    settings.resetPanelPosition()
                }
                .disabled(!settings.hasSavedPanelPosition)

                Picker(String(localized: "settings.panelReset"), selection: $settings.panelResetSeconds) {
                    Text(String(localized: "settings.panelReset.30s")).tag(30)
                    Text(String(localized: "settings.panelReset.60s")).tag(60)
                    Text(String(localized: "settings.panelReset.120s")).tag(120)
                    Text(String(localized: "settings.panelReset.300s")).tag(300)
                    Text(String(localized: "settings.panelReset.never")).tag(0)
                }
            } header: {
                Text(String(localized: "settings.startup"))
            }

            Section {
                Picker("Start", selection: $settings.workingHoursStart) {
                    ForEach(5..<13, id: \.self) { hour in
                        Text(formatHour(hour)).tag(hour)
                    }
                }

                Picker("End", selection: $settings.workingHoursEnd) {
                    ForEach(14..<23, id: \.self) { hour in
                        Text(formatHour(hour)).tag(hour)
                    }
                }
            } header: {
                Text(String(localized: "settings.workingHours"))
            } footer: {
                Text(String(localized: "settings.workingHoursFooter"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Sound Effects", isOn: $settings.soundEnabled)
            } header: {
                Text(String(localized: "settings.sound"))
            }

            Section {
                Picker("Appearance", selection: $settings.appearance) {
                    Text("Auto").tag("auto")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(String(localized: "settings.entryFontSize"))
                        Spacer()
                        Text(fontSizeLabel)
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    Slider(
                        value: Binding(
                            get: { Double(settings.entryFontSizeBoost) },
                            set: { settings.entryFontSizeBoost = Int($0.rounded()) }
                        ),
                        in: 0...3,
                        step: 1
                    ) {
                        Text(String(localized: "settings.entryFontSize"))
                    } minimumValueLabel: {
                        Text("A")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("A")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Autocomplete Descriptions", isOn: $settings.autoCompleteEnabled)
            } header: {
                Text(String(localized: "settings.display"))
            }
        }
        .formStyle(.grouped)
    }

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Label showing the effective base font size (15pt baseline + boost).
    private var fontSizeLabel: String {
        let effective = 15 + settings.entryFontSizeBoost
        return "\(effective)pt"
    }

    private func formatHour(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        if let date = Calendar.current.date(from: components) {
            return Self.hourFormatter.string(from: date)
        }
        return "\(hour):00"
    }
}

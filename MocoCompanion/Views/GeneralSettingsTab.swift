import SwiftUI

/// General settings tab: startup, working hours, sound, appearance, favorites.
struct GeneralSettingsTab: View {
    @Bindable var settings: SettingsStore
    var appState: AppState?

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "settings.launchAtLogin"), isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, newValue in
                        LaunchAtLoginHelper.update(newValue)
                    }

                Picker(String(localized: "settings.defaultTab"), selection: $settings.defaultTab) {
                    Text(String(localized: "settings.defaultTab.search")).tag(DefaultTab.search)
                    Text(String(localized: "settings.defaultTab.today")).tag(DefaultTab.today)
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
                Picker(String(localized: "settings.start"), selection: $settings.workingHoursStart) {
                    ForEach(5..<13, id: \.self) { hour in
                        Text(formatHour(hour)).tag(hour)
                    }
                }

                Picker(String(localized: "settings.end"), selection: $settings.workingHoursEnd) {
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
                Toggle(String(localized: "settings.soundEffects"), isOn: $settings.soundEnabled)
            } header: {
                Text(String(localized: "settings.sound"))
            }

            Section {
                Picker(String(localized: "settings.language"), selection: $settings.appLanguage) {
                    Text(String(localized: "settings.language.system")).tag("system")
                    Text("English").tag("en")
                    Text("Deutsch").tag("de")
                }

                Picker(String(localized: "settings.appearance"), selection: $settings.appearance) {
                    Text(String(localized: "settings.appearance.auto")).tag("auto")
                    Text(String(localized: "settings.appearance.light")).tag("light")
                    Text(String(localized: "settings.appearance.dark")).tag("dark")
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

                Toggle(String(localized: "settings.autocomplete"), isOn: $settings.autoCompleteEnabled)
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

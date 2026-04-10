import SwiftUI

/// Settings tab for the Autotracker feature: toggle recording, view status, configure retention.
struct AutotrackerSettingsTab: View {
    @Bindable var settings: SettingsStore
    var autotracker: Autotracker?
    var projectCatalog: ProjectCatalog?

    @Environment(\.theme) private var theme
    @State private var newExcludedBundleId = ""
    @State private var showRuleList = false
    @State private var ruleCount: Int = 0

    private let retentionOptions = [7, 14, 30]

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "autotracker.enable"), isOn: $settings.autotrackerEnabled)
                    .onChange(of: settings.autotrackerEnabled) { _, enabled in
                        if enabled {
                            autotracker?.start()
                        } else {
                            autotracker?.stop()
                        }
                    }
            }

            if settings.autotrackerEnabled {
                Section(String(localized: "autotracker.status")) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(autotracker?.isRecording == true ? .green : .secondary)
                            .frame(width: 8, height: 8)

                        Text(autotracker?.isRecording == true
                             ? String(localized: "autotracker.recording")
                             : String(localized: "autotracker.stopped"))
                            .font(.system(size: Theme.FontSize.body))
                    }

                    HStack {
                        Text(String(localized: "autotracker.recordCount"))
                            .font(.system(size: Theme.FontSize.body))
                        Spacer()
                        Text("\(autotracker?.recordCount ?? 0)")
                            .font(.system(size: Theme.FontSize.body).monospacedDigit())
                            .foregroundStyle(theme.textSecondary)
                    }

                    if let name = autotracker?.currentAppName, autotracker?.isRecording == true {
                        HStack {
                            Text(String(localized: "autotracker.currentApp"))
                                .font(.system(size: Theme.FontSize.body))
                            Spacer()
                            Text(name)
                                .font(.system(size: Theme.FontSize.body))
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                }

                Section(String(localized: "autotracker.excludedApps")) {
                    ForEach(settings.autotrackerExcludedApps, id: \.self) { bundleId in
                        HStack {
                            Text(bundleId)
                                .font(.system(size: Theme.FontSize.body))
                            Spacer()
                            Button {
                                settings.removeExcludedApp(bundleId)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 8) {
                        TextField(String(localized: "autotracker.excludedApps.placeholder"), text: $newExcludedBundleId)
                            .font(.system(size: Theme.FontSize.body))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addExcludedApp() }
                        Button(String(localized: "autotracker.excludedApps.add")) {
                            addExcludedApp()
                        }
                        .disabled(newExcludedBundleId.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }

            if settings.autotrackerEnabled, autotracker != nil, projectCatalog != nil {
                Section("Rules") {
                    Button {
                        showRuleList = true
                    } label: {
                        HStack {
                            Text("Manage Rules")
                                .font(.system(size: Theme.FontSize.body))
                            Spacer()
                            Text("\(ruleCount)")
                                .font(.system(size: Theme.FontSize.body).monospacedDigit())
                                .foregroundStyle(theme.textTertiary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: Theme.FontSize.caption))
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section(String(localized: "autotracker.data")) {
                Picker(String(localized: "autotracker.retention"), selection: $settings.autotrackerRetentionDays) {
                    ForEach(retentionOptions, id: \.self) { days in
                        Text(String(localized: "autotracker.days \(days)")).tag(days)
                    }
                }
            }

            Section {
                Text(String(localized: "autotracker.privacyNote"))
                    .font(.system(size: Theme.FontSize.footnote))
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .formStyle(.grouped)
        .task {
            if let autotracker {
                ruleCount = (try? await autotracker.allRules().count) ?? 0
            }
        }
        .sheet(isPresented: $showRuleList) {
            // Refresh count when sheet dismisses
            Task {
                if let autotracker {
                    ruleCount = (try? await autotracker.allRules().count) ?? 0
                }
            }
        } content: {
            if let autotracker, let projectCatalog {
                RuleListView(
                    autotracker: autotracker,
                    projectCatalog: projectCatalog,
                    onDismiss: { showRuleList = false }
                )
            }
        }
    }

    private func addExcludedApp() {
        settings.addExcludedApp(newExcludedBundleId)
        newExcludedBundleId = ""
    }
}

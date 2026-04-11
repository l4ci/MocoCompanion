import AppKit
import SwiftUI

/// Settings tab for the Timeline feature: three independent sections for
/// app-activity recording, calendar integration, and automation rules.
struct AutotrackerSettingsTab: View {
    @Bindable var settings: SettingsStore
    var autotracker: Autotracker?
    var projectCatalog: ProjectCatalog?
    var appState: AppState?

    @Environment(\.theme) private var theme
    @State private var showRuleList = false
    @State private var ruleCount: Int = 0

    private let retentionOptions = [7, 14, 30]

    var body: some View {
        Form {
            appRecordingSection
            calendarSection
            rulesSection

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
                    onDismiss: { showRuleList = false },
                    settings: settings
                )
            }
        }
    }

    // MARK: - Section: Record app activity

    @ViewBuilder
    private var appRecordingSection: some View {
        Section(String(localized: "timeline.section.appRecording")) {
            Toggle(String(localized: "timeline.toggle.appRecording"), isOn: $settings.appRecordingEnabled)
                .onChange(of: settings.appRecordingEnabled) { _, enabled in
                    if enabled {
                        autotracker?.start()
                    } else {
                        autotracker?.stop()
                    }
                }

            if settings.appRecordingEnabled {
                // Status rows
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

                // Retention policy
                Picker(String(localized: "autotracker.retention"), selection: $settings.autotrackerRetentionDays) {
                    ForEach(retentionOptions, id: \.self) { days in
                        Text(String(localized: "autotracker.days \(days)")).tag(days)
                    }
                }

                // Excluded apps
                DisclosureGroup(String(localized: "autotracker.excludedApps")) {
                    ForEach(settings.autotrackerExcludedApps, id: \.self) { bundleId in
                        HStack {
                            Text(runningAppName(for: bundleId).map { "\($0) (\(bundleId))" } ?? bundleId)
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

                    RunningAppPicker(label: String(localized: "autotracker.excludedApps.add")) { bundleId, _ in
                        if !settings.autotrackerExcludedApps.contains(bundleId) {
                            settings.addExcludedApp(bundleId)
                        }
                    }
                }

                // Window-title sub-toggle
                Toggle(String(localized: "timeline.toggle.windowTitleTracking"), isOn: $settings.windowTitleTrackingEnabled)
                    .onChange(of: settings.windowTitleTrackingEnabled) { _, enabled in
                        if enabled {
                            _ = AccessibilityPermission.requestAccess()
                        }
                    }

                if settings.windowTitleTrackingEnabled && !AccessibilityPermission.isTrusted {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "timeline.windowTitle.notGranted"))
                            .font(.system(size: Theme.FontSize.footnote))
                            .foregroundStyle(.orange)
                        Button(String(localized: "accessibility.placeholder.openSettings")) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Section: Calendar integration

    @ViewBuilder
    private var calendarSection: some View {
        Section(String(localized: "timeline.section.calendar")) {
            Toggle(String(localized: "timeline.toggle.calendar"), isOn: $settings.calendarEnabled)
                .onChange(of: settings.calendarEnabled) { _, enabled in
                    guard enabled, let service = appState?.calendarService else { return }
                    Task {
                        _ = await service.requestAccessIfNeeded()
                        service.refreshAvailableCalendars()
                    }
                }

            if settings.calendarEnabled {
                if let service = appState?.calendarService {
                    if service.hasReadAccess {
                        Picker(String(localized: "timeline.calendar.picker"), selection: $settings.selectedCalendarId) {
                            Text(String(localized: "timeline.calendar.none")).tag(String?.none)
                            ForEach(service.availableCalendars) { cal in
                                Text("\(cal.title) (\(cal.sourceTitle))").tag(String?.some(cal.id))
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "calendar.placeholder.denied"))
                                .font(.system(size: Theme.FontSize.footnote))
                                .foregroundStyle(.red)
                            Button(String(localized: "calendar.placeholder.openSettings")) {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Section: Automation rules

    @ViewBuilder
    private var rulesSection: some View {
        Section(String(localized: "timeline.section.rules")) {
            Toggle(String(localized: "timeline.toggle.rules"), isOn: $settings.rulesEnabled)

            if settings.rulesEnabled, autotracker != nil, projectCatalog != nil {
                Button {
                    showRuleList = true
                } label: {
                    HStack {
                        Text(String(localized: "timeline.rules.manage"))
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
    }

    /// Returns the display name for a bundle id if the app is currently running, nil otherwise.
    private func runningAppName(for bundleId: String) -> String? {
        NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleId })?
            .localizedName
    }
}

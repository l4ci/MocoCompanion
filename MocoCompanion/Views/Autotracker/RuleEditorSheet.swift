import AppKit
import SwiftUI

// MARK: - Match Criteria Types

private struct AppMatchCriteria {
    var appBundleId: String = ""
    var appNamePattern: String = ""
    var windowTitlePattern: String = ""
}

private struct CalendarMatchCriteria {
    var eventTitle: String = ""
}

private enum RuleMatchCriteria {
    case app(AppMatchCriteria)
    case calendar(CalendarMatchCriteria)

    var ruleType: RuleType {
        switch self {
        case .app: return .app
        case .calendar: return .calendar
        }
    }
}

// MARK: - RuleEditorSheet

/// Sheet for creating or editing a TrackingRule. Follows the same pattern
/// as TimelineEntryCreationSheet — Form-based with project/task search picker.
struct RuleEditorSheet: View {
    /// Non-nil when editing an existing rule; nil for create mode.
    let existingRule: TrackingRule?
    let prefillBundleId: String?
    let prefillAppName: String?
    /// Forces the rule type when opening from a source that already knows
    /// which branch applies (e.g. calendar right-click context menu).
    let prefillRuleType: RuleType?
    /// Seeds the calendar event-title-contains field when opening from a
    /// calendar event.
    let prefillEventTitle: String?
    let autotracker: Autotracker
    let projectCatalog: ProjectCatalog
    /// Optional SettingsStore used to surface the window-title-tracking
    /// disclaimer next to the window-title pattern field.
    let settings: SettingsStore?
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var name: String = ""
    @State private var matchCriteria: RuleMatchCriteria
    @State private var mode: RuleMode = .suggest
    @State private var selectedEntry: SearchEntry?
    @State private var descriptionText: String = ""
    @State private var enabled: Bool = true
    @State private var searchText: String = ""
    @State private var errorMessage: String?
    @State private var runningApps: [RunningAppOption] = []

    private var isEditing: Bool { existingRule != nil }

    init(
        existingRule: TrackingRule?,
        prefillBundleId: String? = nil,
        prefillAppName: String? = nil,
        prefillRuleType: RuleType? = nil,
        prefillEventTitle: String? = nil,
        autotracker: Autotracker,
        projectCatalog: ProjectCatalog,
        settings: SettingsStore? = nil,
        onSave: @escaping () -> Void
    ) {
        self.existingRule = existingRule
        self.prefillBundleId = prefillBundleId
        self.prefillAppName = prefillAppName
        self.prefillRuleType = prefillRuleType
        self.prefillEventTitle = prefillEventTitle
        self.autotracker = autotracker
        self.projectCatalog = projectCatalog
        self.settings = settings
        self.onSave = onSave

        let resolvedType = prefillRuleType ?? existingRule?.ruleType ?? .app
        let initialCriteria: RuleMatchCriteria
        switch resolvedType {
        case .app:
            initialCriteria = .app(AppMatchCriteria(
                appBundleId: prefillBundleId ?? existingRule?.appBundleId ?? "",
                appNamePattern: prefillAppName ?? existingRule?.appNamePattern ?? "",
                windowTitlePattern: existingRule?.windowTitlePattern ?? ""
            ))
        case .calendar:
            initialCriteria = .calendar(CalendarMatchCriteria(
                eventTitle: prefillEventTitle ?? existingRule?.eventTitlePattern ?? ""
            ))
        }
        _matchCriteria = State(initialValue: initialCriteria)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            ruleTypePicker
            matchCriteriaSection
            actionSection
            targetEntrySection
            enabledToggle
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: Theme.FontSize.caption))
                    .foregroundStyle(.red)
            }
            Divider()
            buttonRow
        }
        .padding(16)
        .frame(width: 420, alignment: .topLeading)
        .onAppear {
            populateFields()
            runningApps = fetchRunningApps()
        }
    }

    // MARK: - Header

    private var header: some View {
        Text(isEditing ? "Edit Rule" : "New Rule")
            .font(.system(size: Theme.FontSize.callout, weight: .semibold))
            .foregroundStyle(theme.textPrimary)
    }

    // MARK: - Rule Type Picker

    private var ruleTypePicker: some View {
        Picker(String(localized: "rule.type.label"), selection: ruleTypeBinding) {
            Text(String(localized: "rule.type.app")).tag(RuleType.app)
            Text(String(localized: "rule.type.calendar")).tag(RuleType.calendar)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    /// Binding that maps between the picker's RuleType selection and the
    /// matchCriteria enum. Switching types replaces the whole enum case,
    /// discarding the previous branch's state.
    private var ruleTypeBinding: Binding<RuleType> {
        Binding(
            get: { matchCriteria.ruleType },
            set: { newType in
                guard newType != matchCriteria.ruleType else { return }
                switch newType {
                case .app:
                    matchCriteria = .app(AppMatchCriteria())
                case .calendar:
                    matchCriteria = .calendar(CalendarMatchCriteria())
                }
            }
        )
    }

    // MARK: - Match Criteria

    @ViewBuilder
    private var matchCriteriaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Match Criteria")
                .font(.system(size: Theme.FontSize.caption, weight: .medium))
                .foregroundStyle(theme.textSecondary)

            TextField("Rule name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: Theme.FontSize.body))

            switch matchCriteria {
            case .app:
                appMatchFields
            case .calendar:
                calendarMatchFields
            }
        }
    }

    private var appMatchFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            // App picker — chooses from currently running user-facing
            // applications. Sets both the bundle id (used for matching)
            // and a display name so the rule list reads nicely.
            VStack(alignment: .leading, spacing: 2) {
                Menu {
                    if runningApps.isEmpty {
                        Text("No running apps detected")
                    } else {
                        ForEach(runningApps) { app in
                            Button {
                                setAppCriteria { criteria in
                                    criteria.appBundleId = app.id
                                    criteria.appNamePattern = app.name
                                }
                                if name.trimmingCharacters(in: .whitespaces).isEmpty {
                                    name = app.name
                                }
                            } label: {
                                Text("\(app.name)  (\(app.id))")
                            }
                        }
                    }
                    Divider()
                    Button("Refresh list") {
                        runningApps = fetchRunningApps()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "app.dashed")
                            .foregroundStyle(theme.textTertiary)
                        Text(appPickerLabel)
                            .foregroundStyle(currentAppBundleId.isEmpty ? theme.textTertiary : theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(theme.textTertiary.opacity(0.3), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: false, vertical: true)

                if !currentAppBundleId.isEmpty {
                    Text(currentAppBundleId)
                        .font(.system(size: Theme.FontSize.caption, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                        .padding(.leading, 2)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                TextField(
                    String(localized: "rule.field.windowTitlePattern"),
                    text: windowTitlePatternBinding
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: Theme.FontSize.body))

                if !(settings?.windowTitleTrackingEnabled ?? false) {
                    Text(String(localized: "rule.field.windowTitlePattern.disclaimer"))
                        .font(.system(size: Theme.FontSize.footnote))
                        .foregroundStyle(.orange)
                }
                Text("Examples:  •  \"Pull request\"   •  \"#\\d+\" (regex)")
                    .font(.system(size: Theme.FontSize.caption))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private var calendarMatchFields: some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField(
                String(localized: "rule.field.eventTitle"),
                text: eventTitleBinding
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(size: Theme.FontSize.body))

            Text(String(localized: "rule.field.eventTitle.hint"))
                .font(.system(size: Theme.FontSize.footnote))
                .foregroundStyle(theme.textTertiary)
        }
    }

    // MARK: - Criteria Accessors

    /// The active app bundle ID, or empty string when in calendar mode.
    private var currentAppBundleId: String {
        guard case .app(let c) = matchCriteria else { return "" }
        return c.appBundleId
    }

    /// Label shown in the app picker button.
    private var appPickerLabel: String {
        guard case .app(let c) = matchCriteria else { return "Choose running app…" }
        if c.appBundleId.isEmpty { return "Choose running app…" }
        if !c.appNamePattern.isEmpty { return c.appNamePattern }
        return c.appBundleId
    }

    private var windowTitlePatternBinding: Binding<String> {
        Binding(
            get: {
                guard case .app(let c) = matchCriteria else { return "" }
                return c.windowTitlePattern
            },
            set: { newValue in
                setAppCriteria { $0.windowTitlePattern = newValue }
            }
        )
    }

    private var eventTitleBinding: Binding<String> {
        Binding(
            get: {
                guard case .calendar(let c) = matchCriteria else { return "" }
                return c.eventTitle
            },
            set: { newValue in
                if case .calendar(var c) = matchCriteria {
                    c.eventTitle = newValue
                    matchCriteria = .calendar(c)
                }
            }
        )
    }

    /// Mutates the app criteria in-place; no-op when in calendar mode.
    private func setAppCriteria(_ mutate: (inout AppMatchCriteria) -> Void) {
        guard case .app(var c) = matchCriteria else { return }
        mutate(&c)
        matchCriteria = .app(c)
    }

    // MARK: - Action

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Action")
                .font(.system(size: Theme.FontSize.caption, weight: .medium))
                .foregroundStyle(theme.textSecondary)

            Picker("Mode", selection: $mode) {
                Text("Suggest").tag(RuleMode.suggest)
                Text("Create").tag(RuleMode.create)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Target Entry

    private var targetEntrySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Target Entry")
                .font(.system(size: Theme.FontSize.caption, weight: .medium))
                .foregroundStyle(theme.textSecondary)

            TextField("Search projects…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: Theme.FontSize.body))

            let entries = projectCatalog.filter(query: searchText)
            if entries.isEmpty {
                Text(projectCatalog.searchEntries.isEmpty ? "No projects loaded" : "No matches")
                    .font(.system(size: Theme.FontSize.caption))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(entries.prefix(20), id: \.taskId) { entry in
                            ProjectPickerRow(
                                entry: entry,
                                isSelected: selectedEntry?.projectId == entry.projectId
                                    && selectedEntry?.taskId == entry.taskId,
                                onTap: { selectedEntry = entry }
                            )
                        }
                    }
                }
                .frame(maxHeight: 150)
            }

            VStack(alignment: .leading, spacing: 2) {
                TextField("Description template", text: $descriptionText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: Theme.FontSize.body))
                Text("Example: \"Code review — {app}\" — the text is used as-is when the rule fires.")
                    .font(.system(size: Theme.FontSize.caption))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }


    // MARK: - Enabled Toggle

    private var enabledToggle: some View {
        Toggle("Enabled", isOn: $enabled)
            .font(.system(size: Theme.FontSize.body))
    }

    // MARK: - Buttons

    private var buttonRow: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button(isEditing ? "Save" : "Create Rule") {
                save()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!isValid)
        }
    }

    // MARK: - Validation & Save

    private var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              selectedEntry != nil else { return false }
        switch matchCriteria {
        case .app(let app):
            return !app.appBundleId.isEmpty || !app.appNamePattern.isEmpty || !app.windowTitlePattern.isEmpty
        case .calendar(let calendar):
            return !calendar.eventTitle.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func save() {
        guard let entry = selectedEntry else { return }
        errorMessage = nil

        let now = ISO8601DateFormatter().string(from: Date())
        var rule = existingRule ?? TrackingRule(
            id: nil,
            name: "",
            appBundleId: nil,
            appNamePattern: nil,
            windowTitlePattern: nil,
            eventTitlePattern: nil,
            mode: .suggest,
            ruleType: .app,
            projectId: 0,
            projectName: "",
            taskId: 0,
            taskName: "",
            description: "",
            enabled: true,
            createdAt: now,
            updatedAt: now
        )

        rule.name = name.trimmingCharacters(in: .whitespaces)

        // Populate only the active branch's fields; nil out the other branch
        // because TrackingRule is a flat struct and we must not leave stale
        // values from a previous save in the inactive fields.
        switch matchCriteria {
        case .app(let app):
            rule.ruleType = .app
            rule.appBundleId = app.appBundleId.isEmpty ? nil : app.appBundleId
            rule.appNamePattern = app.appNamePattern.isEmpty ? nil : app.appNamePattern
            rule.windowTitlePattern = app.windowTitlePattern.isEmpty ? nil : app.windowTitlePattern
            rule.eventTitlePattern = nil
        case .calendar(let calendar):
            rule.ruleType = .calendar
            rule.appBundleId = nil
            rule.appNamePattern = nil
            rule.windowTitlePattern = nil
            let trimmed = calendar.eventTitle.trimmingCharacters(in: .whitespaces)
            rule.eventTitlePattern = trimmed.isEmpty ? nil : trimmed
        }

        rule.mode = mode
        rule.projectId = entry.projectId
        rule.projectName = entry.projectName
        rule.taskId = entry.taskId
        rule.taskName = entry.taskName
        rule.description = descriptionText
        rule.enabled = enabled
        rule.updatedAt = now

        Task {
            do {
                if isEditing {
                    try await autotracker.updateRule(rule)
                } else {
                    _ = try await autotracker.insertRule(rule)
                }
                onSave()
                dismiss()
            } catch {
                errorMessage = "Failed to save rule: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Populate

    private func populateFields() {
        if let rule = existingRule {
            name = rule.name
            mode = rule.mode
            descriptionText = rule.description
            enabled = rule.enabled
            selectedEntry = projectCatalog.searchEntries.first {
                $0.projectId == rule.projectId && $0.taskId == rule.taskId
            }
            // matchCriteria is already seeded from existingRule in init;
            // populateFields handles the non-criteria fields only.
        } else {
            if let appName = prefillAppName, !appName.isEmpty {
                name = appName
            }
            if let prefilledEvent = prefillEventTitle, !prefilledEvent.isEmpty,
               name.trimmingCharacters(in: .whitespaces).isEmpty {
                name = prefilledEvent
            }
        }
    }

}

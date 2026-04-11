import AppKit
import SwiftUI

/// Sheet for creating or editing a TrackingRule. Follows the same pattern
/// as TimelineEntryCreationSheet — Form-based with project/task search picker.
struct RuleEditorSheet: View {
    /// Non-nil when editing an existing rule; nil for create mode.
    let existingRule: TrackingRule?
    let prefillBundleId: String?
    let prefillAppName: String?
    let autotracker: Autotracker
    let projectCatalog: ProjectCatalog
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var name: String = ""
    @State private var appBundleId: String = ""
    @State private var appNamePattern: String = ""
    @State private var windowTitlePattern: String = ""
    @State private var mode: RuleMode = .suggest
    @State private var selectedEntry: SearchEntry?
    @State private var descriptionText: String = ""
    @State private var enabled: Bool = true
    @State private var searchText: String = ""
    @State private var errorMessage: String?
    @State private var runningApps: [RunningAppOption] = []

    private var isEditing: Bool { existingRule != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
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

    // MARK: - Match Criteria

    private var matchCriteriaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Match Criteria")
                .font(.system(size: Theme.FontSize.caption, weight: .medium))
                .foregroundStyle(theme.textSecondary)

            TextField("Rule name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: Theme.FontSize.body))

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
                                appBundleId = app.id
                                appNamePattern = app.name
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
                            .foregroundStyle(appBundleId.isEmpty ? theme.textTertiary : theme.textPrimary)
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

                if !appBundleId.isEmpty {
                    Text(appBundleId)
                        .font(.system(size: Theme.FontSize.caption, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                        .padding(.leading, 2)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                TextField("Window Title Pattern", text: $windowTitlePattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: Theme.FontSize.body))
                    .disabled(true)
                    .foregroundStyle(theme.textTertiary)

                Text("Window title matching is not available in sandboxed mode")
                    .font(.system(size: Theme.FontSize.caption))
                    .foregroundStyle(theme.textTertiary)
                Text("Examples:  •  \"Pull request\"   •  \"#\\d+\" (regex)")
                    .font(.system(size: Theme.FontSize.caption))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    /// Label shown in the app picker button.
    private var appPickerLabel: String {
        if appBundleId.isEmpty {
            return "Choose running app…"
        }
        if !appNamePattern.isEmpty {
            return appNamePattern
        }
        return appBundleId
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
        !name.trimmingCharacters(in: .whitespaces).isEmpty && selectedEntry != nil
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
        rule.appBundleId = appBundleId.isEmpty ? nil : appBundleId
        rule.appNamePattern = appNamePattern.isEmpty ? nil : appNamePattern
        rule.windowTitlePattern = windowTitlePattern.isEmpty ? nil : windowTitlePattern
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
            appBundleId = rule.appBundleId ?? ""
            appNamePattern = rule.appNamePattern ?? ""
            windowTitlePattern = rule.windowTitlePattern ?? ""
            mode = rule.mode
            descriptionText = rule.description
            enabled = rule.enabled
            // Pre-select the project/task from the catalog
            selectedEntry = projectCatalog.searchEntries.first {
                $0.projectId == rule.projectId && $0.taskId == rule.taskId
            }
        } else {
            appBundleId = prefillBundleId ?? ""
            appNamePattern = prefillAppName ?? ""
            if let appName = prefillAppName, !appName.isEmpty {
                name = appName
            }
        }
    }

}

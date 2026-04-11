import SwiftUI

/// View for managing all tracking rules: list, toggle, edit, delete.
struct RuleListView: View {
    let autotracker: Autotracker
    let projectCatalog: ProjectCatalog
    let onDismiss: () -> Void

    @Environment(\.theme) private var theme
    @State private var rules: [TrackingRule] = []
    @State private var editingRule: TrackingRule?
    @State private var deletingRule: TrackingRule?
    @State private var showCreateSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if rules.isEmpty {
                emptyState
            } else {
                ruleList
            }
            Divider()
            footer
        }
        .frame(width: 480, height: 400)
        .task { await loadRules() }
        .sheet(item: $editingRule) { rule in
            RuleEditorSheet(
                existingRule: rule,
                prefillBundleId: nil,
                prefillAppName: nil,
                autotracker: autotracker,
                projectCatalog: projectCatalog,
                onSave: { Task { await loadRules() } }
            )
        }
        .sheet(isPresented: $showCreateSheet) {
            RuleEditorSheet(
                existingRule: nil,
                prefillBundleId: nil,
                prefillAppName: nil,
                autotracker: autotracker,
                projectCatalog: projectCatalog,
                onSave: { Task { await loadRules() } }
            )
        }
        .confirmationDialog(
            "Delete Rule",
            isPresented: Binding(
                get: { deletingRule != nil },
                set: { if !$0 { deletingRule = nil } }
            ),
            presenting: deletingRule
        ) { rule in
            Button("Delete", role: .destructive) {
                Task {
                    if let id = rule.id {
                        try? await autotracker.deleteRule(id: id)
                    }
                    await loadRules()
                }
            }
        } message: { rule in
            Text("Delete \"\(rule.name)\"? This cannot be undone.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Tracking Rules")
                .font(.system(size: Theme.FontSize.callout, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Button {
                showCreateSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No rules configured")
                .font(.system(size: Theme.FontSize.body))
                .foregroundStyle(theme.textSecondary)
            Button("Create Rule") {
                showCreateSheet = true
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rule List

    /// Rules grouped by Moco project name, then sorted by project name
    /// (case-insensitive) so that everything belonging to the same
    /// project is visually clustered together.
    private var groupedRules: [(project: String, rules: [TrackingRule])] {
        let grouped = Dictionary(grouping: rules) { $0.projectName }
        return grouped
            .map { (project: $0.key, rules: $0.value.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) }
            .sorted { $0.project.localizedCaseInsensitiveCompare($1.project) == .orderedAscending }
    }

    private var ruleList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedRules, id: \.project) { group in
                    Section {
                        ForEach(group.rules) { rule in
                            ruleRow(rule)
                        }
                    } header: {
                        projectGroupHeader(group.project, count: group.rules.count)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func projectGroupHeader(_ name: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: Theme.FontSize.caption, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.4)
            Text("\(count)")
                .font(.system(size: Theme.FontSize.caption, weight: .medium, design: .rounded))
                .foregroundStyle(theme.textTertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(theme.surface))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(theme.panelBackground)
    }

    private func ruleRow(_ rule: TrackingRule) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .font(.system(size: Theme.FontSize.body, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text("\(rule.projectName) › \(rule.taskName)")
                    .font(.system(size: Theme.FontSize.caption))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            modeBadge(rule.mode)

            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { _ in toggleEnabled(rule) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()

            Button {
                editingRule = rule
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: Theme.FontSize.body))
                    .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.plain)

            Button {
                deletingRule = rule
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: Theme.FontSize.body))
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func modeBadge(_ mode: RuleMode) -> some View {
        Text(mode == .suggest ? "Suggest" : "Create")
            .font(.system(size: Theme.FontSize.caption, weight: .medium))
            .foregroundStyle(mode == .suggest ? .blue : .green)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill((mode == .suggest ? Color.blue : Color.green).opacity(0.12))
            )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("\(rules.count) rule\(rules.count == 1 ? "" : "s")")
                .font(.system(size: Theme.FontSize.caption))
                .foregroundStyle(theme.textTertiary)
            Spacer()
            Button("Done") { onDismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func loadRules() async {
        rules = (try? await autotracker.allRules()) ?? []
    }

    private func toggleEnabled(_ rule: TrackingRule) {
        Task {
            var updated = rule
            updated.enabled.toggle()
            try? await autotracker.updateRule(updated)
            await loadRules()
        }
    }
}

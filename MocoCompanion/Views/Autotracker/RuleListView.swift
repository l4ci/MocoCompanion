import SwiftUI

/// View for managing all tracking rules: list, toggle, edit, delete.
struct RuleListView: View {
    let ruleStore: RuleStore
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
                ruleStore: ruleStore,
                projectCatalog: projectCatalog,
                onSave: { Task { await loadRules() } }
            )
        }
        .sheet(isPresented: $showCreateSheet) {
            RuleEditorSheet(
                existingRule: nil,
                prefillBundleId: nil,
                prefillAppName: nil,
                ruleStore: ruleStore,
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
                        try? await ruleStore.delete(id: id)
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

    private var ruleList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(rules) { rule in
                    ruleRow(rule)
                }
            }
            .padding(.vertical, 4)
        }
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
        rules = (try? await ruleStore.allRules()) ?? []
    }

    private func toggleEnabled(_ rule: TrackingRule) {
        Task {
            var updated = rule
            updated.enabled.toggle()
            try? await ruleStore.update(updated)
            await loadRules()
        }
    }
}

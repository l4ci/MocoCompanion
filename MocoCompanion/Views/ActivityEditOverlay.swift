import SwiftUI

/// Shared inline edit overlay for activity descriptions, hours, and project/task reassignment.
/// Used by both TodayView (panel) and StatusPopoverView (popover).
struct ActivityEditOverlay: View {
    let activity: MocoActivity
    @Binding var descriptionDraft: String
    @Binding var hoursDraft: String
    var onSave: () -> Void
    var onCancel: () -> Void
    var onReassign: ((Int, Int) -> Void)? = nil

    /// Available projects for reassignment (nil = no reassignment UI).
    var projects: [MocoProject]? = nil

    var autoFocus: Bool = true
    var placeholder: String = String(localized: "edit.description")
    var showHeader: Bool = true
    var showHours: Bool = false

    @State private var selectedProjectId: Int = 0
    @State private var selectedTaskId: Int = 0
    @State private var projectSearchText = ""
    @State private var isSearchingProject = false

    @FocusState private var focusedField: Field?
    @Environment(\.entryFontSizeBoost) private var fontBoost

    private var bodySize: CGFloat { 14 + fontBoost }
    private var captionSize: CGFloat { 12 + fontBoost }

    private enum Field {
        case description, hours
    }

    /// Tasks available for the currently selected project.
    private var availableTasks: [MocoTask] {
        guard let projects else { return [] }
        return projects.first(where: { $0.id == selectedProjectId })?.tasks.filter(\.active) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showHeader {
                if projects != nil {
                    editableHeader
                } else {
                    Text("\(activity.project.name) › \(activity.task.name)")
                        .font(.system(size: bodySize, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.7))
                        .lineLimit(1)
                }
            }

            HStack(spacing: 6) {
                TextField(placeholder, text: $descriptionDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: bodySize))
                    .focused($focusedField, equals: .description)
                    .onSubmit { handleSave() }
                    .onExitCommand { onCancel() }
                    .accessibilityLabel(String(localized: "a11y.description"))

                if showHours {
                    TextField("0.0h", text: $hoursDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: bodySize, design: .monospaced))
                        .frame(width: 52)
                        .focused($focusedField, equals: .hours)
                        .onSubmit { handleSave() }
                        .onExitCommand { onCancel() }
                        .accessibilityLabel(String(localized: "a11y.hours"))
                }

                Button {
                    handleSave()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: bodySize + 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "a11y.saveChanges"))
            }
        }
        .onAppear {
            selectedProjectId = activity.project.id
            selectedTaskId = activity.task.id
            if autoFocus {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    focusedField = showHours ? .hours : .description
                }
            }
        }
    }

    // MARK: - Editable Header

    @ViewBuilder
    private var editableHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isSearchingProject {
                ProjectSearchField(
                    searchText: $projectSearchText,
                    isSearching: $isSearchingProject,
                    projects: projects ?? [],
                    onSelect: { selectProject($0) }
                )
            } else {
                Button {
                    isSearchingProject = true
                    projectSearchText = ""
                } label: {
                    HStack(spacing: 4) {
                        Text(currentProjectName)
                            .font(.system(size: bodySize, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.8))
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: captionSize, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "a11y.changeProject \(currentProjectName)"))
            }

            if !availableTasks.isEmpty {
                Picker(String(localized: "edit.task"), selection: $selectedTaskId) {
                    ForEach(availableTasks) { task in
                        Text(task.name).tag(task.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .font(.system(size: captionSize))
                .frame(maxWidth: 200, alignment: .leading)
                .accessibilityLabel(String(localized: "edit.task"))
            }
        }
    }

    // MARK: - Helpers

    private var currentProjectName: String {
        guard let projects else { return activity.project.name }
        return projects.first(where: { $0.id == selectedProjectId })?.name ?? activity.project.name
    }

    private func selectProject(_ project: MocoProject) {
        selectedProjectId = project.id
        if let firstTask = project.tasks.first(where: { $0.active }) {
            selectedTaskId = firstTask.id
        }
        isSearchingProject = false
    }

    private func handleSave() {
        let projectChanged = selectedProjectId != activity.project.id
        let taskChanged = selectedTaskId != activity.task.id

        if (projectChanged || taskChanged), let onReassign {
            onReassign(selectedProjectId, selectedTaskId)
        }
        onSave()
    }
}

// MARK: - Convenience (description-only, backward compatible)

extension ActivityEditOverlay {
    init(
        activity: MocoActivity,
        descriptionDraft: Binding<String>,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        autoFocus: Bool = true,
        placeholder: String = String(localized: "edit.description"),
        showHeader: Bool = true
    ) {
        self.activity = activity
        self._descriptionDraft = descriptionDraft
        self._hoursDraft = .constant("")
        self.onSave = onSave
        self.onCancel = onCancel
        self.autoFocus = autoFocus
        self.placeholder = placeholder
        self.showHeader = showHeader
        self.showHours = false
        self.projects = nil
        self.onReassign = nil
    }
}

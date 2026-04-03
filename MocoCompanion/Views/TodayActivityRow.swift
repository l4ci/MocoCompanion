import SwiftUI

/// A single activity row in the Today/Yesterday tab.
/// Handles four states: normal display, inline edit (description + optional hours), delete confirmation.
struct TodayActivityRow: View {
    let activity: MocoActivity
    let index: Int
    let isSelected: Bool
    let isHovered: Bool
    let isRunning: Bool
    let isPaused: Bool
    let shortcutIndex: Int

    /// Whether this row is showing a yesterday entry (changes available actions).
    var isYesterday: Bool = false
    /// Planned hours for this activity's project+task (nil if not planned).
    var plannedHours: Double? = nil
    /// Available projects for reassignment.
    var projects: [MocoProject] = []
    /// Budget service for badge lookups (nil if unavailable).
    var budgetService: BudgetService? = nil

    @Binding var editingActivityId: Int?
    @Binding var deletingActivityId: Int?
    @Binding var descriptionDraft: String
    @Binding var hoursDraft: String
    @Binding var hoveredActivityId: Int?

    var activityService: ActivityService
    var favoritesManager: FavoritesManager?
    var onSelect: () -> Void
    var onAction: () -> Void
    var onFocusList: () -> Void

    @Environment(\.entryFontSizeBoost) private var fontBoost
    @Environment(\.theme) private var theme

    /// Caption-sized font for secondary elements (icons, planned hours).
    private var captionSize: CGFloat { 12 + fontBoost }

    var body: some View {
        let isEditing = editingActivityId == activity.id
        let isDeleting = deletingActivityId == activity.id

        VStack(spacing: 0) {
            if isDeleting {
                deleteConfirmation
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else if isEditing {
                ActivityEditOverlay(
                    activity: activity,
                    descriptionDraft: $descriptionDraft,
                    hoursDraft: $hoursDraft,
                    onSave: { saveEdit() },
                    onCancel: { cancelEditing() },
                    onReassign: { projectId, taskId in reassign(projectId: projectId, taskId: taskId) },
                    projects: projects,
                    showHeader: true,
                    showHours: true
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else {
                let badge = budgetService?.status(projectId: activity.project.id, taskId: activity.task.id).effectiveBadge ?? .none
                EntryRow(
                    projectName: activity.project.name,
                    customerName: activity.customer.name,
                    taskName: activity.task.name,
                    description: activity.description.isEmpty ? nil : activity.description,
                    isSelected: isSelected,
                    isHovered: isHovered,
                    isRunning: isRunning,
                    isPaused: isPaused,
                    shortcutIndex: shortcutIndex,
                    isFavorite: favoritesManager?.isFavorite(projectId: activity.project.id, taskId: activity.task.id),
                    onToggleFavorite: favoritesManager != nil ? { toggleFavorite() } : nil,
                    hints: rowHints,
                    budgetBadge: badge
                ) {
                    HStack(spacing: 6) {
                        ActivityDurationText(
                            activity: activity,
                            isSelected: isSelected
                        )

                        if let planned = plannedHours {
                            Text("of \(String(format: "%.0fh", planned))")
                                .font(.system(size: captionSize, weight: .medium))
                                .foregroundStyle(isSelected ? theme.selectedTextTertiary : .secondary)
                        }
                    }
                }
                .onHover { hover in
                    if hover {
                        hoveredActivityId = activity.id
                    } else {
                        hoveredActivityId = nil
                    }
                }
                .onTapGesture {
                    onSelect()
                    onAction()
                }
            }
        }
    }

    private var rowHints: [String] {
        if isYesterday {
            return [String(localized: "hint.enterContinue"), String(localized: "hint.edit"), String(localized: "hint.delete"), String(localized: "hint.favorite")]
        }
        if isRunning { return [String(localized: "hint.enterPause"), String(localized: "hint.favorite")] }
        if isPaused { return [String(localized: "hint.enterResume"), String(localized: "hint.edit"), String(localized: "hint.delete"), String(localized: "hint.favorite")] }
        return [String(localized: "hint.enterContinue"), String(localized: "hint.edit"), String(localized: "hint.delete"), String(localized: "hint.favorite")]
    }

    private var deleteConfirmation: some View {
        HStack(spacing: 8) {
            Text(String(localized: "action.deleteConfirm \(activity.project.name)"))
                .font(.system(size: 15 + fontBoost, weight: .medium))
                .foregroundStyle(.red)
                .lineLimit(1)

            Spacer()

            Button {
                cancelDelete()
            } label: {
                HStack(spacing: 4) {
                    Text(String(localized: "action.cancel"))
                    Text("(Esc)")
                        .font(.system(size: captionSize - 1))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(String(localized: "a11y.cancelDelete"))

            Button {
                confirmDelete()
            } label: {
                HStack(spacing: 4) {
                    Text(String(localized: "action.delete"))
                    Text("(↩)")
                        .font(.system(size: captionSize - 1))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.mini)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel(String(localized: "a11y.confirmDelete"))
        }
        .focusable()
        .onExitCommand { cancelDelete() }
        .onKeyPress(.return) {
            confirmDelete()
            return .handled
        }
    }

    private func confirmDelete() {
        let id = activity.id
        deletingActivityId = nil
        onFocusList()  // restore focus immediately before async work
        Task {
            await activityService.deleteActivity(activityId: id)
        }
    }

    private func cancelDelete() {
        deletingActivityId = nil
        onFocusList()
    }

    private func saveEdit() {
        let newDesc = descriptionDraft
        let newHours = hoursDraft
        let activityId = activity.id
        editingActivityId = nil
        onFocusList()

        Task {
            if let hours = DateUtilities.parseHours(newHours) {
                let seconds = Int(hours * 3600)
                await activityService.editActivity(activityId: activityId, seconds: seconds, description: newDesc)
            } else {
                // Hours unchanged or unparseable, just update description
                await activityService.updateDescription(activityId: activityId, description: newDesc)
            }
        }
    }

    private func cancelEditing() {
        editingActivityId = nil
        onFocusList()
    }

    private func toggleFavorite() {
        guard let fm = favoritesManager else { return }
        let entry = SearchEntry(
            projectId: activity.project.id,
            taskId: activity.task.id,
            customerName: activity.customer.name,
            projectName: activity.project.name,
            taskName: activity.task.name
        )
        fm.toggle(entry)
    }

    private func reassign(projectId: Int, taskId: Int) {
        let activityId = activity.id
        Task {
            await activityService.reassignActivity(activityId: activityId, projectId: projectId, taskId: taskId)
        }
    }
}

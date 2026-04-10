import SwiftUI

/// A single activity row in the status popover.
/// Compact layout with project name, task, duration, and inline description editing.
struct StatusActivityRow: View {
    let activity: ShadowEntry
    let isCurrentActivity: Bool

    @Binding var editingActivityId: Int?
    @Binding var descriptionDraft: String
    @Binding var hoveredActivityId: Int?

    var activityService: ActivityService

    private var isRunning: Bool { activity.isTimerRunning }
    private var isEditing: Bool { editingActivityId == activity.id }
    private var isHovered: Bool { hoveredActivityId == activity.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Row 1: Project name + duration
            HStack(spacing: 0) {
                if isRunning {
                    Image(systemName: "play.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 10))
                        .padding(.trailing, 6)
                }

                Text(activity.projectName)
                    .font(.system(size: 13, weight: isRunning ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                ActivityDurationText(
                    activity: activity,
                    isSelected: false,
                    font: .system(size: 12, weight: .medium, design: .monospaced),
                    stoppedOpacity: 0.6
                )
            }

            // Row 2: Task name
            Text(activity.taskName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // Row 3: Editable description
            if isEditing {
                ActivityEditOverlay(
                    activity: activity,
                    descriptionDraft: $descriptionDraft,
                    onSave: { saveDescription() },
                    onCancel: { editingActivityId = nil },
                    placeholder: String(localized: "edit.descriptionPlaceholder"),
                    showHeader: false
                )
                .padding(.top, 2)
            } else {
                HStack(spacing: 6) {
                    Text(activity.description.isEmpty ? String(localized: "popover.noDescription") : activity.description)
                        .font(.system(size: 12))
                        .foregroundStyle(activity.description.isEmpty ? .quaternary : .tertiary)
                        .lineLimit(1)

                    if isCurrentActivity {
                        Button {
                            descriptionDraft = activity.description
                            editingActivityId = activity.id
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 11))
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Edit description")
                        .accessibilityLabel(String(localized: "a11y.editDescription"))
                    }

                    Spacer()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isRunning ? Color.green.opacity(0.06) :
                      isHovered ? Color.primary.opacity(0.04) : Color.primary.opacity(0.015))
        )
        .contentShape(Rectangle())
        .onHover { hover in
            hoveredActivityId = hover ? activity.id : nil
        }
    }

    private func saveDescription() {
        let newDesc = descriptionDraft
        editingActivityId = nil
        guard let activityId = activity.id else { return }
        Task { await activityService.updateDescription(activityId: activityId, description: newDesc) }
    }
}

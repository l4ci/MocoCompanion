import SwiftUI

/// Section showing planned tasks the user hasn't tracked time on today.
/// Each task has a play button to start tracking immediately.
/// Supports keyboard selection via selectedUnplannedIndex.
struct UnplannedTasksSection: View {
    let tasks: [ActivityService.UnplannedTask]
    var timerService: TimerService
    /// Index of the selected unplanned task within this section (0-based), or nil.
    var selectedIndex: Int? = nil

    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost

    private var captionSize: CGFloat { 12 + fontBoost }

    var body: some View {
        VStack(spacing: 0) {
            theme.divider.frame(height: 1)

            HStack {
                Text(String(localized: "planned.header"))
                    .font(.system(size: captionSize, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.3)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)

            VStack(spacing: 2) {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    PlannedTaskRow(
                        task: task,
                        timerService: timerService,
                        isSelected: selectedIndex == index
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
    }
}

/// A single unplanned task row with project/task info, planned hours, and start button.
struct PlannedTaskRow: View {
    let task: ActivityService.UnplannedTask
    var timerService: TimerService
    var isSelected: Bool = false

    @State private var isHovered = false

    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost

    private var bodySize: CGFloat { 14 + fontBoost }
    private var captionSize: CGFloat { 12 + fontBoost }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: captionSize))
                .foregroundStyle(isSelected ? .white.opacity(0.7) : .blue.opacity(0.7))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    if !task.customerName.isEmpty {
                        Text(task.customerName)
                            .foregroundStyle(isSelected ? .white.opacity(0.7) : theme.textSecondary)
                        Text(" › ")
                            .foregroundStyle(isSelected ? .white.opacity(0.4) : theme.textTertiary)
                    }
                    Text(task.projectName)
                        .foregroundStyle(isSelected ? .white : theme.textPrimary)
                }
                .font(.system(size: bodySize))
                .lineLimit(1)

                Text(task.taskName)
                    .font(.system(size: bodySize))
                    .fontWeight(.semibold)
                    .foregroundStyle(isSelected ? .white.opacity(0.7) : theme.textSecondary)
                    .lineLimit(1)

                if isSelected || isHovered {
                    HStack(spacing: 8) {
                        Text(String(localized: "hint.enterStart"))
                            .font(.system(size: captionSize, weight: .medium))
                    }
                    .foregroundStyle(isSelected ? .white.opacity(0.4) : theme.textTertiary)
                    .padding(.top, 2)
                }
            }

            Spacer()

            Text(String(format: "%.0fh", task.plannedHours))
                .font(.system(size: captionSize, weight: .medium, design: .monospaced))
                .foregroundStyle(isSelected ? .white.opacity(0.5) : .blue.opacity(0.6))

            Button {
                startTimer()
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: bodySize + 2))
                    .foregroundStyle(isSelected ? .white : .green)
            }
            .buttonStyle(.plain)
            .help("Start timer")
            .accessibilityLabel("Start timer for \(task.projectName)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? theme.selection : theme.surface)
        )
        .contentShape(Rectangle())
        .onHover { hovering in isHovered = hovering }
        .onTapGesture {
            startTimer()
        }
    }

    private func startTimer() {
        Task {
            _ = await timerService.startTimer(
                projectId: task.projectId,
                taskId: task.taskId,
                description: ""
            )
        }
    }
}

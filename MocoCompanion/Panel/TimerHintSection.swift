import SwiftUI

/// Timer status hint row shown when search is empty and a timer is active.
/// Shows the current project/task with elapsed time and pause/resume hint.
struct TimerHintSection: View {
    let timerState: TimerState
    let currentActivity: ShadowEntry?
    @Binding var selectedIndex: Int

    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost

    var body: some View {
        switch timerState {
        case .running(_, let projectName):
            timerHintRow(
                iconColor: .green,
                projectName: projectName,
                hint: String(localized: "hint.enterPause"),
                taskName: currentActivity?.taskName
            )
        case .paused(_, let projectName):
            timerHintRow(
                iconColor: .orange,
                projectName: projectName,
                hint: String(localized: "hint.enterResume"),
                taskName: currentActivity?.taskName
            )
        case .idle:
            EmptyView()
        }
    }

    private func timerHintRow(iconColor: Color, projectName: String, hint: String, taskName: String?) -> some View {
        let isFocused = selectedIndex == -1

        return VStack(spacing: 0) {
            theme.divider.frame(height: 1)

            EntryRow(
                projectName: projectName,
                customerName: nil,
                taskName: taskName ?? "",
                description: nil,
                isSelected: isFocused,
                isHovered: false,
                isRunning: iconColor == .green,
                isPaused: iconColor == .orange,
                hints: [hint]
            ) {
                elapsedTimeBadge(isFocused: isFocused)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(projectName), \(hint). \(taskName ?? "")")
        }
    }

    @ViewBuilder
    private func elapsedTimeBadge(isFocused: Bool) -> some View {
        if let activity = currentActivity,
           let startedAt = activity.timerStartedAt,
           let startDate = DateUtilities.parseISO8601(startedAt) {
            let baseSecs = Double(activity.seconds)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let liveSecs = baseSecs + context.date.timeIntervalSince(startDate)
                Text(DateUtilities.formatElapsedCompact(liveSecs))
                    .font(.system(size: 13 + fontBoost, weight: .medium, design: .monospaced))
                    .foregroundStyle(isFocused ? theme.selectedTextTertiary : .green)
            }
        } else if let activity = currentActivity {
            Text(DateUtilities.formatHoursCompact(Double(activity.seconds) / 3600.0))
                .font(.system(size: 13 + fontBoost, weight: .medium, design: .monospaced))
                .foregroundStyle(isFocused ? theme.selectedTextTertiary : .secondary)
        }
    }
}

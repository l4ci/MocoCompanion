import SwiftUI

/// Popover content shown when the user left-clicks the menubar icon.
/// Displays all today's activities with the running one highlighted, plus today's stats.
struct StatusPopoverView: View {
    var timerService: TimerService
    var activityService: ActivityService
    @Binding var yesterdayWarning: YesterdayWarning?

    @State private var editingActivityId: Int?
    @State private var descriptionDraft = ""
    @State private var hoveredActivityId: Int?

    private var sortedActivities: [ShadowEntry] {
        activityService.sortedTodayActivities
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let warning = yesterdayWarning {
                YesterdayBannerView(warning: warning, onDismiss: { yesterdayWarning = nil }, style: .expanded)
                    .padding(.horizontal, 18)
            }

            StatusTimerSection(
                timerState: timerService.timerState,
                currentActivity: timerService.currentActivity,
                onStop: { Task { await timerService.stopTimer() } }
            )
            .padding(.horizontal, 18)

            if !sortedActivities.isEmpty {
                sectionDivider
                    .padding(.horizontal, 18)
                activitiesList
            }

            sectionDivider
                .padding(.horizontal, 18)
            todayStatsSection
                .padding(.horizontal, 18)
            }
            .padding(.vertical, 18)
            .frame(width: 340)
    }

    private var sectionDivider: some View {
        Divider()
            .padding(.vertical, 10)
    }

    // MARK: - Activities List

    private var activitiesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "popover.todaysEntries"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(0.3)
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(sortedActivities, id: \.id) { activity in
                        StatusActivityRow(
                            activity: activity,
                            isCurrentActivity: timerService.currentActivity?.id == activity.id,
                            editingActivityId: $editingActivityId,
                            descriptionDraft: $descriptionDraft,
                            hoveredActivityId: $hoveredActivityId,
                            activityService: activityService
                        )
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(maxHeight: 320)
        }
    }

    // MARK: - Today's Stats

    private var todayStatsSection: some View {
        HStack(spacing: 10) {
            statPill(label: String(localized: "today.title"), value: "\(activityService.todayTotalHours.formatted(.number.precision(.fractionLength(1))))h")
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "a11y.todayHours \(activityService.todayTotalHours.formatted(.number.precision(.fractionLength(1))))"))

            statPill(label: String(localized: "stats.billable"), value: "\(activityService.todayBillablePercentage.formatted(.number.precision(.fractionLength(0))))%")
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "a11y.billable \(activityService.todayBillablePercentage.formatted(.number.precision(.fractionLength(0))))"))
        }
    }

    private func statPill(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(0.3)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }
}

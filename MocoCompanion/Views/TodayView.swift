import SwiftUI

/// Today/Yesterday tab content for the floating panel.
/// Thin view layer — business logic lives in TodayViewModel.
struct TodayView: View {
    @Bindable var appState: AppState
    var onTabSwitch: () -> Void = {}
    var onTypeToSearch: ((String) -> Void)? = nil
    /// Called when a planned entry is selected for tracking — switches to Track tab with entry pre-selected.
    var onStartEntry: ((SearchEntry) -> Void)? = nil

    @State private var vm: TodayViewModel
    @State private var descriptionDraft = ""
    @State private var hoursDraft = ""
    @State private var refreshId = UUID()

    @FocusState private var listFocused: Bool
    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost

    private var bodySize: CGFloat { 14 + fontBoost }
    private var captionSize: CGFloat { 12 + fontBoost }

    init(appState: AppState, onTabSwitch: @escaping () -> Void = {}, onTypeToSearch: ((String) -> Void)? = nil, onStartEntry: ((SearchEntry) -> Void)? = nil) {
        self.appState = appState
        self.onTabSwitch = onTabSwitch
        self.onTypeToSearch = onTypeToSearch
        self.onStartEntry = onStartEntry
        self._vm = State(initialValue: TodayViewModel(
            timerService: appState.timerService,
            activityService: appState.activityService,
            favoritesManager: appState.favoritesManager
        ))
    }

    enum DaySelection: CaseIterable {
        case yesterday
        case today
        case tomorrow

        var label: String {
            switch self {
            case .today: String(localized: "today.title")
            case .yesterday: String(localized: "yesterday.title")
            case .tomorrow: String(localized: "tomorrow.title")
            }
        }

        var dateString: String {
            switch self {
            case .today: DateUtilities.todayString()
            case .yesterday: DateUtilities.yesterdayString() ?? ""
            case .tomorrow: DateUtilities.tomorrowString() ?? ""
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            dayToggle

            if let absence = vm.activityService.absence(for: vm.selectedDay.dateString) {
                absenceBanner(absence)
            }

            if vm.isTomorrow {
                tomorrowView
            } else if vm.sortedActivities.isEmpty && (vm.selectedDay != .today || vm.activityService.unplannedTasks.isEmpty) {
                TodayEmptyState(isYesterday: vm.isYesterday)
            } else {
                if !vm.sortedActivities.isEmpty {
                    activitiesList
                }

                if vm.selectedDay == .today && !vm.activityService.unplannedTasks.isEmpty {
                    UnplannedTasksSection(
                        tasks: vm.activityService.unplannedTasks,
                        timerService: vm.timerService,
                        selectedIndex: vm.isUnplannedSelected ? vm.selectedIndex - vm.sortedActivities.count : nil
                    )
                }

                if !vm.isTomorrow {
                    TodayStatsFooter(
                        totalHours: vm.isYesterday ? yesterdayTotalHours : vm.activityService.todayTotalHours,
                        billablePercentage: vm.isYesterday ? yesterdayBillablePercentage : vm.activityService.todayBillablePercentage,
                        entryCount: vm.sortedActivities.count
                    )
                }
            }
        }
        .focusable()
        .focused($listFocused)
        .focusEffectDisabled()
        .task(id: refreshId) {
            await vm.activityService.refreshTodayStats()
            await vm.activityService.refreshYesterdayActivities()
            await vm.activityService.refreshAllPlanning()
            await vm.activityService.refreshAbsences()
            if let idx = vm.activeEntryIndex {
                vm.selectedIndex = idx
                vm.trackSelectedId()
            }
        }
        .onAppear {
            refreshId = UUID()
            setFocusAfterDelay($listFocused, to: true)
        }
        .onChange(of: vm.selectedDay) {
            vm.editingActivityId = nil
            vm.deletingActivityId = nil
        }
        .onChange(of: vm.activityService.todayActivities) {
            guard !vm.isYesterday else { return }
            vm.syncSelectionAfterDataChange()
        }
        .onChange(of: vm.activityService.yesterdayActivities) {
            guard vm.isYesterday else { return }
            vm.syncSelectionAfterDataChange()
        }
        .onKeyPress(phases: .down) { press in
            let action = vm.handleKeyPress(
                key: press.key,
                characters: press.characters,
                modifiers: NSApp.currentEvent?.modifierFlags ?? []
            )
            switch action {
            case .handled:
                return .handled
            case .ignored:
                return .ignored
            case .switchTab:
                onTabSwitch()
                return .handled
            case .startEntry(let entry):
                onStartEntry?(entry)
                return .handled
            case .dismiss:
                NSApp.keyWindow?.close()
                return .handled
            case .startEdit(let desc, let hours):
                descriptionDraft = desc
                hoursDraft = hours
                vm.startEditingSelected()
                return .handled
            case .typeToSearch(let chars):
                onTypeToSearch?(chars)
                return .handled
            }
        }
    }

    // MARK: - Day Toggle

    private var dayToggle: some View {
        HStack {
            HStack(spacing: 2) {
                ForEach(DaySelection.allCases, id: \.self) { day in
                    Button {
                        vm.selectedDay = day
                    } label: {
                        Text(day.label)
                            .font(.system(size: captionSize, weight: vm.selectedDay == day ? .semibold : .medium))
                            .foregroundStyle(vm.selectedDay == day ? theme.textPrimary : theme.textTertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(vm.selectedDay == day ? theme.tabPillActive : .clear)
                                    .shadow(color: vm.selectedDay == day ? .black.opacity(0.06) : .clear, radius: 1, y: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(day.label)")
                    .accessibilityAddTraits(vm.selectedDay == day ? .isSelected : [])
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.tabPillBackground)
            )

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    // MARK: - Absence Banner

    private func absenceBanner(_ schedule: MocoSchedule) -> some View {
        HStack(spacing: 8) {
            Image(systemName: schedule.assignment.name.contains("Feier") ? "calendar.badge.clock" : "airplane")
                .font(.system(size: captionSize))
                .foregroundStyle(.orange)

            Text(schedule.assignment.name)
                .font(.system(size: bodySize, weight: .medium))
                .foregroundStyle(theme.textPrimary)

            if schedule.am && !schedule.pm {
                Text("(vormittags)")
                    .font(.system(size: captionSize))
                    .foregroundStyle(theme.textSecondary)
            } else if !schedule.am && schedule.pm {
                Text("(nachmittags)")
                    .font(.system(size: captionSize))
                    .foregroundStyle(theme.textSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: - Tomorrow View

    private var tomorrowView: some View {
        VStack(spacing: 0) {
            if vm.activityService.tomorrowPlanningEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 22 + fontBoost))
                        .foregroundStyle(theme.textTertiary)
                    Text(String(localized: "tomorrow.noPlanning"))
                        .font(.system(size: bodySize, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
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
                    ForEach(vm.activityService.tomorrowPlanningEntries) { entry in
                        tomorrowPlanningRow(entry)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)

                let totalPlanned = vm.activityService.tomorrowPlanningEntries.reduce(0.0) { $0 + $1.hoursPerDay }
                HStack {
                    Spacer()
                    Text(String(format: "%.0fh geplant", totalPlanned))
                        .font(.system(size: captionSize, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
        }
    }

    private func tomorrowPlanningRow(_ entry: MocoPlanningEntry) -> some View {
        TomorrowPlanningRowView(entry: entry, onStartEntry: onStartEntry)
    }

    // MARK: - Activities List

    private var activitiesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(vm.sortedActivities.enumerated()), id: \.element.id) { index, activity in
                        TodayActivityRow(
                            activity: activity,
                            index: index,
                            isSelected: index == vm.selectedIndex,
                            isHovered: vm.hoveredActivityId == activity.id,
                            isRunning: !vm.isYesterday && activity.isTimerRunning,
                            isPaused: !vm.isYesterday && vm.timerService.isPausedActivity(activity),
                            shortcutIndex: vm.shortcutIndex(for: index),
                            isYesterday: vm.isYesterday,
                            plannedHours: vm.isYesterday ? nil : vm.activityService.plannedHours(projectId: activity.project.id, taskId: activity.task.id),
                            projects: appState.projects,
                            budgetService: appState.budgetService,
                            editingActivityId: $vm.editingActivityId,
                            deletingActivityId: $vm.deletingActivityId,
                            descriptionDraft: $descriptionDraft,
                            hoursDraft: $hoursDraft,
                            hoveredActivityId: $vm.hoveredActivityId,
                            activityService: vm.activityService,
                            favoritesManager: appState.favoritesManager,
                            onSelect: {
                                vm.selectedIndex = index
                                vm.trackSelectedId()
                            },
                            onAction: {
                                let result = vm.performEntryAction()
                                if PanelDismissPolicy.shouldDismiss(after: result) {
                                    NSApp.keyWindow?.close()
                                }
                            },
                            onFocusList: { listFocused = true }
                        )
                        .id(index)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
            }
            .frame(maxHeight: 350)
            .id(vm.selectedDay)
            .onChange(of: vm.selectedIndex) { _, newIndex in
                withAnimation(.easeOut(duration: Theme.Motion.fast)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    // MARK: - Stats

    private var yesterdayTotalHours: Double {
        vm.activityService.yesterdayActivities.reduce(0.0) { $0 + $1.hours }
    }

    private var yesterdayBillablePercentage: Double {
        let total = yesterdayTotalHours
        guard total > 0 else { return 0 }
        let billable = vm.activityService.yesterdayActivities.filter(\.billable).reduce(0.0) { $0 + $1.hours }
        return (billable / total) * 100.0
    }
}

// MARK: - Tomorrow Planning Row

/// A single planning entry row for the tomorrow tab.
/// Extracted to a struct so it can track its own hover state.
private struct TomorrowPlanningRowView: View {
    let entry: MocoPlanningEntry
    var onStartEntry: ((SearchEntry) -> Void)? = nil

    @State private var isHovered = false

    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost

    private var bodySize: CGFloat { 14 + fontBoost }
    private var captionSize: CGFloat { 12 + fontBoost }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: captionSize))
                .foregroundStyle(.blue.opacity(0.7))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    if let customer = entry.project?.customerName, !customer.isEmpty {
                        Text(customer)
                            .foregroundStyle(theme.textSecondary)
                        Text(" › ")
                            .foregroundStyle(theme.textTertiary)
                    }
                    Text(entry.project?.name ?? "—")
                        .foregroundStyle(theme.textPrimary)
                }
                .font(.system(size: bodySize))
                .lineLimit(1)

                Text(entry.task?.name ?? "—")
                    .font(.system(size: bodySize))
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)

                if isHovered {
                    HStack(spacing: 8) {
                        Text(String(localized: "hint.enterStart"))
                            .font(.system(size: captionSize, weight: .medium))
                    }
                    .foregroundStyle(theme.textTertiary)
                    .padding(.top, 2)
                }
            }

            Spacer()

            Text(String(format: "%.0fh", entry.hoursPerDay))
                .font(.system(size: captionSize, weight: .medium, design: .monospaced))
                .foregroundStyle(.blue.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? theme.hover : theme.surface)
        )
        .contentShape(Rectangle())
        .onHover { hovering in isHovered = hovering }
        .onTapGesture {
            guard let project = entry.project, let task = entry.task else { return }
            let searchEntry = SearchEntry(
                projectId: project.id,
                taskId: task.id,
                customerName: project.customerName ?? "",
                projectName: project.name,
                taskName: task.name
            )
            onStartEntry?(searchEntry)
        }
    }
}

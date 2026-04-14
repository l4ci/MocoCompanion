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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var bodySize: CGFloat { 14 + fontBoost }
    private var captionSize: CGFloat { 12 + fontBoost }

    init(appState: AppState, onTabSwitch: @escaping () -> Void = {}, onTypeToSearch: ((String) -> Void)? = nil, onStartEntry: ((SearchEntry) -> Void)? = nil) {
        self.appState = appState
        self.onTabSwitch = onTabSwitch
        self.onTypeToSearch = onTypeToSearch
        self.onStartEntry = onStartEntry
        let viewModel = TodayViewModel(
            timerService: appState.timerService,
            activityService: appState.activityService,
            planningStore: appState.planningStore,
            deleteUndoManager: appState.deleteUndoManager,
            favoritesManager: appState.favoritesManager
        )
        viewModel.syncState = appState.syncState
        self._vm = State(initialValue: viewModel)
    }

    // DaySelection extracted to DaySelection.swift for test target independence

    var body: some View {
        VStack(spacing: 0) {
            // Yesterday under-booking warning — visible in Log view
            if let warning = appState.yesterdayService.warning {
                YesterdayBannerView(warning: warning, onDismiss: { appState.yesterdayService.warning = nil })
            }

            dayToggle

            if let absence = vm.absence(for: vm.selectedDay.dateString) {
                absenceBanner(absence)
            }

            if vm.isTomorrow {
                tomorrowView
            } else if vm.sortedActivities.isEmpty && (vm.selectedDay != .today || vm.unplannedTasks.isEmpty) {
                TodayEmptyState(isYesterday: vm.isYesterday)
            } else {
                if !vm.sortedActivities.isEmpty {
                    activitiesList
                }

                if vm.selectedDay == .today && !vm.unplannedTasks.isEmpty {
                    UnplannedTasksSection(
                        tasks: vm.unplannedTasks,
                        timerService: vm.timerService,
                        selectedIndex: vm.isUnplannedSelected ? vm.selectedIndex - vm.sortedActivities.count : nil
                    )
                }

                if !vm.isTomorrow {
                    TodayStatsFooter(
                        totalHours: vm.isYesterday ? vm.yesterdayTotalHours : vm.todayTotalHours,
                        billablePercentage: vm.isYesterday ? vm.yesterdayBillablePercentage : vm.todayBillablePercentage,
                        entryCount: vm.sortedActivities.count
                    )
                }
            }

            // Undo toast — shown after deleting an entry
            if let pending = vm.pendingDelete {
                UndoToastView(
                    projectName: pending.activity.projectName,
                    onUndo: { vm.undoDelete() }
                )
            }
        }
        .focusable()
        .focused($listFocused)
        .focusEffectDisabled()
        .task(id: refreshId) {
            // Wait for session to establish userId before fetching — prevents
            // returning all-users data for accounts with elevated permissions.
            if appState.session.currentUserId == nil {
                for _ in 0..<50 { // up to 5 seconds
                    do { try await Task.sleep(for: .milliseconds(100)) }
                    catch { return }
                    if appState.session.currentUserId != nil { break }
                }
            }
            guard !Task.isCancelled else { return }
            await vm.refreshTodayStats()
            guard !Task.isCancelled else { return }
            await vm.refreshYesterdayActivities()
            guard !Task.isCancelled else { return }
            await vm.refreshAllPlanning()
            guard !Task.isCancelled else { return }
            await vm.refreshAbsences()
            vm.lastSyncedAt = .now
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
        .onChange(of: vm.todayActivitiesVersion) {
            guard !vm.isYesterday else { return }
            vm.syncSelectionAfterDataChange()
        }
        .onChange(of: vm.yesterdayActivitiesVersion) {
            guard vm.isYesterday else { return }
            vm.syncSelectionAfterDataChange()
        }
        .onKeyPress(phases: .down) { press in
            // Clear hover on any key press — prevents two rows being highlighted
            // when the mouse cursor is hidden during typing.
            vm.hoveredActivityId = nil

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

            syncIndicator
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private var syncIndicator: some View {
        HStack(spacing: 4) {
            if let lastSync = vm.lastSyncedAt {
                // Isolate the per-second tick to this one label. SwiftUI
                // re-renders only the TimelineView closure, not any parent.
                TimelineView(.periodic(from: lastSync, by: 1)) { context in
                    Text(relativeTimeString(from: lastSync, to: context.date))
                        .font(.system(size: 10 + fontBoost))
                        .foregroundStyle(theme.textTertiary)
                }
            }

            Button {
                Task { await vm.refreshCurrentDay() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10 + fontBoost, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
                    .rotationEffect(vm.isRefreshing ? .degrees(360) : .zero)
                    .animation(vm.isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: vm.isRefreshing)
            }
            .buttonStyle(.plain)
            .disabled(vm.isRefreshing)
            .accessibilityLabel(String(localized: "sync.refresh"))
        }
    }

    /// Format a Date into a compact relative string: "now", "30s", "2m", "1h".
    /// Accepts an explicit `now` so callers inside a `TimelineView` can pass
    /// the frame's context date instead of allocating `Date()` every call.
    private func relativeTimeString(from date: Date, to now: Date = .now) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 5 { return String(localized: "sync.now") }
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        return "\(hours)h"
    }

    // MARK: - Absence Banner

    private func absenceBanner(_ schedule: MocoSchedule) -> some View {
        let info = AbsenceStyle.resolve(schedule)

        return HStack(spacing: 10) {
            Image(systemName: info.icon)
                .font(.system(size: 18 + fontBoost, weight: .light))
                .foregroundStyle(info.color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(schedule.assignment.name)
                    .font(.system(size: bodySize, weight: .medium))
                    .foregroundStyle(theme.textPrimary)

                if let detail = info.detail(schedule: schedule) {
                    Text(detail)
                        .font(.system(size: captionSize))
                        .foregroundStyle(theme.textSecondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(info.color.opacity(0.08))
    }

    // MARK: - Tomorrow View

    private var tomorrowView: some View {
        VStack(spacing: 0) {
            if vm.tomorrowPlanningEntries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "sun.horizon")
                        .font(.system(size: 28 + fontBoost, weight: .light))
                        .foregroundStyle(theme.textTertiary.opacity(0.7))
                        .frame(height: 36)
                    Text(String(localized: "tomorrow.noPlanning"))
                        .font(.system(size: bodySize, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
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
                    ForEach(Array(vm.tomorrowPlanningEntries.enumerated()), id: \.element.id) { index, entry in
                        tomorrowPlanningRow(entry, index: index)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)

                let totalPlanned = vm.tomorrowPlanningEntries.reduce(0.0) { $0 + $1.hoursPerDay }
                HStack {
                    Spacer()
                    Text(String(localized: "tomorrow.hoursPlanned \(Int(totalPlanned.rounded()))"))
                        .font(.system(size: captionSize, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
        }
    }

    private func tomorrowPlanningRow(_ entry: MocoPlanningEntry, index: Int) -> some View {
        TomorrowPlanningRowView(
            entry: entry,
            isSelected: index == vm.selectedIndex,
            onStartEntry: onStartEntry,
            onHover: { hovering in
                if hovering { vm.selectedIndex = index }
            }
        )
    }

    // MARK: - Activities List

    private var activitiesList: some View {
        // Read dataVersion so @Observable triggers re-render on data changes
        let _ = vm.dataVersion
        // Build the planned-hours lookup once per render — previously each
        // row did an O(n) filter over planningStore entries, yielding
        // quadratic cost over the whole list. See audit P2-3.
        let plannedMap: [String: Double] = vm.isYesterday ? [:] : vm.buildPlannedHoursMap()
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(vm.sortedActivities.enumerated()), id: \.element.id) { index, activity in
                        TodayActivityRow(
                            activity: activity,
                            index: index,
                            isSelected: index == vm.selectedIndex,
                            isHovered: vm.hoveredActivityId == activity.id,
                            isRunning: !vm.isYesterday && activity.isTimerRunning,
                            isPaused: !vm.isYesterday && vm.isPausedActivity(activity),
                            shortcutIndex: vm.shortcutIndex(for: index),
                            isYesterday: vm.isYesterday,
                            plannedHours: plannedMap["\(activity.projectId)-\(activity.taskId)"],
                            projects: appState.catalog.projects,
                            budgetService: appState.budgetService,
                            editingActivityId: $vm.editingActivityId,
                            deletingActivityId: $vm.deletingActivityId,
                            descriptionDraft: $descriptionDraft,
                            hoursDraft: $hoursDraft,
                            hoveredActivityId: $vm.hoveredActivityId,
                            activityService: vm.activityService,
                            deleteUndoManager: vm.deleteUndoManager,
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
                        .id(activity.id)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
            }
            .frame(idealHeight: 300, maxHeight: 500)
            .id(vm.selectedDay)
            .onChange(of: vm.selectedActivityId) { _, newId in
                if let newId {
                    animateAccessibly(reduceMotion, .easeOut(duration: Theme.Motion.fast)) {
                        proxy.scrollTo(newId, anchor: .center)
                    }
                }
            }
        }
    }

}

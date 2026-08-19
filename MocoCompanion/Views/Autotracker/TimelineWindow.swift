import SwiftUI

/// Root SwiftUI view for the Autotracker window.
/// Shows date navigation at top, a placeholder content area (replaced by TimelinePaneView in T03),
/// and a status bar at the bottom with sync state and entry count.
struct TimelineWindow: View {
    @State private var viewModel: TimelineViewModel
    let projectCatalog: ProjectCatalog
    let autotracker: Autotracker
    var favoritesManager: FavoritesManager?
    var descriptionRequired: Bool = false
    /// Shared undo manager — when non-nil, deletes show a bottom toaster
    /// with an Undo action for 5 seconds before the Moco API call fires.
    var deleteUndoManager: DeleteUndoManager?
    /// Settings reference for feature flags (e.g. rulesEnabled). Optional
    /// so test harnesses that don't wire settings still compile.
    var settings: SettingsStore?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.entryFontSizeBoost) private var fontBoost
    /// Derived from the window's actual color scheme rather than
    /// `@Environment(\.theme)` — the theme environment key defaults
    /// to light and isn't set above this view; `.withTheme()` inside
    /// body only reaches child view structs, not `self` properties.
    private var theme: Theme { Theme(colorScheme: colorScheme) }
    @State private var showRuleList = false

    init(shadowEntryStore: ShadowEntryStore, syncState: SyncState, projectCatalog: ProjectCatalog, autotracker: Autotracker, workdayStartHour: Int = 8, workdayEndHour: Int = 17, descriptionRequired: Bool = false, onEntryChanged: (() async -> Void)? = nil) {
        let vm = TimelineViewModel(
            shadowEntryStore: shadowEntryStore,
            autotracker: autotracker,
            syncState: syncState,
            workdayStartHour: workdayStartHour,
            workdayEndHour: workdayEndHour
        )
        vm.onEntryChanged = onEntryChanged
        _viewModel = State(initialValue: vm)
        self.projectCatalog = projectCatalog
        self.autotracker = autotracker
        self.descriptionRequired = descriptionRequired
    }

    /// Init with a pre-built ViewModel (allows external date navigation).
    init(viewModel: TimelineViewModel, syncState: SyncState, projectCatalog: ProjectCatalog, autotracker: Autotracker, favoritesManager: FavoritesManager? = nil, descriptionRequired: Bool = false, deleteUndoManager: DeleteUndoManager? = nil, settings: SettingsStore? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.projectCatalog = projectCatalog
        self.autotracker = autotracker
        self.favoritesManager = favoritesManager
        self.descriptionRequired = descriptionRequired
        self.deleteUndoManager = deleteUndoManager
        self.settings = settings
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: date nav + sync status
            DateNavigationView(viewModel: viewModel)

            Divider()

            // Timeline content. Keep the pane rendered across subsequent
            // loadData() calls so ScrollView scroll position survives —
            // otherwise the view unmounts/remounts on every refresh
            // (drag-drop, sync, resize) and the user snaps back to the
            // top. The full-screen "Loading…" branch is reserved for the
            // very first load before any data has arrived.
            if viewModel.isLoading && viewModel.shadowEntries.isEmpty && viewModel.timeSlots.isEmpty {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Text("Loading...")
                    .font(.system(size: Theme.FontSize.body + fontBoost))
                    .foregroundStyle(theme.textTertiary)
                Spacer()
            } else {
                TimelinePaneView(
                    positionedEntries: viewModel.positionedEntries,
                    unpositionedEntries: viewModel.unpositionedEntries,
                    selectedDate: viewModel.selectedDate,
                    isToday: viewModel.isToday,
                    viewModel: viewModel,
                    projectCatalog: projectCatalog,
                    favoritesManager: favoritesManager,
                    descriptionRequired: descriptionRequired
                )
            }

            // Footer stats
            timelineStatsFooter
        }
        .overlay(alignment: .bottom) {
            if let manager = deleteUndoManager, manager.pendingDelete != nil {
                undoToaster(manager: manager)
                    .padding(.bottom, 70) // clear the stats footer
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // 0.2s doesn't match a Theme.Motion token (0.18 standard / 0.30 slow) — left as-is rather than retuning.
        .animation(.easeInOut(duration: 0.2), value: deleteUndoManager?.pendingDelete?.activity.id)
        .onKeyPress(.leftArrow) {
            viewModel.selectPreviousDay()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            if !viewModel.isToday {
                viewModel.selectNextDay()
                return .handled
            }
            return .ignored
        }
        .preferredColorScheme(Theme.colorScheme(from: settings?.appearance ?? ""))
        .environment(\.entryFontSizeBoost, CGFloat(settings?.entryFontSizeBoost ?? 0))
        .withTheme(colorScheme: colorScheme)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                SyncStatusLabel(lastSyncedAt: viewModel.lastSyncedAt)
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await viewModel.refreshData() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Sync with Moco (⌘R)")
                .accessibilityLabel("Sync with Moco")
                .keyboardShortcut("r", modifiers: .command)
                .disabled(viewModel.isRefreshing || viewModel.isSyncing)
            }
            if settings?.rulesEnabled == true {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showRuleList = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .help("Manage Rules")
                    .accessibilityLabel("Manage Rules")
                }
            }
        }
        .sheet(isPresented: $showRuleList) {
            RuleListView(
                autotracker: autotracker,
                projectCatalog: projectCatalog,
                onDismiss: { showRuleList = false }
            )
            .preferredColorScheme(Theme.colorScheme(from: settings?.appearance ?? ""))
            .withTheme(colorScheme: colorScheme)
        }
        .task {
            // Load local data first so the UI has something to show,
            // then trigger a real sync so the toolbar "last synced"
            // label stamps on window open (matches the main panel's
            // TodayView.task behaviour).
            await viewModel.loadData()
            await viewModel.refreshData()
        }
        .task {
            // Auto-refresh app activity every 60 seconds so the timeline
            // stays current while the window is open. The "synced Ns ago"
            // toolbar label ticks independently inside SyncStatusLabel, so
            // this loop no longer needs a 1-second cadence.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) }
                catch { break }
                await viewModel.loadData()
            }
        }
        .onChange(of: viewModel.selectedDate) {
            Task {
                await viewModel.loadData()
            }
        }
    }

    fileprivate static func relativeTimeString(since date: Date) -> String {
        let seconds = Int(Date.now.timeIntervalSince(date))
        if seconds < 5 { return String(localized: "sync.now") }
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        return "\(hours)h"
    }

    // MARK: - Stats Footer

    private var timelineStatsFooter: some View {
        VStack(spacing: 0) {
            theme.divider.frame(height: 1)

            HStack(spacing: 8) {
                statCard(
                    label: String(localized: "stats.total"),
                    value: "\(viewModel.totalHours.formatted(.number.precision(.fractionLength(1))))h",
                    accent: viewModel.totalHours >= 8.0 ? .green : nil
                )
                statCard(
                    label: String(localized: "stats.billable"),
                    value: "\(viewModel.billablePercentage.formatted(.number.precision(.fractionLength(0))))%"
                )
                statCard(
                    label: String(localized: "stats.entries"),
                    value: "\(viewModel.shadowEntries.count)"
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Undo Toaster

    /// Bottom-anchored toast shown for 5 seconds after a delete, giving
    /// the user a chance to undo before the deletion is committed to
    /// Moco. Subscribes to `DeleteUndoManager.pendingDelete`.
    private func undoToaster(manager: DeleteUndoManager) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "trash")
                .foregroundStyle(theme.textSecondary)
            Text("Entry deleted")
                .font(.system(size: Theme.FontSize.body + fontBoost, weight: .medium))
                .foregroundStyle(theme.textPrimary)
            Spacer(minLength: 12)
            Button("Undo") {
                manager.undoDelete()
            }
            .buttonStyle(.plain)
            .font(.system(size: Theme.FontSize.body + fontBoost, weight: .semibold))
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .fill(theme.surfaceElevated)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .stroke(theme.textTertiary.opacity(0.15), lineWidth: 1)
        }
        .frame(maxWidth: 360)
    }

    // MARK: - Stat Card

    private func statCard(label: String, value: String, accent: Color? = nil) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: Theme.FontSize.footnote + fontBoost, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.3)
            Text(value)
                .font(.system(size: 18 + fontBoost, weight: .semibold, design: .rounded))
                .foregroundStyle(accent ?? theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.statCardBackground)
        )
    }

}

// MARK: - Sync Status Label

/// Toolbar label showing "synced N s ago". Owns its own 1-second
/// periodic timer so only this Text re-renders each tick — isolated
/// from `TimelineWindow.body`, which previously held the tick in a
/// `@State` var read via `let _ = syncLabelTick`, forcing the entire
/// window body (including `TimelinePaneView`'s layout computation) to
/// re-render every second just to keep this label current.
private struct SyncStatusLabel: View {
    let lastSyncedAt: Date?

    @Environment(\.theme) private var theme
    @Environment(\.entryFontSizeBoost) private var fontBoost
    @Environment(\.timelineActive) private var timelineActive

    var body: some View {
        Group {
            if let lastSyncedAt {
                if timelineActive {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        label(TimelineWindow.relativeTimeString(since: lastSyncedAt))
                    }
                } else {
                    // Static fallback when the host sets timelineActive to
                    // false (the panel does; the standalone Timeline window
                    // currently leaves it at the default `true`, so here the
                    // periodic branch runs whenever the window exists).
                    label(TimelineWindow.relativeTimeString(since: lastSyncedAt))
                }
            } else {
                Text(String(localized: "Not synced"))
                    .font(.system(size: Theme.FontSize.footnote + fontBoost))
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(.leading, 8)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: Theme.FontSize.footnote + fontBoost))
            .foregroundStyle(theme.textSecondary)
            .monospacedDigit()
    }
}

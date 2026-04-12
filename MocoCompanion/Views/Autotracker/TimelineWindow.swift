import SwiftUI

/// Root SwiftUI view for the Autotracker window.
/// Shows date navigation at top, a placeholder content area (replaced by TimelinePaneView in T03),
/// and a status bar at the bottom with sync state and entry count.
struct TimelineWindow: View {
    @State private var viewModel: TimelineViewModel
    let projectCatalog: ProjectCatalog
    let autotracker: Autotracker
    var descriptionRequired: Bool = false
    /// Shared undo manager — when non-nil, deletes show a bottom toaster
    /// with an Undo action for 5 seconds before the Moco API call fires.
    var deleteUndoManager: DeleteUndoManager?
    /// Settings reference for feature flags (e.g. rulesEnabled). Optional
    /// so test harnesses that don't wire settings still compile.
    var settings: SettingsStore?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.theme) private var theme
    @State private var showRuleList = false
    @State private var syncLabelTick = Date.now

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
    init(viewModel: TimelineViewModel, syncState: SyncState, projectCatalog: ProjectCatalog, autotracker: Autotracker, descriptionRequired: Bool = false, deleteUndoManager: DeleteUndoManager? = nil, settings: SettingsStore? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.projectCatalog = projectCatalog
        self.autotracker = autotracker
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
            if viewModel.isLoading && viewModel.shadowEntries.isEmpty && viewModel.appUsageBlocks.isEmpty {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Text("Loading...")
                    .font(.system(size: Theme.FontSize.body))
                    .foregroundStyle(theme.textTertiary)
                Spacer()
            } else {
                TimelinePaneView(
                    positionedEntries: viewModel.positionedEntries,
                    unpositionedEntries: viewModel.unpositionedEntries,
                    appUsageBlocks: viewModel.appUsageBlocks,
                    selectedDate: viewModel.selectedDate,
                    isToday: viewModel.isToday,
                    viewModel: viewModel,
                    projectCatalog: projectCatalog,
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
        .animation(.easeInOut(duration: 0.2), value: deleteUndoManager?.pendingDelete?.activity.id)
        .withTheme(colorScheme: colorScheme)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                let _ = syncLabelTick
                Group {
                    if let lastSync = viewModel.lastSyncedAt {
                        Text(Self.relativeTimeString(since: lastSync))
                            .font(.system(size: Theme.FontSize.footnote))
                            .foregroundStyle(theme.textTertiary)
                            .monospacedDigit()
                    } else {
                        Text(String(localized: "Not synced"))
                            .font(.system(size: Theme.FontSize.footnote))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .padding(.leading, 8)
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
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) }
                catch { break }
                syncLabelTick = .now
            }
        }
        .onChange(of: viewModel.selectedDate) {
            Task {
                await viewModel.loadData()
            }
        }
    }

    private static func relativeTimeString(since date: Date) -> String {
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
                .font(.system(size: Theme.FontSize.body, weight: .medium))
                .foregroundStyle(theme.textPrimary)
            Spacer(minLength: 12)
            Button("Undo") {
                manager.undoDelete()
            }
            .buttonStyle(.plain)
            .font(.system(size: Theme.FontSize.body, weight: .semibold))
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
                .font(.system(size: Theme.FontSize.footnote, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.3)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
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

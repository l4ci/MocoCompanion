import SwiftUI

/// Root SwiftUI view for the Autotracker window.
/// Shows date navigation at top, a placeholder content area (replaced by TimelinePaneView in T03),
/// and a status bar at the bottom with sync state and entry count.
struct TimelineWindow: View {
    @State private var viewModel: TimelineViewModel
    let projectCatalog: ProjectCatalog
    let autotracker: Autotracker
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.theme) private var theme
    @State private var showRuleList = false

    init(shadowEntryStore: ShadowEntryStore, syncState: SyncState, projectCatalog: ProjectCatalog, autotracker: Autotracker) {
        let vm = TimelineViewModel(
            shadowEntryStore: shadowEntryStore,
            autotracker: autotracker,
            syncState: syncState
        )
        _viewModel = State(initialValue: vm)
        self.projectCatalog = projectCatalog
        self.autotracker = autotracker
    }

    var body: some View {
        VStack(spacing: 0) {
            DateNavigationView(viewModel: viewModel)

            Divider()

            // Timeline content
            if viewModel.isLoading {
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
                    projectCatalog: projectCatalog
                )
            }

            Divider()

            // Status bar
            HStack {
                if let lastSync = viewModel.syncState.lastSyncedAt {
                    Text("Synced \(Self.relativeTime(from: lastSync))")
                        .font(.system(size: Theme.FontSize.caption))
                        .foregroundStyle(theme.textTertiary)
                } else {
                    Text("Not synced")
                        .font(.system(size: Theme.FontSize.caption))
                        .foregroundStyle(theme.textTertiary)
                }

                Spacer()

                Text("\(viewModel.shadowEntries.count) entries")
                    .font(.system(size: Theme.FontSize.caption))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
        .withTheme(colorScheme: colorScheme)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showRuleList = true
                } label: {
                    Image(systemName: "list.bullet")
                }
                .help("Manage Rules")
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
            await viewModel.loadData()
        }
        .onChange(of: viewModel.selectedDate) {
            Task {
                await viewModel.loadData()
            }
        }
    }

    private static func relativeTime(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }
}

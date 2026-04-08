import AppKit
import Foundation
import os

/// Central app state observable by SwiftUI views.
/// Thin composition root that wires services together and forwards to
/// ProjectCatalog (project list, search index) and SessionManager (user identity, sync).
@Observable
@MainActor
final class AppState {
    private let logger = Logger(category: "AppState")

    let catalog: ProjectCatalog
    let session: SessionManager

    let settings: SettingsStore
    let favoritesManager: FavoritesManager
    let recencyTracker: RecencyTracker
    let recentEntriesTracker: RecentEntriesTracker
    let descriptionStore: DescriptionStore
    let timerService: TimerService
    let activityService: ActivityService
    let planningStore: PlanningStore
    let deleteUndoManager: DeleteUndoManager
    let notificationDispatcher: NotificationDispatcher
    let budgetService: BudgetService
    let monitorEngine: MonitorEngine
    let networkMonitor: NetworkMonitor
    let entryQueue: EntryQueue

    let yesterdayService: YesterdayService

    /// Project IDs that are relevant for budget monitoring: today's tracked activities,
    /// today's planned entries, favorites, and recent entries. Much smaller than all
    /// assigned projects — avoids hitting the Moco API rate limit on budget refresh.
    var relevantBudgetProjectIds: [Int] {
        var ids = Set<Int>()

        // Today's tracked activities
        for activity in activityService.todayActivities {
            ids.insert(activity.project.id)
        }

        // Today's planning entries
        for entry in planningStore.todayPlanningEntries {
            if let projectId = entry.project?.id { ids.insert(projectId) }
        }

        // Favorites
        for fav in favoritesManager.favorites {
            ids.insert(fav.projectId)
        }

        // Recent entries
        for recent in recentEntriesTracker.entries {
            ids.insert(recent.projectId)
        }

        return Array(ids)
    }

    /// Fuzzy search over flattened project/task entries, boosted by recency.
    func search(query: String) -> [FuzzyMatcher.Match] {
        FuzzyMatcher.search(query: query, in: catalog.searchEntries, recencyScores: recencyTracker.allScores())
    }

    /// Build a client from current settings. Returns nil if not configured.
    func makeClient() -> (any MocoClientProtocol)? {
        guard settings.isConfigured else { return nil }
        return MocoClient(subdomain: settings.subdomain, apiKey: settings.apiKey, rateGate: _rateGate)
    }

    init(
        settings: SettingsStore = SettingsStore(),
        favoritesManager: FavoritesManager = FavoritesManager(),
        recencyTracker: RecencyTracker = RecencyTracker(),
        recentEntriesTracker: RecentEntriesTracker = RecentEntriesTracker(),
        descriptionStore: DescriptionStore = DescriptionStore()
    ) {
        self.settings = settings
        self.favoritesManager = favoritesManager
        self.recencyTracker = recencyTracker
        self.recentEntriesTracker = recentEntriesTracker
        self.descriptionStore = descriptionStore

        let dispatcher = NotificationDispatcher(
            isEnabledCheck: { type in settings.isNotificationEnabled(type) }
        )
        self.notificationDispatcher = dispatcher

        // Shared mutable boxes replace the weakSelf pattern.
        // Services capture these boxes (stable lifetime); AppState pushes updates.
        let userIdBox = ValueBox<Int?>(nil)
        let searchEntriesBox = ValueBox<[SearchEntry]>([])

        // Shared rate gate — all API calls flow through this to stay within Moco's limits
        let rateGate = APIRateGate()

        let clientFactory: () -> (any MocoClientProtocol)? = { [weak settings] in
            guard let settings, settings.isConfigured else { return nil }
            return MocoClient(subdomain: settings.subdomain, apiKey: settings.apiKey, rateGate: rateGate)
        }

        let userIdProvider: () -> Int? = { userIdBox.value }

        let budgetSvc = BudgetService(
            clientFactory: clientFactory,
            userIdProvider: userIdProvider
        )
        self.budgetService = budgetSvc

        let sideEffects = TimerSideEffects(
            recencyTracker: recencyTracker,
            recentEntriesTracker: recentEntriesTracker,
            descriptionStore: descriptionStore,
            settings: settings,
            notificationDispatcher: dispatcher,
            searchEntriesProvider: { searchEntriesBox.value },
            budgetRefresh: { [weak budgetSvc] projectId in
                await budgetSvc?.refreshProject(projectId)
            },
            budgetStatusProvider: { [weak budgetSvc] projectId, taskId in
                budgetSvc?.status(projectId: projectId, taskId: taskId) ?? .empty
            }
        )

        // Create ActivityService first (TimerService needs it for sync target)
        let activitySvc = ActivityService(
            clientFactory: clientFactory,
            notificationDispatcher: dispatcher,
            userIdProvider: userIdProvider
        )
        self.activityService = activitySvc

        // Create TimerService with activity sync target (replaces TimerActivityCoordinator)
        let timerSvc = TimerService(
            clientFactory: clientFactory,
            userIdProvider: userIdProvider,
            activitySync: activitySvc
        )
        self.timerService = timerSvc

        // Wire timer events → side effects
        timerSvc.onEvent = { [weak sideEffects] event in sideEffects?.handle(event) }

        // Create PlanningStore — owns planning entries, absences, unplanned tasks
        let planningSvc = PlanningStore(
            clientFactory: clientFactory,
            userIdProvider: userIdProvider,
            todayActivitiesProvider: { [weak activitySvc] in activitySvc?.todayActivities ?? [] }
        )
        self.planningStore = planningSvc

        // Create DeleteUndoManager — owns delete lifecycle with undo support
        let deleteUndo = DeleteUndoManager(
            clientFactory: clientFactory,
            activityService: activitySvc,
            notificationDispatcher: dispatcher
        )
        self.deleteUndoManager = deleteUndo

        // Monitor engine — centralized polling, dedup, and dispatch for background monitors
        let engine = MonitorEngine(dispatcher: dispatcher)
        self.monitorEngine = engine
        self.networkMonitor = NetworkMonitor()
        self.entryQueue = EntryQueue()

        // Create extracted submodules
        let projectCatalog = ProjectCatalog()
        self.catalog = projectCatalog

        let sessionMgr = SessionManager(userIdBox: userIdBox)
        self.session = sessionMgr

        // Keep the search entries box in sync when catalog projects change
        searchEntriesBox.value = projectCatalog.searchEntries

        engine.register(BudgetDepletionMonitor(
            timerService: timerSvc,
            budgetService: budgetSvc
        ))

        engine.register(IdleReminderMonitor(
            timerService: timerSvc,
            activityService: activitySvc,
            settings: settings
        ))

        // Wire delete → timer: stop timer before deleting a timed activity
        deleteUndo.timerStopProvider = timerSvc

        // Wire usage recording for manual entries (recency, recent entries, descriptions)
        activitySvc.onUsageRecorded = { [weak sideEffects] projectId, taskId, description in
            sideEffects?.recordUsage(projectId: projectId, taskId: taskId, description: description)
        }

        self._searchEntriesBox = searchEntriesBox
        self._rateGate = rateGate

        // Yesterday service — owns warning state and threshold logic
        let yesterdaySvc = YesterdayService(
            settings: settings,
            clientFactory: clientFactory,
            userIdProvider: userIdProvider
        )
        self.yesterdayService = yesterdaySvc
        engine.register(yesterdaySvc, immediateFirstCheck: true)

        // Wire yesterday recheck: when local yesterday data changes (edit, delete),
        // immediately recompute the warning without waiting for the 10-minute poll.
        activitySvc.onYesterdayDataChanged = { [weak yesterdaySvc, weak activitySvc] in
            guard let yesterdaySvc, let activitySvc else { return }
            yesterdaySvc.recheckLocally(yesterdayActivities: activitySvc.yesterdayActivities)
        }

        // Wire network reconnect: sync queued entries + refresh data
        networkMonitor.onReconnect = { [weak self] in
            guard let self else { return }
            await self.fetchSession()
            await self.fetchProjects()
            await self.timerService.sync()
            await self.syncQueuedEntries()
        }
    }

    /// Mutable box captured by service closures. Updated when searchEntries changes.
    private let _searchEntriesBox: ValueBox<[SearchEntry]>
    /// Shared rate gate for all API calls.
    private let _rateGate: APIRateGate

    // MARK: - Delegated Methods

    /// Fetch the current user's ID from the Moco session endpoint.
    func fetchSession() async {
        await session.fetchSession(client: makeClient())
    }

    func fetchProjects() async {
        await catalog.fetchProjects(
            client: makeClient(),
            onError: { [weak self] error in self?.timerService.lastError = error },
            dispatcher: notificationDispatcher
        )
        _searchEntriesBox.value = catalog.searchEntries
    }

    /// Sync queued entries after reconnecting. Deduplicates against existing activities.
    func syncQueuedEntries() async {
        await session.syncQueuedEntries(
            queue: entryQueue,
            client: makeClient(),
            userId: session.currentUserId,
            dispatcher: notificationDispatcher,
            onSynced: { [weak self] in
                await self?.activityService.refreshTodayStats()
            }
        )
    }
}

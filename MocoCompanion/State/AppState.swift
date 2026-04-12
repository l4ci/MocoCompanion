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
    let offlineSyncService: OfflineSyncService
    let shadowEntryStore: ShadowEntryStore
    let syncEngine: SyncEngine
    let syncState: SyncState
    let autotracker: Autotracker

    let yesterdayService: YesterdayService
    let calendarService: CalendarService

    /// Project IDs that are relevant for budget monitoring: today's tracked activities,
    /// today's planned entries, favorites, and recent entries. Much smaller than all
    /// assigned projects — avoids hitting the Moco API rate limit on budget refresh.
    var relevantBudgetProjectIds: [Int] {
        var ids = Set<Int>()

        // Today's tracked activities
        for activity in activityService.todayActivities {
            ids.insert(activity.projectId)
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

        // --- Phase 1: Storage ---
        let storage = Self.buildStorage(settings: settings)
        self.shadowEntryStore = storage.shadowEntryStore
        self.syncState = storage.syncState
        self.syncEngine = storage.syncEngine
        self._searchEntriesBox = storage.searchEntriesBox
        self._rateGate = storage.rateGate

        // --- Phase 2: Domain catalog ---
        let domain = Self.buildDomain(
            clientFactory: storage.clientFactory,
            userIdProvider: storage.userIdProvider,
            userIdBox: storage.userIdBox
        )
        self.catalog = domain.projectCatalog
        self.session = domain.session
        self.budgetService = domain.budgetService

        // --- Phase 3: Time tracking ---
        let tracking = Self.buildTracking(
            clientFactory: storage.clientFactory,
            userIdProvider: storage.userIdProvider,
            recencyTracker: recencyTracker,
            recentEntriesTracker: recentEntriesTracker,
            descriptionStore: descriptionStore,
            settings: settings,
            dispatcher: dispatcher,
            searchEntriesBox: storage.searchEntriesBox,
            budgetService: domain.budgetService,
            shadowEntryStore: storage.shadowEntryStore,
            syncEngine: storage.syncEngine
        )
        self.activityService = tracking.activityService
        self.timerService = tracking.timerService
        self.planningStore = tracking.planningStore
        self.deleteUndoManager = tracking.deleteUndoManager

        // --- Phase 4: Monitoring ---
        let monitoring = Self.buildMonitoring(
            clientFactory: storage.clientFactory,
            userIdProvider: storage.userIdProvider,
            settings: settings,
            dispatcher: dispatcher,
            shadowEntryStore: storage.shadowEntryStore,
            timerService: tracking.timerService,
            activityService: tracking.activityService,
            budgetService: domain.budgetService
        )
        self.monitorEngine = monitoring.monitorEngine
        self.networkMonitor = monitoring.networkMonitor
        self.entryQueue = monitoring.entryQueue
        self.offlineSyncService = monitoring.offlineSyncService
        self.autotracker = monitoring.autotracker
        self.yesterdayService = monitoring.yesterdayService
        self.calendarService = monitoring.calendarService

        // --- Wire-ups that cross phase boundaries or capture self ---

        // When autotracker creates entries, refresh the Today panel so they appear
        self.autotracker.onEntryCreated = { [weak activitySvc = tracking.activityService] in
            await activitySvc?.refreshTodayStats()
        }

        // Keep the search entries box in sync when catalog projects change
        storage.searchEntriesBox.value = domain.projectCatalog.searchEntries

        // Wire delete → timer: stop timer before deleting a timed activity
        tracking.deleteUndoManager.timerStopProvider = tracking.timerService

        // Wire usage recording for manual entries (recency, recent entries, descriptions)
        tracking.activityService.usageRecorder = tracking.sideEffects

        // Wire yesterday recheck: when local yesterday data changes (edit, delete),
        // immediately recompute the warning without waiting for the 10-minute poll.
        tracking.activityService.yesterdayService = monitoring.yesterdayService

        // Wire network reconnect: sync queued entries + refresh data
        monitoring.networkMonitor.onReconnect = { [weak self] in
            guard let self else { return }
            await self.fetchSession()
            await self.fetchProjects()
            await self.timerService.sync()
            await self.syncQueuedEntries()
        }

        // Auto-detect "description required" from Moco validation errors.
        // The callback is invoked synchronously from the SyncEngine actor
        // (see SyncEngine.sync catch block), which is NOT the main actor.
        // Hop to main before touching @MainActor settings — using
        // `assumeIsolated` here would trap.
        storage.syncEngine.onDescriptionRequired = { [weak self] in
            Task { @MainActor in
                guard let self, !self.settings.descriptionRequired else { return }
                self.settings.descriptionRequired = true
                self.logger.info("Auto-detected: Moco requires non-empty descriptions")
            }
        }
    }

    /// Mutable box captured by service closures. Updated when searchEntries changes.
    private let _searchEntriesBox: ValueBox<[SearchEntry]>
    /// Shared rate gate for all API calls.
    private let _rateGate: APIRateGate

    // MARK: - Phase Helpers

    private struct StoragePhase {
        let shadowEntryStore: ShadowEntryStore
        let syncState: SyncState
        let syncEngine: SyncEngine
        let searchEntriesBox: ValueBox<[SearchEntry]>
        let rateGate: APIRateGate
        let clientFactory: () -> (any MocoClientProtocol)?
        let userIdProvider: () -> Int?
        let userIdBox: ValueBox<Int?>
    }

    private static func buildStorage(settings: SettingsStore) -> StoragePhase {
        let userIdBox = ValueBox<Int?>(nil)
        let searchEntriesBox = ValueBox<[SearchEntry]>([])
        let rateGate = APIRateGate()

        let clientFactory: () -> (any MocoClientProtocol)? = { [weak settings] in
            guard let settings, settings.isConfigured else { return nil }
            return MocoClient(subdomain: settings.subdomain, apiKey: settings.apiKey, rateGate: rateGate)
        }
        let userIdProvider: () -> Int? = { userIdBox.value }

        let appSupportURL = URL.applicationSupportDirectory
            .appendingPathComponent("MocoCompanion")
        try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        let sState = SyncState()
        let shadowStore: ShadowEntryStore
        do {
            let db = try SQLiteDatabase(path: appSupportURL.appendingPathComponent("shadow.db").path)
            shadowStore = try ShadowEntryStore(database: db)
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }

        // nonisolated(unsafe) suppresses the sending diagnostic — safe because
        // the closures only read Sendable values (String, Int, Bool) from settings/userIdBox.
        nonisolated(unsafe) let existingClientFactory = clientFactory
        nonisolated(unsafe) let existingUserIdProvider = userIdProvider
        let sEngine = SyncEngine(
            store: shadowStore,
            clientFactory: { existingClientFactory() as (any ActivityAPI & TimerAPI)? },
            userIdProvider: existingUserIdProvider,
            syncState: sState
        )

        return StoragePhase(
            shadowEntryStore: shadowStore,
            syncState: sState,
            syncEngine: sEngine,
            searchEntriesBox: searchEntriesBox,
            rateGate: rateGate,
            clientFactory: clientFactory,
            userIdProvider: userIdProvider,
            userIdBox: userIdBox
        )
    }

    private struct DomainPhase {
        let projectCatalog: ProjectCatalog
        let session: SessionManager
        let budgetService: BudgetService
    }

    private static func buildDomain(
        clientFactory: @escaping () -> (any MocoClientProtocol)?,
        userIdProvider: @escaping () -> Int?,
        userIdBox: ValueBox<Int?>
    ) -> DomainPhase {
        // Initialize catalog and session early — Swift requires all `let` properties
        // to be set before `self` can be captured in closures.
        let projectCatalog = ProjectCatalog()
        let sessionMgr = SessionManager(userIdBox: userIdBox)
        let budgetSvc = BudgetService(
            clientFactory: clientFactory,
            userIdProvider: userIdProvider
        )
        return DomainPhase(projectCatalog: projectCatalog, session: sessionMgr, budgetService: budgetSvc)
    }

    private struct TrackingPhase {
        let sideEffects: TimerSideEffects
        let activityService: ActivityService
        let timerService: TimerService
        let planningStore: PlanningStore
        let deleteUndoManager: DeleteUndoManager
    }

    private static func buildTracking(
        clientFactory: @escaping () -> (any MocoClientProtocol)?,
        userIdProvider: @escaping () -> Int?,
        recencyTracker: RecencyTracker,
        recentEntriesTracker: RecentEntriesTracker,
        descriptionStore: DescriptionStore,
        settings: SettingsStore,
        dispatcher: NotificationDispatcher,
        searchEntriesBox: ValueBox<[SearchEntry]>,
        budgetService: BudgetService,
        shadowEntryStore: ShadowEntryStore,
        syncEngine: SyncEngine
    ) -> TrackingPhase {
        let sideEffects = TimerSideEffects(
            recencyTracker: recencyTracker,
            recentEntriesTracker: recentEntriesTracker,
            descriptionStore: descriptionStore,
            settings: settings,
            notificationDispatcher: dispatcher,
            searchEntriesProvider: { searchEntriesBox.value },
            budgetRefresh: { [weak budgetService] projectId in
                await budgetService?.refreshProject(projectId)
            },
            budgetStatusProvider: { [weak budgetService] projectId, taskId in
                budgetService?.status(projectId: projectId, taskId: taskId) ?? .empty
            }
        )

        // Create ActivityService first (TimerService needs it for sync target)
        let activitySvc = ActivityService(
            clientFactory: clientFactory,
            notificationDispatcher: dispatcher,
            userIdProvider: userIdProvider
        )
        activitySvc.syncEngine = syncEngine

        // Create TimerService with activity sync target (replaces TimerActivityCoordinator)
        let timerSvc = TimerService(
            clientFactory: clientFactory,
            userIdProvider: userIdProvider,
            activitySync: activitySvc
        )

        // Wire timer events → side effects
        timerSvc.onEvent = { [weak sideEffects] event in sideEffects?.handle(event) }

        // Create PlanningStore — owns planning entries, absences, unplanned tasks
        let planningSvc = PlanningStore(
            clientFactory: clientFactory,
            userIdProvider: userIdProvider,
            todayActivitiesProvider: { [weak activitySvc] in activitySvc?.todayActivities ?? [] }
        )

        // Create DeleteUndoManager — owns delete lifecycle with undo support
        let deleteUndo = DeleteUndoManager(
            clientFactory: clientFactory,
            activityService: activitySvc,
            shadowEntryStore: shadowEntryStore,
            notificationDispatcher: dispatcher
        )

        return TrackingPhase(
            sideEffects: sideEffects,
            activityService: activitySvc,
            timerService: timerSvc,
            planningStore: planningSvc,
            deleteUndoManager: deleteUndo
        )
    }

    private struct MonitoringPhase {
        let monitorEngine: MonitorEngine
        let networkMonitor: NetworkMonitor
        let entryQueue: EntryQueue
        let offlineSyncService: OfflineSyncService
        let autotracker: Autotracker
        let yesterdayService: YesterdayService
        let calendarService: CalendarService
    }

    private static func buildMonitoring(
        clientFactory: @escaping () -> (any MocoClientProtocol)?,
        userIdProvider: @escaping () -> Int?,
        settings: SettingsStore,
        dispatcher: NotificationDispatcher,
        shadowEntryStore: ShadowEntryStore,
        timerService: TimerService,
        activityService: ActivityService,
        budgetService: BudgetService
    ) -> MonitoringPhase {
        // Monitor engine — centralized polling, dedup, and dispatch for background monitors
        let engine = MonitorEngine(dispatcher: dispatcher)
        let networkMonitor = NetworkMonitor()
        let entryQueue = EntryQueue()
        let offlineSyncService = OfflineSyncService(clientFactory: clientFactory)

        let appSupportURL = URL.applicationSupportDirectory
            .appendingPathComponent("MocoCompanion")
        let recordStore = AppRecordStore()
        let rStore: RuleStore
        do {
            let rulesDb = try SQLiteDatabase(path: appSupportURL.appendingPathComponent("rules.sqlite").path)
            rStore = try RuleStore(database: rulesDb)
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
        let autotracker = Autotracker(
            shadowEntryStore: shadowEntryStore,
            appRecordStore: recordStore,
            ruleStore: rStore,
            settings: settings
        )

        engine.register(BudgetDepletionMonitor(
            timerService: timerService,
            budgetService: budgetService
        ))

        engine.register(IdleReminderMonitor(
            timerService: timerService,
            activityService: activityService,
            settings: settings
        ))

        // Yesterday service — owns warning state and threshold logic
        let yesterdaySvc = YesterdayService(
            settings: settings,
            clientFactory: clientFactory,
            userIdProvider: userIdProvider
        )
        engine.register(yesterdaySvc, immediateFirstCheck: true)

        let calendarService = CalendarService()

        return MonitoringPhase(
            monitorEngine: engine,
            networkMonitor: networkMonitor,
            entryQueue: entryQueue,
            offlineSyncService: offlineSyncService,
            autotracker: autotracker,
            yesterdayService: yesterdaySvc,
            calendarService: calendarService
        )
    }

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
        guard let userId = session.currentUserId else { return }
        await offlineSyncService.sync(
            queue: entryQueue,
            userId: userId,
            onSynced: { [weak self] syncedCount in
                guard let self else { return }
                let message = String(localized: "offline.synced \(syncedCount)")
                self.notificationDispatcher.send(.projectsRefreshed, message: message)
                await self.activityService.refreshTodayStats()
            }
        )
    }
}

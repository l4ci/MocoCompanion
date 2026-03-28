import Foundation
import os

/// Central app state observable by SwiftUI views.
/// Owns project catalog, search, settings, and in-app notifications.
/// Timer lifecycle delegated to TimerService.
@Observable
@MainActor
final class AppState {
    private let logger = Logger(category: "AppState")

    let settings: SettingsStore
    let favoritesManager: FavoritesManager
    let recencyTracker: RecencyTracker
    let recentEntriesTracker: RecentEntriesTracker
    let descriptionStore: DescriptionStore
    let timerService: TimerService
    let activityService: ActivityService
    let notificationDispatcher: NotificationDispatcher
    let budgetService: BudgetService
    let monitorEngine: MonitorEngine
    private let coordinator: TimerActivityCoordinator

    var projects: [MocoProject] = [] {
        didSet {
            _searchEntries = nil
            _searchEntriesBox.value = searchEntries
        }
    }
    var isLoading = false
    var yesterdayWarning: YesterdayWarning?
    /// The authenticated user's Moco ID. Set on app launch via fetchSession().
    private(set) var currentUserId: Int?
    private(set) var currentUserProfile: MocoUserProfile?

    // MARK: - Cached Search Entries

    /// Cache invalidated when `projects` changes.
    private var _searchEntries: [SearchEntry]?

    /// Flattened search entries built from current projects. Cached until projects change.
    var searchEntries: [SearchEntry] {
        if let cached = _searchEntries { return cached }
        let entries = SearchEntry.from(projects: projects)
        _searchEntries = entries
        return entries
    }

    /// IDs of currently assigned projects. Used to drive budget refresh.
    var assignedProjectIds: [Int] { projects.map(\.id) }

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
        for entry in activityService.todayPlanningEntries {
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
        FuzzyMatcher.search(query: query, in: searchEntries, recencyScores: recencyTracker.allScores())
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

        // Create TimerService (no cross-service dependencies at init)
        let timerSvc = TimerService(
            clientFactory: clientFactory,
            sideEffects: sideEffects,
            userIdProvider: userIdProvider
        )
        self.timerService = timerSvc

        // Create ActivityService (no cross-service dependencies at init)
        let activitySvc = ActivityService(
            clientFactory: clientFactory,
            sideEffects: sideEffects,
            userIdProvider: userIdProvider
        )
        self.activityService = activitySvc

        // Monitor engine — centralized polling, dedup, and dispatch for background monitors
        let engine = MonitorEngine(dispatcher: dispatcher)
        self.monitorEngine = engine

        engine.register(BudgetDepletionMonitor(
            timerService: timerSvc,
            budgetService: budgetSvc
        ))

        engine.register(IdleReminderMonitor(
            timerService: timerSvc,
            activityService: activitySvc,
            settings: settings
        ))

        // Coordinator wires the cross-boundary callbacks between timer and activity services
        self.coordinator = TimerActivityCoordinator(timer: timerSvc, activities: activitySvc)
        self._userIdBox = userIdBox
        self._searchEntriesBox = searchEntriesBox
        self._rateGate = rateGate

        // Register yesterday check after all stored properties are initialized
        engine.register(YesterdayCheckManager(
            settings: settings,
            clientFactory: clientFactory,
            setWarning: { [weak self] warning in self?.yesterdayWarning = warning }
        ))
    }

    // MARK: - Shared State Boxes

    /// Mutable box captured by service closures. Updated when currentUserId changes.
    private let _userIdBox: ValueBox<Int?>
    /// Mutable box captured by service closures. Updated when searchEntries changes.
    private let _searchEntriesBox: ValueBox<[SearchEntry]>
    /// Shared rate gate for all API calls.
    private let _rateGate: APIRateGate

    // MARK: - Session

    /// Fetch the current user's ID from the Moco session endpoint.
    func fetchSession() async {
        guard let client = makeClient() else { return }
        do {
            let session = try await client.fetchSession()
            currentUserId = session.id
            _userIdBox.value = session.id
            logger.info("Session: userId=\(session.id)")

            // Fetch user profile for greeting + avatar
            let profile = try await client.fetchUserProfile(userId: session.id)
            currentUserProfile = profile
            logger.info("Profile: \(profile.firstname) \(profile.lastname)")
        } catch {
            logger.error("fetchSession failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Projects

    func fetchProjects() async {
        guard let client = makeClient() else {
            logger.warning("Cannot fetch projects — API not configured")
            timerService.lastError = .invalidConfiguration
            return
        }

        isLoading = true

        do {
            let fetched = try await client.fetchAssignedProjects()
            projects = fetched
            logger.info("Fetched \(fetched.count) projects")
            notificationDispatcher.send(.projectsRefreshed, message: "\(fetched.count) projects synced")
        } catch {
            let mocoError = MocoError.from(error)
            timerService.lastError = mocoError
            notificationDispatcher.send(.apiError, message: mocoError.errorDescription ?? "Unknown error")
            logger.error("fetchProjects failed: \(error.localizedDescription)")
            Task { await AppLogger.shared.app("fetchProjects failed: \(error.localizedDescription)", level: .error, context: "AppState") }
        }

        isLoading = false
    }
}

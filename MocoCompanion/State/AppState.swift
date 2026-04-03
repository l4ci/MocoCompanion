import AppKit
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
    let networkMonitor: NetworkMonitor
    let entryQueue: EntryQueue
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
    /// Cached avatar image — downloaded once after profile fetch. Nil if no avatar URL or download failed.
    private(set) var cachedAvatarImage: NSImage?

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
        self.networkMonitor = NetworkMonitor()
        self.entryQueue = EntryQueue()

        // Load cached projects for offline use
        let cached = ProjectCache.load()
        if !cached.isEmpty {
            projects = cached
        }

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
        // Use a closure that doesn't capture self during init — wire it afterward.
        var yesterdayWarningCallback: ((YesterdayWarning?) -> Void)?
        let yesterdayChecker = YesterdayCheckManager(
            settings: settings,
            clientFactory: clientFactory,
            userIdProvider: userIdProvider,
            setWarning: { warning in yesterdayWarningCallback?(warning) }
        )
        self._yesterdayChecker = yesterdayChecker

        // All stored properties now initialized — safe to capture [weak self]
        yesterdayWarningCallback = { [weak self] warning in self?.yesterdayWarning = warning }
        engine.register(yesterdayChecker, immediateFirstCheck: true)

        // Wire yesterday recheck: when local yesterday data changes (edit, delete),
        // immediately recompute the warning without waiting for the 10-minute poll.
        activitySvc.onYesterdayDataChanged = { [weak self] in
            self?.recheckYesterdayWarning()
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

    /// Reference to yesterday checker for local recheck on activity edits.
    private let _yesterdayChecker: YesterdayCheckManager

    // MARK: - Shared State Boxes

    /// Mutable box captured by service closures. Updated when currentUserId changes.
    private let _userIdBox: ValueBox<Int?>
    /// Mutable box captured by service closures. Updated when searchEntries changes.

    // MARK: - Yesterday Warning Recheck

    /// Recheck yesterday warning using local data. Called after activity edits/deletes
    /// that change yesterday's hours — clears the banner immediately if the threshold is met,
    /// without waiting for the 10-minute polling cycle.
    func recheckYesterdayWarning() {
        guard let warning = yesterdayWarning else { return }
        let yesterdayHours = activityService.yesterdayActivities.reduce(0.0) { $0 + $1.hours }
        let ratio = yesterdayHours / warning.expectedHours
        if ratio >= YesterdayCheckManager.threshold {
            yesterdayWarning = nil
        } else {
            // Update the displayed hours in case they changed
            yesterdayWarning = YesterdayWarning(bookedHours: yesterdayHours, expectedHours: warning.expectedHours)
        }
    }
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

            // Pre-download avatar so tab switches don't flash
            if let urlStr = profile.avatarUrl, let url = URL(string: urlStr) {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let image = NSImage(data: data) {
                        cachedAvatarImage = image
                        logger.info("Avatar image cached")
                    }
                } catch {
                    logger.warning("Avatar download failed: \(error.localizedDescription)")
                }
            }
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
            ProjectCache.save(fetched)
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

    // MARK: - Offline Sync

    /// Sync queued entries after reconnecting. Deduplicates against existing activities.
    func syncQueuedEntries() async {
        guard !entryQueue.isEmpty else { return }
        guard let client = makeClient() else { return }
        guard let userId = currentUserId else { return }

        logger.info("Syncing \(self.entryQueue.count) queued entries")

        var syncedCount = 0

        for entry in entryQueue.entries {
            // Fetch existing activities for the entry's date to deduplicate
            do {
                let existing = try await client.fetchActivities(from: entry.date, to: entry.date, userId: userId)

                // Check for duplicates: same project + task + description
                let isDuplicate = existing.contains { activity in
                    activity.project.id == entry.projectId
                    && activity.task.id == entry.taskId
                    && activity.description == entry.description
                }

                if isDuplicate {
                    logger.info("Skipping duplicate queued entry for \(entry.projectName)")
                    entryQueue.remove(id: entry.id)
                    continue
                }

                // Create the entry
                _ = try await client.createActivity(
                    date: entry.date,
                    projectId: entry.projectId,
                    taskId: entry.taskId,
                    description: entry.description,
                    seconds: entry.seconds,
                    tag: entry.tag
                )
                entryQueue.remove(id: entry.id)
                syncedCount += 1
                logger.info("Synced queued entry for \(entry.projectName)")
            } catch {
                logger.error("Failed to sync queued entry: \(error.localizedDescription)")
                break // Stop on first error — don't burn API quota
            }
        }

        if syncedCount > 0 {
            let message = String(localized: "offline.synced \(syncedCount)")
            notificationDispatcher.send(.projectsRefreshed, message: message)
            // Refresh today's data to show synced entries
            await activityService.refreshTodayStats()
        }
    }
}

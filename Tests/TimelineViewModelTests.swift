import Testing
import Foundation
@testable import MocoCompanion

@Suite("TimelineViewModel")
struct TimelineViewModelTests {

    // MARK: - Date Navigation

    @Test("selectPreviousDay moves back one day")
    @MainActor
    func selectPreviousDay() async throws {
        let vm = try makeViewModel()
        let today = Calendar.current.startOfDay(for: Date())
        vm.selectedDate = today

        vm.selectPreviousDay()

        let expected = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        #expect(vm.selectedDate == expected)
    }

    @Test("selectNextDay moves forward one day")
    @MainActor
    func selectNextDay() async throws {
        let vm = try makeViewModel()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!
        vm.selectedDate = yesterday

        vm.selectNextDay()

        let today = Calendar.current.startOfDay(for: Date())
        #expect(vm.selectedDate == today)
    }

    @Test("selectNextDay does nothing when already today")
    @MainActor
    func selectNextDayBlockedOnToday() async throws {
        let vm = try makeViewModel()
        let today = Calendar.current.startOfDay(for: Date())
        vm.selectedDate = today

        vm.selectNextDay()

        #expect(vm.selectedDate == today)
    }

    @Test("selectToday resets to today")
    @MainActor
    func selectToday() async throws {
        let vm = try makeViewModel()
        let pastDate = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        vm.selectedDate = Calendar.current.startOfDay(for: pastDate)

        vm.selectToday()

        #expect(vm.selectedDate == Calendar.current.startOfDay(for: Date()))
    }

    @Test("selectDate sets specific date")
    @MainActor
    func selectDate() async throws {
        let vm = try makeViewModel()
        let target = Calendar.current.date(byAdding: .day, value: -3, to: Date())!

        vm.selectDate(target)

        #expect(vm.selectedDate == Calendar.current.startOfDay(for: target))
    }

    // MARK: - App Usage Block Merging

    @Test("merges adjacent same-app records within 5-minute gap")
    func mergesSameAppWithinGap() {
        let base = Date()
        let records = [
            makeAppRecord(bundleId: "com.app.a", name: "App A", timestamp: base, duration: 60),
            makeAppRecord(bundleId: "com.app.a", name: "App A", timestamp: base.addingTimeInterval(120), duration: 60),
            makeAppRecord(bundleId: "com.app.a", name: "App A", timestamp: base.addingTimeInterval(240), duration: 60),
        ]

        let blocks = AppUsageBlock.merge(records)

        #expect(blocks.count == 1)
        #expect(blocks[0].appBundleId == "com.app.a")
        #expect(blocks[0].recordCount == 3)
        #expect(blocks[0].durationSeconds == 180)
    }

    @Test("does NOT merge records with gap exceeding 5 minutes")
    func doesNotMergeWithLargeGap() {
        let base = Date()
        let records = [
            makeAppRecord(bundleId: "com.app.a", name: "App A", timestamp: base, duration: 60),
            // Gap of 400 seconds (>300s threshold) from end of first record
            makeAppRecord(bundleId: "com.app.a", name: "App A", timestamp: base.addingTimeInterval(460), duration: 60),
        ]

        let blocks = AppUsageBlock.merge(records)

        #expect(blocks.count == 2)
        #expect(blocks[0].recordCount == 1)
        #expect(blocks[1].recordCount == 1)
    }

    @Test("does NOT merge different apps even within gap")
    func doesNotMergeDifferentApps() {
        let base = Date()
        let records = [
            makeAppRecord(bundleId: "com.app.a", name: "App A", timestamp: base, duration: 60),
            makeAppRecord(bundleId: "com.app.b", name: "App B", timestamp: base.addingTimeInterval(120), duration: 60),
        ]

        let blocks = AppUsageBlock.merge(records)

        #expect(blocks.count == 2)
        #expect(blocks[0].appBundleId == "com.app.a")
        #expect(blocks[1].appBundleId == "com.app.b")
    }

    @Test("empty records produces empty blocks")
    func emptyRecords() {
        let blocks = AppUsageBlock.merge([])
        #expect(blocks.isEmpty)
    }

    @Test("interleaved apps create separate blocks")
    func interleavedApps() {
        let base = Date()
        let records = [
            makeAppRecord(bundleId: "com.app.a", name: "App A", timestamp: base, duration: 60),
            makeAppRecord(bundleId: "com.app.b", name: "App B", timestamp: base.addingTimeInterval(70), duration: 60),
            makeAppRecord(bundleId: "com.app.a", name: "App A", timestamp: base.addingTimeInterval(140), duration: 60),
        ]

        let blocks = AppUsageBlock.merge(records)

        #expect(blocks.count == 3)
        #expect(blocks[0].appBundleId == "com.app.a")
        #expect(blocks[1].appBundleId == "com.app.b")
        #expect(blocks[2].appBundleId == "com.app.a")
    }

    // MARK: - Data Loading: pendingDelete Filtering

    @Test("pendingDelete entries are filtered from display")
    @MainActor
    func filtersPendingDelete() async throws {
        let store = try makeShadowEntryStore()
        let today = TimelineViewModel.dateString(from: Date())

        let normal = TestFactories.makeShadowEntry(id: 1, date: today, syncStatus: .synced)
        let deleted = TestFactories.makeShadowEntry(id: 2, date: today, syncStatus: .pendingDelete)
        try await store.insert(normal)
        try await store.insert(deleted)

        let vm = try makeViewModel(shadowEntryStore: store)
        await vm.loadData()

        #expect(vm.shadowEntries.count == 1)
        #expect(vm.shadowEntries[0].id == 1)
    }

    // MARK: - Data Loading: Positioned vs Unpositioned Segregation

    @Test("entries segregated into positioned and unpositioned by startTime")
    @MainActor
    func segregatesEntries() async throws {
        let store = try makeShadowEntryStore()
        let today = TimelineViewModel.dateString(from: Date())

        let positioned = TestFactories.makeShadowEntry(id: 1, date: today, startTime: "09:00")
        let unpositioned = TestFactories.makeShadowEntry(id: 2, date: today)
        try await store.insert(positioned)
        try await store.insert(unpositioned)

        let vm = try makeViewModel(shadowEntryStore: store)
        await vm.loadData()

        #expect(vm.positionedEntries.count == 1)
        #expect(vm.positionedEntries[0].id == 1)
        #expect(vm.unpositionedEntries.count == 1)
        #expect(vm.unpositionedEntries[0].id == 2)
    }

    // MARK: - Snap Helpers

    @Test("snapToGrid rounds to nearest 5 minutes")
    func snapToGridBasic() {
        #expect(TimelineViewModel.snapToGrid(minutes: 0) == 0)
        #expect(TimelineViewModel.snapToGrid(minutes: 2) == 0)
        #expect(TimelineViewModel.snapToGrid(minutes: 3) == 5)
        #expect(TimelineViewModel.snapToGrid(minutes: 7) == 5)
        #expect(TimelineViewModel.snapToGrid(minutes: 62) == 60)
        #expect(TimelineViewModel.snapToGrid(minutes: 63) == 65)
    }

    @Test("snapToGrid clamps to 0...1439")
    func snapToGridClamp() {
        #expect(TimelineViewModel.snapToGrid(minutes: -10) == 0)
        #expect(TimelineViewModel.snapToGrid(minutes: 1500) == 1439)
    }

    @Test("minutesSinceMidnight parses HH:mm correctly")
    func minutesSinceMidnight() {
        #expect(TimelineViewModel.minutesSinceMidnight(from: "00:00") == 0)
        #expect(TimelineViewModel.minutesSinceMidnight(from: "09:30") == 570)
        #expect(TimelineViewModel.minutesSinceMidnight(from: "23:59") == 1439)
        #expect(TimelineViewModel.minutesSinceMidnight(from: "bad") == nil)
    }

    @Test("timeString formats minutes as HH:mm")
    func timeStringFormatting() {
        #expect(TimelineViewModel.timeString(fromMinutes: 0) == "00:00")
        #expect(TimelineViewModel.timeString(fromMinutes: 570) == "09:30")
        #expect(TimelineViewModel.timeString(fromMinutes: 1439) == "23:59")
    }

    // MARK: - Move Entry

    @Test("moveEntry updates startTime and marks dirty")
    @MainActor
    func moveEntryUpdatesPersistence() async throws {
        let store = try makeShadowEntryStore()
        let today = TimelineViewModel.dateString(from: Date())
        let entry = TestFactories.makeShadowEntry(id: 1, date: today, startTime: "09:00")
        try await store.insert(entry)

        let vm = try makeViewModel(shadowEntryStore: store)
        await vm.loadData()

        await vm.moveEntry(vm.positionedEntries[0], toStartTime: "10:30")

        let updated = try await store.entry(id: 1)
        #expect(updated?.startTime == "10:30")
        #expect(updated?.syncStatus == .dirty)
    }

    @Test("moveEntry rejects locked entries")
    @MainActor
    func moveEntryRejectsLocked() async throws {
        let store = try makeShadowEntryStore()
        let today = TimelineViewModel.dateString(from: Date())
        let entry = TestFactories.makeShadowEntry(id: 1, date: today, locked: true, startTime: "09:00")
        try await store.insert(entry)

        let vm = try makeViewModel(shadowEntryStore: store)
        await vm.loadData()

        await vm.moveEntry(vm.positionedEntries[0], toStartTime: "10:30")

        let unchanged = try await store.entry(id: 1)
        #expect(unchanged?.startTime == "09:00")
        #expect(unchanged?.syncStatus == .synced)
    }

    // MARK: - Resize Entry

    @Test("resizeEntry updates startTime, seconds, and marks dirty")
    @MainActor
    func resizeEntryUpdatesPersistence() async throws {
        let store = try makeShadowEntryStore()
        let today = TimelineViewModel.dateString(from: Date())
        let entry = TestFactories.makeShadowEntry(id: 1, date: today, seconds: 3600, startTime: "09:00")
        try await store.insert(entry)

        let vm = try makeViewModel(shadowEntryStore: store)
        await vm.loadData()

        await vm.resizeEntry(vm.positionedEntries[0], newStartTime: "09:15", newDurationSeconds: 2700)

        let updated = try await store.entry(id: 1)
        #expect(updated?.startTime == "09:15")
        #expect(updated?.seconds == 2700)
        #expect(updated?.syncStatus == .dirty)
    }

    // MARK: - App Block Selection

    @Test("plain click selects a single block")
    @MainActor
    func plainClickSelectsSingle() throws {
        let vm = try makeViewModel()
        vm.toggleAppBlockSelection(id: "block-1", shiftHeld: false)

        #expect(vm.selectedAppBlockIds == ["block-1"])
    }

    @Test("plain click replaces previous selection")
    @MainActor
    func plainClickReplacesSelection() throws {
        let vm = try makeViewModel()
        vm.toggleAppBlockSelection(id: "block-1", shiftHeld: false)
        vm.toggleAppBlockSelection(id: "block-2", shiftHeld: false)

        #expect(vm.selectedAppBlockIds == ["block-2"])
    }

    @Test("plain click on sole selection clears it")
    @MainActor
    func plainClickDeselectsSole() throws {
        let vm = try makeViewModel()
        vm.toggleAppBlockSelection(id: "block-1", shiftHeld: false)
        vm.toggleAppBlockSelection(id: "block-1", shiftHeld: false)

        #expect(vm.selectedAppBlockIds.isEmpty)
    }

    @Test("shift-click toggles blocks into multi-selection")
    @MainActor
    func shiftClickMultiSelect() throws {
        let vm = try makeViewModel()
        vm.toggleAppBlockSelection(id: "block-1", shiftHeld: true)
        vm.toggleAppBlockSelection(id: "block-2", shiftHeld: true)

        #expect(vm.selectedAppBlockIds == ["block-1", "block-2"])
    }

    @Test("shift-click removes an already-selected block")
    @MainActor
    func shiftClickDeselects() throws {
        let vm = try makeViewModel()
        vm.toggleAppBlockSelection(id: "block-1", shiftHeld: true)
        vm.toggleAppBlockSelection(id: "block-2", shiftHeld: true)
        vm.toggleAppBlockSelection(id: "block-1", shiftHeld: true)

        #expect(vm.selectedAppBlockIds == ["block-2"])
    }

    @Test("clearAppBlockSelection empties the set")
    @MainActor
    func clearSelection() throws {
        let vm = try makeViewModel()
        vm.toggleAppBlockSelection(id: "block-1", shiftHeld: false)
        vm.clearAppBlockSelection()

        #expect(vm.selectedAppBlockIds.isEmpty)
    }

    // MARK: - Combined Time Range

    @Test("combinedTimeRange returns nil when nothing selected")
    @MainActor
    func combinedTimeRangeEmpty() throws {
        let vm = try makeViewModel()
        #expect(vm.combinedTimeRange == nil)
    }

    @Test("combinedTimeRange returns correct range for single selected block")
    @MainActor
    func combinedTimeRangeSingle() throws {
        let vm = try makeViewModel()
        let base = makeDate(hour: 9, minute: 0)
        let block = AppUsageBlock(
            id: "b1", appBundleId: "com.app", appName: "App",
            startTime: base, endTime: base.addingTimeInterval(3600),
            durationSeconds: 3600, recordCount: 1
        )
        vm.appUsageBlocks = [block]
        vm.toggleAppBlockSelection(id: "b1", shiftHeld: false)

        let range = vm.combinedTimeRange
        #expect(range?.startMinutes == 540)  // 9:00
        #expect(range?.durationMinutes == 60) // 1 hour
    }

    @Test("combinedTimeRange combines non-contiguous blocks using min/max")
    @MainActor
    func combinedTimeRangeNonContiguous() throws {
        let vm = try makeViewModel()
        let block1 = AppUsageBlock(
            id: "b1", appBundleId: "com.app", appName: "App",
            startTime: makeDate(hour: 9, minute: 0),
            endTime: makeDate(hour: 9, minute: 30),
            durationSeconds: 1800, recordCount: 1
        )
        let block2 = AppUsageBlock(
            id: "b2", appBundleId: "com.app", appName: "App",
            startTime: makeDate(hour: 11, minute: 0),
            endTime: makeDate(hour: 11, minute: 45),
            durationSeconds: 2700, recordCount: 1
        )
        vm.appUsageBlocks = [block1, block2]
        vm.toggleAppBlockSelection(id: "b1", shiftHeld: true)
        vm.toggleAppBlockSelection(id: "b2", shiftHeld: true)

        let range = vm.combinedTimeRange
        #expect(range?.startMinutes == 540)   // 9:00
        #expect(range?.durationMinutes == 165) // 9:00 to 11:45
    }

    // MARK: - Overlap Detection

    @Test("overlappingEntries returns empty when no entries exist")
    @MainActor
    func overlapNoEntries() throws {
        let vm = try makeViewModel()
        let result = vm.overlappingEntries(startMinutes: 540, durationMinutes: 60)
        #expect(result.isEmpty)
    }

    @Test("overlappingEntries detects partial overlap")
    @MainActor
    func overlapPartial() async throws {
        let store = try makeShadowEntryStore()
        let today = TimelineViewModel.dateString(from: Date())
        let entry = TestFactories.makeShadowEntry(id: 1, date: today, seconds: 3600, startTime: "09:00")
        try await store.insert(entry)

        let vm = try makeViewModel(shadowEntryStore: store)
        await vm.loadData()

        // Proposed 09:30-10:30 overlaps existing 09:00-10:00
        let result = vm.overlappingEntries(startMinutes: 570, durationMinutes: 60)
        #expect(result.count == 1)
        #expect(result[0].id == 1)
    }

    @Test("overlappingEntries detects full containment")
    @MainActor
    func overlapContainment() async throws {
        let store = try makeShadowEntryStore()
        let today = TimelineViewModel.dateString(from: Date())
        let entry = TestFactories.makeShadowEntry(id: 1, date: today, seconds: 3600, startTime: "09:00")
        try await store.insert(entry)

        let vm = try makeViewModel(shadowEntryStore: store)
        await vm.loadData()

        // Proposed 08:00-11:00 fully contains existing 09:00-10:00
        let result = vm.overlappingEntries(startMinutes: 480, durationMinutes: 180)
        #expect(result.count == 1)
    }

    @Test("overlappingEntries does not flag exact boundary touch")
    @MainActor
    func overlapBoundaryNoOverlap() async throws {
        let store = try makeShadowEntryStore()
        let today = TimelineViewModel.dateString(from: Date())
        // Entry from 09:00, duration 3600s = 60 min → ends at 10:00 (600 min)
        let entry = TestFactories.makeShadowEntry(id: 1, date: today, seconds: 3600, startTime: "09:00")
        try await store.insert(entry)

        let vm = try makeViewModel(shadowEntryStore: store)
        await vm.loadData()

        // Proposed starts exactly when existing ends (10:00 = 600 min) → NOT an overlap
        let result = vm.overlappingEntries(startMinutes: 600, durationMinutes: 60)
        #expect(result.isEmpty)
    }

    @Test("overlappingEntries returns no matches when ranges don't overlap")
    @MainActor
    func overlapNone() async throws {
        let store = try makeShadowEntryStore()
        let today = TimelineViewModel.dateString(from: Date())
        let entry = TestFactories.makeShadowEntry(id: 1, date: today, seconds: 3600, startTime: "09:00")
        try await store.insert(entry)

        let vm = try makeViewModel(shadowEntryStore: store)
        await vm.loadData()

        // Proposed 14:00-15:00 doesn't overlap 09:00-10:00
        let result = vm.overlappingEntries(startMinutes: 840, durationMinutes: 60)
        #expect(result.isEmpty)
    }

    // MARK: - Create Entry

    @Test("createEntry inserts with pendingCreate syncStatus and correct fields")
    @MainActor
    func createEntryInsertsWithPendingCreate() async throws {
        let store = try makeShadowEntryStore()
        let vm = try makeViewModel(shadowEntryStore: store)
        let today = TimelineViewModel.dateString(from: Date())

        await vm.createEntry(
            date: today,
            startTime: "09:30",
            durationSeconds: 2700,
            projectId: 100,
            taskId: 200,
            projectName: "Test Project",
            taskName: "Test Task",
            customerName: "Test Customer",
            description: "Xcode"
        )

        let entries = try await store.entries(forDate: today)
        #expect(entries.count == 1)
        let entry = entries[0]
        #expect(entry.syncStatus == .pendingCreate)
        #expect(entry.startTime == "09:30")
        #expect(entry.seconds == 2700)
        #expect(entry.hours == 0.75)
        #expect(entry.projectId == 100)
        #expect(entry.taskId == 200)
        #expect(entry.description == "Xcode")
        #expect(entry.localId != nil)
        #expect(entry.locked == false)
    }

    @Test("createEntry reloads data so entry appears in positionedEntries")
    @MainActor
    func createEntryReloadsData() async throws {
        let store = try makeShadowEntryStore()
        let vm = try makeViewModel(shadowEntryStore: store)
        let today = TimelineViewModel.dateString(from: Date())

        await vm.createEntry(
            date: today,
            startTime: "14:00",
            durationSeconds: 3600,
            projectId: 100,
            taskId: 200,
            projectName: "Test Project",
            taskName: "Test Task",
            customerName: "Test Customer",
            description: ""
        )

        #expect(vm.positionedEntries.count == 1)
        #expect(vm.positionedEntries[0].startTime == "14:00")
    }

    @Test("createEntry inherits user fields from existing entry on same date")
    @MainActor
    func createEntryInheritsUserFields() async throws {
        let store = try makeShadowEntryStore()
        let today = TimelineViewModel.dateString(from: Date())
        let existing = TestFactories.makeShadowEntry(id: 1, date: today, startTime: "08:00")
        try await store.insert(existing)

        let vm = try makeViewModel(shadowEntryStore: store)
        await vm.loadData()

        await vm.createEntry(
            date: today,
            startTime: "10:00",
            durationSeconds: 1800,
            projectId: 100,
            taskId: 200,
            projectName: "Test Project",
            taskName: "Test Task",
            customerName: "Test Customer",
            description: ""
        )

        let entries = try await store.entries(forDate: today)
        let created = entries.first { $0.id == nil || $0.id != 1 }
        #expect(created?.userId == 42)
        #expect(created?.userFirstname == "Test")
        #expect(created?.userLastname == "User")
        #expect(created?.hourlyRate == 100.0)
    }

    // MARK: - Helpers

    private func makeShadowEntryStore() throws -> ShadowEntryStore {
        let db = try SQLiteDatabase(path: ":memory:")
        return try ShadowEntryStore(database: db)
    }

    @MainActor
    private func makeViewModel(shadowEntryStore: ShadowEntryStore? = nil) throws -> TimelineViewModel {
        let store = try shadowEntryStore ?? makeShadowEntryStore()
        let appRecordStore = AppRecordStore(inMemory: true)
        let rulesDb = try SQLiteDatabase(path: ":memory:")
        let ruleStore = try RuleStore(database: rulesDb)
        let autotracker = Autotracker(
            shadowEntryStore: store,
            appRecordStore: appRecordStore,
            ruleStore: ruleStore
        )
        let syncState = SyncState()
        return TimelineViewModel(
            shadowEntryStore: store,
            autotracker: autotracker,
            syncState: syncState
        )
    }

    @MainActor
    private func makeViewModel(shadowEntryStore: ShadowEntryStore) throws -> TimelineViewModel {
        let appRecordStore = AppRecordStore(inMemory: true)
        let rulesDb = try SQLiteDatabase(path: ":memory:")
        let ruleStore = try RuleStore(database: rulesDb)
        let autotracker = Autotracker(
            shadowEntryStore: shadowEntryStore,
            appRecordStore: appRecordStore,
            ruleStore: ruleStore
        )
        let syncState = SyncState()
        return TimelineViewModel(
            shadowEntryStore: shadowEntryStore,
            autotracker: autotracker,
            syncState: syncState
        )
    }

    private func makeDate(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }

    private func makeAppRecord(
        bundleId: String,
        name: String,
        timestamp: Date,
        duration: TimeInterval
    ) -> AppRecord {
        AppRecord(
            id: nil,
            timestamp: timestamp,
            appBundleId: bundleId,
            appName: name,
            windowTitle: nil,
            durationSeconds: duration
        )
    }
}

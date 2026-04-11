# Performance Audit Fixes — Implementation Plan

> **Source:** `/audit` run on 2026-04-11. 23 findings total. P1-9 (AppState split) is deferred to its own PR — out of scope here per "minimal impact" principle.

**Goal:** Apply all 22 remaining P0/P1/P2/P3 performance fixes without regressing existing tests. Biggest wins are panel-visibility gating, killing the 1 Hz ticker, and eliminating the 100 Hz observation poll.

**Strategy:** Five phases, each ending with `xcodebuild ... test` green. Phase 1 is foundational (everything else rides on it). Phases 3–5 are mostly independent file-scoped edits that could be parallelized, but we'll go sequentially to keep the diff reviewable.

**Build command:** `xcodebuild -scheme MocoCompanion -configuration Debug -destination 'platform=macOS' build`
**Test command:** `xcodebuild -scheme MocoCompanion -configuration Debug -destination 'platform=macOS' test`

---

## Phase 1 — Panel visibility gate (foundation)

Many downstream fixes depend on a way to pause work when the panel is hidden.

### Task 1.1: Add `PanelVisibility` observable source
**Files:**
- Create: `MocoCompanion/State/PanelVisibility.swift`
- Modify: `MocoCompanion/Panel/PanelController.swift` (publish on show/hide)

`PanelVisibility` exposes:
```swift
@MainActor @Observable final class PanelVisibility {
    static let shared = PanelVisibility()
    private(set) var isVisible: Bool = false
    // AsyncStream for non-observable consumers
    var changes: AsyncStream<Bool> { ... }
    func set(_ visible: Bool) { ... }
}
```

Wire `PanelController.show()` → `PanelVisibility.shared.set(true)` and `hide()`/scheduleStateReset → `set(false)`.

**Test:** Add `PanelVisibilityTests.swift` — set true/false, assert AsyncStream emits.

**Commit:** `perf(panel): introduce PanelVisibility observable`

### Task 1.2: Gate `StatusItemController.elapsedTimerTask` on visibility
**Files:** `MocoCompanion/Panel/StatusItemController.swift:255-270`

When `PanelVisibility.shared.isVisible == false` AND timer is running, menu-bar title stays correct but the 1 Hz refresh loop sleeps at 10 s granularity (enough to keep HH:MM fresh). When visible, refresh at 1 s.

**Commit:** `perf(menubar): throttle elapsed refresh to 10s when panel hidden`

### Task 1.3: Gate `Autotracker.pollingTask`
**Files:** `MocoCompanion/State/Autotracker.swift:281-288`

Instead of the 2 s lastSeenAt refresh loop, rely on workspace events to update `lastSeenAt` (already happens in `handleWorkspaceEvent`). Delete `startPolling()`/`stopPolling()` entirely — they're dead weight.

**Test:** Existing `AutotrackerTests.swift` must still pass. Add a test confirming `lastSeenAt` advances on workspace event even with no polling.

**Commit:** `perf(autotracker): delete 2s polling loop, rely on workspace events`

### Task 1.4: Gate `MonitorEngine` cadence on visibility
**Files:** `MocoCompanion/State/MonitorEngine.swift:128-194`

When panel hidden: bump poll interval to max(currentInterval, 15 min). When visible: restore original. YesterdayService already at 10 min can stay, but IdleReminder (60 s) → 15 min when hidden; BudgetDepletion (120 s) → 15 min when hidden.

**Commit:** `perf(monitors): throttle monitor cadence when panel hidden`

### Task 1.5: Pause `Autotracker.workspace` listener when hidden (opt-in)
**Files:** `MocoCompanion/State/Autotracker.swift:53-88`

Actually — KEEP this running even when panel is hidden, because autotracking is the whole point of Autotracker. The user wants app activity recorded regardless of panel visibility. **Do not gate this.** Document the decision in a comment.

**No commit — decision documented inline.**

---

## Phase 2 — Hot path CPU wastes

### Task 2.1: Kill `TodayView.syncLabelTick` 1 Hz ticker (P0-3)
**Files:** `MocoCompanion/Views/TodayView.swift:114-120` + consumers of `syncLabelTick`

Delete the `.task { while ... }` block. Replace the sync-label display with `TimelineView(.periodic(from: .now, by: 60))` scoped to the specific `Text` showing the relative time — nothing else reads the ticker after this.

Audit every reader of `syncLabelTick` and detach them from ticker dependency. Stats (`yesterdayTotalHours`, `yesterdayBillablePercentage`) must NOT re-run per tick.

**Commit:** `perf(today): replace 1Hz ticker with scoped 60s TimelineView`

### Task 2.2: Rewrite `StatusItemController.observationTask` (P0-1)
**Files:** `MocoCompanion/Panel/StatusItemController.swift:190-213`

Replace the `while !Task.isCancelled { withObservationTracking ... sleep(10ms) }` with one-shot observation: when `onChange` fires, re-invoke the closure for the next mutation. No sleep, no busy loop. Standard Observation re-subscription pattern.

```swift
@MainActor
private func subscribeDisplayState() {
    let state = withObservationTracking {
        MenuBarDisplayState.from(...)
    } onChange: {
        Task { @MainActor [weak self] in self?.subscribeDisplayState() }
    }
    applyDisplayState(state)
}
```

**Commit:** `perf(menubar): replace 100Hz observation poll with re-subscribe pattern`

### Task 2.3: Async AX window title capture (P0-4)
**Files:** `MocoCompanion/State/Autotracker.swift:47-50` + `AccessibilityPermission.swift`

`currentFrontmost` returns immediately with `(bundleId, appName, nil)`. A detached `Task` calls `focusedWindowTitle(forProcess:)` with a 100 ms time box and invokes a callback to merge the title into the current segment when it arrives. Add a `CFRunLoopTimer`-backed timeout around the AX call.

**Test:** `AutotrackerTests.swift` — verify segment is created immediately without the title; title fills in asynchronously.

**Commit:** `perf(autotracker): move AX window title capture off main thread`

### Task 2.4: Bound `BudgetService.projectCaches` (P0-5)
**Files:** `MocoCompanion/State/BudgetService.swift:17-25`

Replace `[Int: ProjectBudgetCache]` with an LRU bounded at 32 entries. Add a simple `LRUCache<Key, Value>` helper (or inline: dictionary + access-order array).

**Test:** `BudgetServiceTests.swift` — assert cache max 32; 33rd insert evicts oldest.

**Commit:** `perf(budget): bound project cache with 32-entry LRU`

---

## Phase 3 — P1 mechanical fixes

### Task 3.1: Cache `DateFormatter` in `PanelContentView` (P1-1)
**Files:** `MocoCompanion/Panel/PanelContentView.swift:217-222`

Static formatter cache keyed by locale identifier. One-liner helper or `NSCache<NSString, DateFormatter>`.

**Commit:** `perf(panel): cache todayDateString formatter`

### Task 3.2: Stable IDs in `SearchResultsListView` (P1-2)
**Files:** `MocoCompanion/Panel/SearchResultsListView.swift:26-34`

Change `ForEach(Array(items.enumerated()), id: \.offset)` → `ForEach(items, id: \.entry.id)`. Remove `.id(index)` row modifier. Preserve section-header detection via `zip(items.indices, items)` or similar.

**Commit:** `perf(search): use stable entry.id for list identity`

### Task 3.3: Cached prefix in `MenuBarDisplayState` refresh (P1-3)
**Files:** `MocoCompanion/Panel/StatusItemController.swift:272-282` + `MenuBarDisplayState.swift`

Split title into `prefix` (emoji + project name, cached on transition) + `elapsed` (recomputed per tick). `refreshElapsed()` recomposes `prefix + " " + formattedElapsed` without re-scanning emoji.

**Test:** `MenuBarDisplayStateTests.swift` — existing tests must still pass.

**Commit:** `perf(menubar): cache title prefix across refresh ticks`

### Task 3.4: Coalesce `OfflineSyncService` fetches by date (P1-4)
**Files:** `MocoCompanion/State/OfflineSyncService.swift:32-44`

Group queue entries by date, fetch once per distinct date, build a set of server-side activity keys, then dedupe in memory.

**Test:** `OfflineSyncServiceTests.swift` — add test confirming 3 entries on same date → 1 fetch.

**Commit:** `perf(sync): batch offline-sync duplicate check by date`

### Task 3.5: Transactional `AppRecordStore` insert (P1-5)
**Files:** `MocoCompanion/State/AppRecordStore.swift:66-91`

Wrap insert in `BEGIN IMMEDIATE / COMMIT`. Add `insertMany(_ records: [AppRecord])` for batch flushes.

**Test:** `AppRecordStoreTests.swift` — add test for `insertMany` covering 100 records.

**Commit:** `perf(apprecord): batch inserts in a single transaction`

### Task 3.6: Verify `SyncEngine.dirtyEntries` index (P1-6)
**Files:** `MocoCompanion/Database/ShadowEntryStore.swift` (schema) + `SyncEngine.swift:109-112`

Run `EXPLAIN QUERY PLAN` on the dirty-entries query programmatically in a debug-only helper, or manually via a migration test. If not using an index, add a partial index: `CREATE INDEX IF NOT EXISTS idx_shadow_sync_dirty ON shadow_entries(sync_status) WHERE sync_status != 'synced'`.

**Commit:** `perf(sync): partial index on dirty shadow entries`

### Task 3.7: Debounce `NSWorkspace` activation events (P1-7)
**Files:** `MocoCompanion/State/Autotracker.swift:196-198`

Add a 300 ms trailing debounce to `handleWorkspaceEvent`. Use a simple `DispatchWorkItem` swap pattern on the main actor.

**Test:** `AutotrackerTests.swift` — verify rapid alt-tab (5 events in 100 ms) produces 1 final segment update.

**Commit:** `perf(autotracker): debounce workspace activation events`

### Task 3.8: Debounce `RecencyTracker` / `RecentEntriesTracker` persistence (P1-8)
**Files:** `MocoCompanion/State/RecencyTracker.swift:26-29`, `MocoCompanion/State/RecentEntriesTracker.swift:36-59`

Replace per-call `persist()` with a 2 s trailing debounce. Flush synchronously on `applicationWillTerminate` (add a `flush()` public method).

**Commit:** `perf(recency): debounce UserDefaults writes`

### Task 3.9: Cache `effectiveColorScheme` in `PanelContentView` (P1-9b → was P1-9 in my numbering; this is the cheap version)
**Files:** `MocoCompanion/Panel/PanelContentView.swift:37-53`

Store `effectiveColorScheme` in `@State`, update via `.onChange(of: appState.settings.appearance)` and `.onChange(of: colorScheme)`.

**Commit:** `perf(panel): memoize effectiveColorScheme`

---

## Phase 4 — P2 fixes

### Task 4.1: Reduce panel shadow cost (P2-1)
**Files:** `MocoCompanion/Panel/PanelContentView.swift:132-133`

Replace dual shadows (radius 40 + radius 6) with single radius-12 shadow, or move to `NSPanel.contentView.wantsLayer = true` with `CALayer.shadow*` properties (cached by Core Animation).

**Commit:** `perf(panel): consolidate stacked shadows`

### Task 4.2: Move `TodayView` stats into `TodayViewModel` (P2-2)
**Files:** `MocoCompanion/Views/TodayView.swift:393-403`

Add `todayTotalHours`, `todayBillablePercentage`, `yesterdayTotalHours`, `yesterdayBillablePercentage` as stored properties on `TodayViewModel`, recomputed only when the underlying activities change.

**Commit:** `perf(today): precompute stats on view-model data change`

### Task 4.3: Precompute `plannedHours` per row (P2-3)
**Files:** `MocoCompanion/Views/TodayView.swift:341-375` + `TodayViewModel`

Build a `[RowKey: Double?]` dictionary once per data-change in the view model. Row lookup becomes `O(1)` dictionary read instead of per-row search.

**Commit:** `perf(today): cache plannedHours lookups per data change`

### Task 4.4: Schedule `IdleReminderMonitor` end-of-day via Timer, not polling (P2-4)
**Files:** `MocoCompanion/State/IdleReminderMonitor.swift:77-121`

Remove the `checkEndOfDay()` path from the 60 s poll. Instead, schedule a one-shot `Task.sleep(until: nextHoursEndBoundary)` that fires the alert, then reschedules for the next day.

**Commit:** `perf(monitors): one-shot schedule for end-of-day reminder`

### Task 4.5: Debounce `CalendarService.changeTick` (P2-5)
**Files:** `MocoCompanion/State/CalendarService.swift:137-149`

Add 500 ms trailing debounce to the `.EKEventStoreChanged` handler before bumping `changeTick`.

**Commit:** `perf(calendar): debounce EKEventStoreChanged fanout`

### Task 4.6: Monotonic version for `ActivityService` sort cache (P2-6)
**Files:** `MocoCompanion/State/ActivityService.swift:63-79, 311-350`

Replace the sort-cache invalidation on every mutation with a version check: cache stores `(version, sortedArray)`. Mutations bump version. Reads compare versions and re-sort only when stale.

**Commit:** `perf(activity): version-based sort cache`

---

## Phase 5 — P3 polish

### Task 5.1: `ProjectCatalog.color` lookup cache (P3-1)
**Files:** `MocoCompanion/State/ProjectCatalog.swift:31-34`

Cache `[Int: Color]` alongside `projects`. Rebuild lazily when `projects` is set.

**Commit:** `perf(catalog): cache project color lookup`

### Task 5.2: Extract `EntryRow` star + hints into isolated subviews (P3-2)
**Files:** `MocoCompanion/Views/EntryRow.swift:87-98, 126-135`

Pull `StarButton` and `RowHintsRow` into their own `View` types so parent state changes don't force their re-materialization.

**Commit:** `perf(entry-row): isolate star and hints into subviews`

### Task 5.3: Relax `AppLogger` flush interval (P3-3)
**Files:** `MocoCompanion/State/AppLogger.swift:113`

Change flush interval from 5 s → 30 s.

**Commit:** `perf(logger): relax flush cadence to 30s`

---

## Verification gates

After each phase:
1. `xcodebuild -scheme MocoCompanion -configuration Debug -destination 'platform=macOS' build` → must succeed
2. `xcodebuild -scheme MocoCompanion -configuration Debug -destination 'platform=macOS' test` → all tests green

After all phases:
3. Manual smoke: launch app, open panel, start timer, switch apps, hide panel, confirm menu-bar label still updates.
4. Re-read `/audit` output mentally against each task — any missed?

---

## Deferred (out of scope here)

- **P1-9 `AppState` split** — large structural refactor, separate PR.

# Knowledge

Durable learnings captured from sessions — gotchas, conventions, constraints, and hard-won debugging insights. Grouped by topic, newest first within each topic.

Use `/hv-learn` at the end of a session to capture new learnings. `/hv-work` consults this file when its topics are relevant to the task.

## Build & Tooling

- SourceKit live diagnostics can emit spurious *"Cannot find X in scope"* / *"Missing argument for parameter"* errors for same-target Swift symbols right after a rapid edit — the live index lags behind the file. Authoritative signal is `xcodebuild -scheme MocoCompanion -configuration Debug -destination 'platform=macOS' build`; trust its `** BUILD SUCCEEDED **` over the editor's error list before acting. <!-- 2026-04-22 -->

## Architecture

- `AppRecord.windowTitle` flows end-to-end through the capture pipeline (`Autotracker` → `AppRecordStore` → `AppUsageBlock.windowTitle`) — but the Timeline UI only surfaces fields that `AppUsageBlockView` explicitly renders. When auditing what the user sees, check `AppUsageBlockView.helpLabel` (tooltip) and `AppUsageBlockView.hoverPopover`, not just the model. The file lives at `MocoCompanion/Views/Autotracker/AppUsageBlockView.swift`, not under `Views/Timeline/`. <!-- 2026-04-22 -->

## Menubar

- `NSApp.currentEvent` can be nil when a third-party menubar manager (Bartender, Ice) re-parents the `NSStatusItem`. A `guard let event = NSApp.currentEvent else { return }` in a status-item click handler silently swallows left-clicks for affected users while the global hotkey still works. Default the nil case to the primary left-click action and log the occurrence — don't early-return. See `StatusItemController.statusItemClicked(_:)`. <!-- 2026-04-22 -->
- `StatusItemController.verifyOrRecreate()` runs at T+2/5/10s after launch to handle menubar managers that hide the status item; it rebuilds the item *and* re-binds the click handler (`button.target`, `button.action`, `sendAction(on:)`). Don't duplicate this recovery logic elsewhere — extend it if a new failure mode (e.g., orphaned button still attached to a window but outside the status bar) needs coverage. <!-- 2026-04-22 -->

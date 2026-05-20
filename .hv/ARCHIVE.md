# Archive

Completed items older than the active window.
- ~~**[B-4] [P1] Shortcut recorder doesn't recognize key presses and ESC doesn't cancel.**~~ Done 2026-04-15 [`e495c49`]
- ~~**[B-5] [P1] Today view doesn't refresh when switching timer to another entry.**~~ Done 2026-04-15 [`e495c49`]
- ~~**[B-1] [P1] Undo toast "Entry deleted" and "Delete this entry?" not translated in German.**~~ Done 2026-04-15 [`679800a`]
- ~~**[B-2] [P1] Timeline entry creation — project search has no keyboard path.**~~ Done 2026-04-15 [`679800a`]
- ~~**[F-1] [Minor] Default global hotkey to Hyper key (⌘⌥⌃⇧).**~~ Done 2026-04-15 [`679800a`]
- ~~**[F-2] [Major] Internal diagnostic breadcrumb trail for crash investigation.**~~ Done 2026-04-15 [`941bfe6`]
- ~~**[B-3] [P0] CPU pegs to 100% after starting a timer — app becomes unresponsive.**~~ Done 2026-04-15 [`70148d9`]
- ~~**[B06] [P1] Project picker fuzzy matching broken in Timeline view.** When creating a new entry in the Timeline view, the project picker always shows the first entry as selected. Typing does not trigger a search/filter — fuzzy matching is completely unresponsive. Related: [B-2]~~ Done 2026-04-21 [`6a8ba29`]
- ~~**[B07] [P1] Left-click on menubar icon does not open panel for some users.** Reported externally: clicking the menubar status item fails to toggle the panel. Workaround: the global hotkey still works. Suspect interaction with menubar managers (Bartender/Ice) or a stale NSStatusItem target — note that `StatusItemController.verifyOrRecreate()` already runs at T+2/5/10s for this class of issue, so root cause is likely click-handler wiring rather than item registration. Need repro details (macOS version, menubar manager, does right-click menu still appear).~~ Done 2026-04-22 [`43d1199`]
- ~~**[B08] [P1] Menu-title capture missing from Timeline view.** Menu-title / active-window capture (app recording) either isn't being recorded or is no longer rendered in the Timeline. Unclear which: needs to check (a) whether `AppRecordStore` is receiving entries (Accessibility permission, `MonitorEngine` wiring), and (b) whether `TimelineWindow` still surfaces the captured titles on hover/detail. Likely a regression — worked previously.~~ Done 2026-04-22 [`b6ba5be`]

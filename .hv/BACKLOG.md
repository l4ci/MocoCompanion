# TODO

## Bugs
- **[B09] [P1] Dark mode contrast issues on Settings pages.** Some Settings panels still render black text on a dark background in dark mode, making content unreadable. Likely hardcoded colors or system-color usage that doesn't adapt to the appearance — check against `Theme.swift` and ensure every label/control uses the three-tier text tokens. Since: 5688805

## Features
- **[F03] [Minor] Option to set Timeline View as default.** Add a setting so the global shortcut opens the Timeline View directly instead of the popup panel. Useful for users who primarily work day-at-a-glance and currently need an extra step to reach the Timeline. Since: 5688805

## Tasks

## Completed
- ~~**[B06] [P1] Project picker fuzzy matching broken in Timeline view.** When creating a new entry in the Timeline view, the project picker always shows the first entry as selected. Typing does not trigger a search/filter — fuzzy matching is completely unresponsive. Related: [B-2]~~ Done 2026-04-21 [`6a8ba29`]
- ~~**[B07] [P1] Left-click on menubar icon does not open panel for some users.** Reported externally: clicking the menubar status item fails to toggle the panel. Workaround: the global hotkey still works. Suspect interaction with menubar managers (Bartender/Ice) or a stale NSStatusItem target — note that `StatusItemController.verifyOrRecreate()` already runs at T+2/5/10s for this class of issue, so root cause is likely click-handler wiring rather than item registration. Need repro details (macOS version, menubar manager, does right-click menu still appear).~~ Done 2026-04-22 [`43d1199`]
- ~~**[B08] [P1] Menu-title capture missing from Timeline view.** Menu-title / active-window capture (app recording) either isn't being recorded or is no longer rendered in the Timeline. Unclear which: needs to check (a) whether `AppRecordStore` is receiving entries (Accessibility permission, `MonitorEngine` wiring), and (b) whether `TimelineWindow` still surfaces the captured titles on hover/detail. Likely a regression — worked previously.~~ Done 2026-04-22 [`b6ba5be`]

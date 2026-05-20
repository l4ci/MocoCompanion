# TODO

## Bugs

## Features
- **[F04] [Minor] Default-window setting also drives menubar left-click target.** The setting introduced in [F03] (currently named `shortcutTarget` / `settings.shortcutTarget`) should also decide which window opens when the user left-clicks the menubar icon — not just the global keyboard shortcut. Rename the config key + the UI label to reflect the broader scope (something like `defaultWindow` / "Default Window"). Touches `StatusItemController.statusItemClicked`, the `ShortcutTarget` enum in `SettingsStore`, and the picker in `GeneralSettingsTab`. Watch for the rename migration: existing users have `shortcutTarget` in UserDefaults — either read both keys with a legacy fallback or migrate on launch. Related: [F03] Since: 2be5ec6

## Tasks

## Completed
- ~~**[B09] [P1] Dark mode contrast issues on Settings pages.** Some Settings panels still render black text on a dark background in dark mode, making content unreadable. Likely hardcoded colors or system-color usage that doesn't adapt to the appearance — check against `Theme.swift` and ensure every label/control uses the three-tier text tokens. Since: 5688805~~ Done 2026-05-20 [`2e2067c`]
- ~~**[F03] [Minor] Option to set Timeline View as default.** Add a setting so the global shortcut opens the Timeline View directly instead of the popup panel. Useful for users who primarily work day-at-a-glance and currently need an extra step to reach the Timeline. Since: 5688805~~ Done 2026-05-20 [`0cf697a`]

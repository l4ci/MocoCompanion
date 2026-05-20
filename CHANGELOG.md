# Changelog

All notable changes to MocoCompanion are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) loosely; versions follow semver.

## v0.6.0 — 2026-05-20

Two new settings, four bug fixes around the menubar and Timeline, plus an internal refactor pass.

### New

- **Default Window setting** (formerly *Global Shortcut Opens*) now drives both the global keyboard shortcut and the menubar left-click. Pick Panel or Timeline once; both honor the choice. UserDefaults migrates automatically on first launch. ([F03], [F04])
- Environment snapshot (macOS version, build, locale, peer apps) is now logged at launch for diagnostics.

### Fixed

- Menubar left-click no longer silently no-ops when third-party menubar managers (Bartender, Ice) re-parent the status item — defaults to opening the panel when `NSApp.currentEvent` is nil. ([B07])
- Timeline block popover and tooltip now show the captured window title. ([B08])
- Settings window respects dark mode; theme and color scheme are injected into the view. ([B09])
- Replaced deprecated `String(cString:)` with UTF8 decoding.

### Changed

- Internal refactor pass: surfaced silent local-store errors, centralized ShadowEntry merge logic to preserve local-origin metadata, and patched TimelineViewModel mutations in place so the pre-sync reload is gone. (R1–R3)

### Stats

17 user-visible commits · 27 files changed · +611 −48 lines

**Full changelog:** https://github.com/l4ci/MocoCompanion/compare/v0.5.6...v0.6.0

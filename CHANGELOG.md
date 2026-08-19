# Changelog

All notable changes to MocoCompanion are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) loosely; versions follow semver.

## v0.7.0 — 2026-08-19

Audit pass: security, performance, concurrency and test-hygiene reviews, with fixes. Day-to-day use is unchanged apart from the additions below.

### New

- **Clear tracked app history** button in Settings → Timeline → Tracking. Deletes every recorded app/window segment after a confirmation; independent of the age-based retention.
- **Demo badge.** While Demo Mode is on, a small "Demo" pill sits next to the greeting in the panel header so it can't be left on by accident.
- **Corrupt-database recovery.** If `shadow.db`, `rules.sqlite` or `app_records.sqlite` turns out to be corrupt (SQLite reports CORRUPT/NOTADB/FORMAT on open, probe, or `quick_check`), the file (plus `-wal`/`-shm`) is moved aside as `*.corrupt-<timestamp>` and a fresh database is created. A locked or unreadable file is left alone. Previously this crashed on every launch.

### Fixed

- **Manual bookings made offline are kept** and pushed when the connection returns, instead of failing with an error. The unused second offline queue is gone; the offline banner now shows the real number of entries waiting to sync.
- **Duplicate bookings under overlapping syncs.** Several code paths could run a sync at the same time; two overlapping runs could both push the same pending entry and create it twice on Moco. Syncs are now coalesced into one queue.
- **Reset all data** left the offline queue, rules and window-title history on disk. It now clears all three.
- **Autotracker double-counting on sleep/lock.** macOS sends more than one notification per sleep/lock; the same segment could be written twice. Events are now processed strictly in order.
- Login error in the setup wizard showed a raw string key instead of a message. Rule count and the timeline slot action were missing German translations.
- Refresh spinner now respects Reduce Motion; VoiceOver announces "timer running" on the status row.
- Update check no longer misreads pre-release tags (`1.2.0-beta1`) as older/equal releases.
- Manual hours input rejects values above 24 and non-finite numbers.

### Changed

- Local databases open in WAL mode (you'll see `-wal`/`-shm` files next to them). Writes no longer block reads and app/window switches no longer wait on disk.
- API log file strips query strings and truncates error bodies unless the API log level is Debug.
- App-usage recording moved off the main thread; the last segment is flushed before quit.
- Unit tests run in random order and no longer touch the real Keychain, preferences or log directory. (Previously a test run could overwrite the stored Moco API key.)
- `Vendor/HotKey` ships its MIT license; xcodegen 2.46, Xcode 26.6.

### Stats

15 user-visible commits · 72 files changed · +7,400 / −5,576 lines

**Full changelog:** https://github.com/l4ci/MocoCompanion/compare/v0.6.1...v0.7.0

## v0.6.1 — 2026-05-20

One user-visible behavior change: window-title capture now keeps up with tab and document switches inside the same app, not just app switches.

### New

- **Window-title capture follows intra-app focus changes.** Switching Chrome tabs, opening a different email in Outlook, or jumping between Xcode documents each now create their own timeline segment tagged with the new title. Before this, the autotracker only re-read the title on app switch — a one-hour Chrome session showed a single segment with the first tab's title. Requires **Settings → Autotracker → Window title tracking** to be on. Built on a per-PID `AXObserver` subscribed to `kAXFocusedWindowChangedNotification`; title-change notifications are deliberately not observed, so Gmail unread-counter flicker and similar JS-driven title updates don't fragment segments.

### Changed

- Dev workflow: `.hv/` workspace state (backlog, knowledge, decisions, milestones, sidecars) is now gitignored and local-only; each contributor maintains their own.

### Stats

1 user-visible commit · 4 files changed · +172 lines

**Full changelog:** https://github.com/l4ci/MocoCompanion/compare/v0.6.0...v0.6.1

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

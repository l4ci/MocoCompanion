# MocoCompanion — User Guide

> A native macOS menubar app for Moco time tracking. Zero-friction: shortcut → search → track. No browser needed.

---

## Table of Contents

1. [Getting Started](#getting-started)
2. [Your Workday with MocoCompanion](#your-workday-with-mococompanion)
   - [Morning: Start Your Day](#morning-start-your-day)
   - [Mid-Morning: Switch Tasks](#mid-morning-switch-tasks)
   - [Break: Pause Timer](#break-pause-timer)
   - [Before Lunch: Review & Correct](#before-lunch-review--correct)
   - [End of Day: Manual Entry](#end-of-day-manual-entry)
   - [Check Tomorrow](#check-tomorrow)
3. [Timeline & Autotracker](#timeline--autotracker)
   - [The Timeline View](#the-timeline-view)
   - [Autotracker](#autotracker)
   - [Calendar Integration](#calendar-integration)
   - [Rules](#rules)
4. [Settings](#settings)
5. [Keyboard Shortcuts Reference](#keyboard-shortcuts-reference)
6. [Tips & Tricks](#tips--tricks)

---

## Getting Started

### Installation

1. Launch **MocoCompanion** — it lives in your menubar (top-right of your screen, near the clock)
2. On first launch, Settings opens automatically
3. Enter your **Moco subdomain** (e.g., `mycompany` for mycompany.mocoapp.com)
4. Enter your **API key** (found in Moco → Profile → Integrations)
5. Close Settings — you're ready

### The Menubar Icon

MocoCompanion sits in your menubar as a timer icon with a small colored dot:

| State | Dot Color | Menubar Text |
|-------|-----------|-------------|
| **Idle** | 🔴 Red | No text — nothing is tracking |
| **Running** | 🟢 Green | Project name + live elapsed time |
| **Paused** | 🟠 Orange | No text — timer is paused |
| **Error** | 🔴 Red | Warning triangle icon |

**Interactions:**
- **Left-click** the menubar icon → opens the **panel** (Track or Log view)
- **Right-click** → opens a context menu (New Timer, Open Moco in Browser, Settings, Quit)
- **Global shortcut** `⌘⌃⌥M` → opens the panel from anywhere (customizable in Settings)

---

## Your Workday with MocoCompanion

### Morning: Start Your Day

#### 1. Open the Panel

Press your **global shortcut** (`⌘⌃⌥M` by default) or **left-click** the menubar icon.

The panel opens with two tabs: **TRACK** and **LOG**. Which tab appears first is configurable in Settings → General → Default Tab.

Your user avatar (or initials) appears in the top-left of both views.

#### 2. Check What's Planned

Switch to the **LOG** tab (press `Tab` or click the tab switcher).

You'll see the day toggle: **Gestern | Heute | Morgen** (Yesterday | Today | Tomorrow). Today shows:

- **Tracked entries** — any time already booked today
- **Planned · not yet tracked** — tasks from Moco's planning that you haven't started
- **Stats footer** — total hours, billable %, entry count

Each planned task shows the project name, task name, and planned hours.

**To start working on a planned task:**
- Use `↓` arrow key to navigate to the planned task
- Press `Enter` to start the timer — or click the row
- The task moves from "Planned" to "Tracked"

#### 3. Start from Favorites or Search

Switch to the **TRACK** tab. You'll see:

- **Favorites** — your pinned project/task combos (⭐ star to toggle)
- **Recents** — recently used combos with last description
- **Suggestions** — popular projects (when favorites and recents are empty)

**The search → timer flow:**
1. Type a few characters (e.g., `mark` to find "Marketing")
2. Results filter live — use `↑↓` or `⌘1`–`⌘5` to select
3. Press `Enter` → project/task locks in, you enter the **description phase**
4. A green checkmark banner shows your selection
5. Type a description (e.g., "Weekly sync call")
6. Press `Enter` → **timer starts**, panel closes, menubar updates

**In the description phase:**
- Use `#TICKET-123` in your description — extracted as a tag automatically
- `Tab` autocompletes from your previous descriptions
- Toggle **Timer / Manual** to switch between timer start and hours booking
- `Escape` goes back to search

---

### Mid-Morning: Switch Tasks

#### Option A: Quick Switch via Search

1. Press `⌘⌃⌥M` to open the panel
2. Search for the new project/task → select → describe → `Enter`
3. The **previous timer stops automatically** and the new one starts

#### Option B: Continue a Previous Entry from Today

1. Open panel → **LOG** tab → Today
2. Navigate to a previous entry with `↑↓`
3. Press `Enter` → timer continues on that entry, panel closes

#### Option C: Quick-Start with ⌘+Number

In the **LOG** tab, each entry has a ⌘-number badge (⌘1, ⌘2, etc.):
- Press `⌘1` to instantly start tracking on the first entry
- Works in both Today and Yesterday views
- Panel closes after starting

---

### Break: Pause Timer

#### Pause

1. Press `⌘⌃⌥M` to open the panel
2. With the search field empty, press `Enter` → **timer pauses**
3. The menubar dot changes to 🟠 orange, text disappears
4. **Panel stays open** so you can see the paused state

#### Resume

1. Press `⌘⌃⌥M` again (or if panel is still open)
2. Press `Enter` with empty search → **timer resumes**
3. Menubar dot returns to 🟢 green with live elapsed time

Alternatively, in the Log tab: select the paused entry and press `Enter` to resume. The panel stays open when pausing, closes when resuming.

---

### Before Lunch: Review & Correct

#### Check Your Day

Open panel → **LOG** tab → Today.

- **Running entry** — green dot, live elapsed time, listed first
- **Paused entry** — orange dot
- **Completed entries** — static duration (e.g., `1h05m`)
- **Planned hours** — entries show `1h of 2h` (tracked vs planned)

Stats footer shows: **Gesamt** (total hours), **Abrechenbar** (billable %), **Einträge** (entry count).

#### Edit an Entry

1. Navigate with `↑↓`, press `E`
2. Edit overlay appears inline: description, hours, project reassignment
3. `Enter` to save, `Escape` to cancel

**Hours accept flexible formats:** `1`, `1.5`, `1h`, `60m`, `1h 30m`, `1,5`

#### Change Project on an Entry

1. Press `E` to edit → click the project name in the header
2. Mini search field appears — type to filter projects
3. Select the correct project → task dropdown updates
4. `Enter` to save — description and hours preserved

#### Delete an Entry

1. Navigate with `↑↓`, press `D`
2. Confirmation row: **Abbrechen (Esc)** and **Löschen (↩)** buttons
3. Both clickable and keyboard-accessible

#### Check Yesterday

Press `←` arrow to switch to **Gestern** (Yesterday).

Yesterday's entries are fully editable (hours, description, project, task). Key differences from Today:

- **Enter** on a yesterday entry → **starts a new timer** with the same project/task/description (copies to today)
- **E** to edit, **D** to delete, **F** to favorite
- Active timer entries are hidden from the Yesterday view (they belong to Today)
- The Yesterday empty state shows "Keine Einträge gestern" (not Today's message)

---

### End of Day: Manual Entry

Forgot to track a meeting? Book it without starting a timer:

1. `⌘⌃⌥M` → search → select project/task → `Enter`
2. In the description phase, click **Timer / Manual** toggle (or press `Tab` to switch and focus hours)
3. Enter hours: `2` or `2h` or `1h 30m` or `90m`
4. Type description → `Enter` → entry booked, no timer started

---

### Check Tomorrow

Press `→` twice from Today (or once from Yesterday's Tomorrow) to see **Morgen** (Tomorrow).

Tomorrow shows a read-only planning view:
- Planned tasks with project/customer names and hours
- Total planned hours at the bottom
- Absence banners if you have scheduled leave

---

## Timeline & Autotracker

### The Timeline View

Open the Timeline via `⌘T` from the quick-entry panel or via the menubar context menu.

The Timeline shows your workday as a visual time axis with two columns side by side:

- **Left column — App usage** shows which applications you used and for how long, rendered as colored blocks. Blocks are clustered when they overlap so nothing is hidden.
- **Right column — Moco entries** shows your tracked time entries positioned on the same time axis, color-coded by project (colors synced from Moco).

Above the timeline, an **all-day events bar** shows calendar events that span the full day (holidays, out-of-office, etc.).

#### Creating entries on the timeline

- **Drag in empty space** in the Moco column to create a new entry. A ghost preview shows the time range as you drag. Dragging bottom-to-top works too.
- **Move entries** by dragging an existing block up or down on the time axis.
- **Resize entries** by dragging the top or bottom edge of a block.
- Changes are pushed to Moco immediately after move or resize.

#### Managing entries

- **Click** an entry to select it. The selected entry is highlighted.
- **Delete/Backspace** removes the selected shadow entry (with confirmation).
- **Right-click** an entry for a context menu with edit and delete options.
- Billed entries are read-only — they cannot be moved, resized, or deleted.

The toolbar shows the current date, a sync button with last-sync timestamp, and navigation to switch days.

### Autotracker

The Autotracker runs in the background and records which apps you use throughout the day. It captures:

- **App name and bundle ID** for each focused application
- **Window titles** (optional, enable in Settings → Timeline → Track window titles)
- **Duration** of each usage session

Usage blocks shorter than 5 minutes are filtered out to reduce noise.

When you see app usage blocks on the timeline, you can:

1. **Right-click an app block** → "Create entry" to turn it into a Moco time entry with the matching time range
2. **Approve a suggestion** — when a rule matches an app block, a dashed-outline suggestion appears. Hover to see details, click to approve and create the entry.

**Excluded apps:** In Settings → Timeline → Excluded Apps, you can blacklist apps that should not be tracked (e.g., your password manager). Uses a running-app picker for easy selection.

### Calendar Integration

When calendar access is granted (macOS will prompt on first use), your calendar events appear on the timeline:

- **Timed events** show as blocks in the calendar column, positioned on the time axis
- **All-day events** appear in a dedicated bar above the timeline
- Events are read-only — they serve as context for your time entries, not as editable items

Calendar events are also available as triggers for autotracker rules (see below).

### Rules

Rules let you automate time entry creation based on app usage or calendar events.

#### Creating a rule

1. Open Settings → Timeline → Rules, or right-click an app block on the timeline → "Create rule"
2. Choose a **rule type**: App-based or Calendar event-based
3. For app rules: select the app (auto-filled from context menu) and optionally a window title pattern
4. For calendar rules: enter an event title pattern to match
5. Select the **project and task** the rule should map to
6. Save — the rule takes effect on the next autotracker evaluation cycle

#### Managing rules

- Rules are listed in Settings → Timeline with toggle switches to enable/disable each one
- Each rule shows its type icon, match criteria, and target project
- Edit or delete rules from the list
- Rules are evaluated during the periodic background tick (every 10 minutes)

---

## Settings

Open via **right-click menubar → Settings** or `⌘,`.

Settings window (780×580) has 9 tabs:

### Account
- **Subdomain** — your Moco instance name
- **API Key** — stored in macOS Keychain (masked display)
- **Status** — connection indicator + Refresh Projects button

### How to Use
- **Global Shortcut** — current shortcut display + click-to-record custom shortcut
- **Track** — search, keyboard navigation, tagging reference
- **Log** — today/yesterday controls reference

All instructions are localized (German/English).

### General
- **Startup** — Launch at Login toggle, Default Tab picker (Track / Log)
- **Working Hours** — Start/End time pickers. Controls when idle reminders are active and when the end-of-day summary appears.
- **Sound** — Sound Effects toggle (Tink on start, Pop on stop)
- **Display** — Appearance (Auto/Light/Dark), entry font size slider (15–18pt), Autocomplete Descriptions toggle

### Timeline
Three sections:

- **Calendar** — Enable calendar integration (requires macOS calendar permission)
- **Rules** — Enable autotracker rules, manage rule list (add/edit/delete/toggle individual rules), rule type icons
- **Tracking** — Track window titles toggle, excluded apps list with running-app picker

### Favorites
- **Show Favorites** toggle
- Reorder favorites via drag (☰ handles)
- Remove individual favorites (✕ button)

### Notifications
5 groups with per-type toggles:

| Group | Types |
|-------|-------|
| **Timer** | Started, Resumed, Stopped, Continued |
| **Activity** | Manual Entry, Duplicated, Deleted, Description Updated, Projects Synced |
| **Reminders** | Idle (5min no timer), Forgotten Timer (3h+), End of Day Summary |
| **Budget** | Project Budget Warning, Task Budget Warning |
| **Alerts** | Yesterday Incomplete, API Errors (always on) |

### Projects
- Browse synced projects with customer names and active tasks
- Refresh button for manual re-sync

### Debug
- Log levels (API, App) — adjustable verbosity
- Open/reveal/clear log files

### About
- App icon, name, and version number
- Author name (Volker Otto)
- License (MIT)
- Link to GitHub repository

---

## Keyboard Shortcuts Reference

### Global

| Shortcut | Action |
|----------|--------|
| `⌘⌃⌥M` | Open/close panel *(customizable)* |

### Track Tab

| Shortcut | Action |
|----------|--------|
| Type | Filter projects by name, customer, or task |
| `↑` `↓` | Navigate results |
| `⌘1`–`⌘5` | Jump to result by number |
| `Enter` | Select result / Pause or resume (empty search) |
| `Tab` | Switch to Log tab (empty search) |
| `Escape` | Close panel |

### Description Phase

| Shortcut | Action |
|----------|--------|
| `Enter` | Start timer (timer mode) / Book entry (manual mode) |
| `Tab` | Accept autocomplete / Switch to manual mode + focus hours |
| `Escape` | Back to search |

### Log Tab

| Shortcut | Action |
|----------|--------|
| `↑` `↓` | Navigate entries |
| `←` `→` | Switch day (Yesterday ↔ Today ↔ Tomorrow) |
| `Enter` | Continue/toggle timer (today) / Start tracking (yesterday) |
| `⌘1`–`⌘9` | Jump to entry + start tracking immediately |
| `E` | Edit entry |
| `D` / `Delete` | Delete entry (with confirmation) |
| `F` | Toggle favorite |
| `Tab` | Switch to Track tab |
| Type | Switch to Track tab with typed character |

### Timeline

| Shortcut | Action |
|----------|--------|
| `⌘T` | Open Timeline from the quick-entry panel |
| `←` `→` | Switch day |
| Click + drag (empty area) | Create a new entry |
| Click + drag (entry) | Move entry on the time axis |
| Drag top/bottom edge | Resize entry |
| `Delete` / `Backspace` | Remove selected shadow entry |
| Right-click | Context menu (create from app block, edit, delete) |

### Edit Mode

| Shortcut | Action |
|----------|--------|
| `Enter` | Save changes |
| `Escape` | Cancel |

### Delete Confirmation

| Shortcut | Action |
|----------|--------|
| `Enter` / Click **Löschen** | Confirm delete |
| `Escape` / Click **Abbrechen** | Cancel |

---

## Tips & Tricks

| Tip | How |
|-----|-----|
| **Fastest timer start** | `⌘⌃⌥M` → type 3 chars → `Enter` → `Enter` — under 3 seconds |
| **Fastest pause/resume** | `⌘⌃⌥M` → `Enter` — under 1 second |
| **Continue yesterday's work** | Log → Yesterday → `Enter` on entry — starts new timer with same details |
| **Quick-start from Log** | `⌘1` in Log tab — instantly starts timer on first entry |
| **Check your day** | Left-click menubar icon → panel opens with Log tab showing entries + stats |
| **Fix yesterday's hours** | `←` in Log → navigate → `E` → edit hours → `Enter` |
| **Book past time** | Track → select → `Tab` (manual mode) → type hours → `Enter` |
| **Flexible hours input** | All equivalent: `1.5`, `1h 30m`, `1h30m`, `90m`, `1,5` |
| **Tag a ticket** | Type `#JIRA-123` in description — auto-extracted as a tag |
| **Wrong project?** | `E` to edit → click project name → search → pick correct one. Hours preserved. |
| **Favorites** | ⭐ Star your daily projects — they appear first in Track tab |
| **Plan your morning** | Set Default Tab to "Log" → see what's planned before starting |
| **Menubar dot colors** | 🔴 = idle, 🟢 = running, 🟠 = paused — glance without opening |
| **Timeline from panel** | `⌘T` opens the Timeline — see your full day at a glance |
| **Drag to create** | Drag in empty timeline space to create an entry for that exact time range |
| **App → entry** | Right-click any app usage block → "Create entry" pre-fills the time range |
| **Automate repeating work** | Create rules for apps/calendar events you use daily — entries are suggested automatically |
| **Calendar context** | Enable calendar in Settings → Timeline to see meetings alongside your time entries |

---

*MocoCompanion — track time without leaving your flow.*

# CLAUDE.md — Project Instructions for MocoCompanion

## Design Context

### Users
Professionals who track their hours in Moco daily — developers, designers, consultants, project managers at agencies and consultancies. They're in the middle of work when they use this: switching tasks, starting meetings, ending their day. The app must never break their flow. Context is "I need to track this in under 3 seconds and get back to what I was doing." German and English speakers, macOS power users comfortable with keyboard shortcuts.

### Brand Personality
**Friendly, polished, reliable.** A warm companion you trust through your workday — not a cold tool, not a toy. It should feel like a well-made watch: you glance at it, it tells you what you need, you move on. Approachable but never cute. Confident but never loud.

### Aesthetic Direction

**Visual tone:** Neutral and minimal. The UI is content-forward — color serves state (green=running, orange=paused, red=error/idle) not decoration. The vibrant app icon is the brand moment; the interface itself is calm, quiet, and fast. Think Raycast or Alfred: keyboard-first launcher aesthetic where density and speed are the design.

**References:** Raycast, Alfred — fast launchers with dense, efficient UIs that feel native to macOS. The panel floats like Spotlight, responds to keyboard instantly, and disappears when done.

**Anti-references:** Electron-style bloat — nothing heavy, slow, or over-animated. No gratuitous transitions, no loading spinners that could be avoided, no UI that makes you wait. If it feels like a web app pretending to be native, it's wrong.

**Theme:** Both light and dark, user-selectable plus system-follow. The existing `Theme.swift` color system is the source of truth — warm-tinted backgrounds (slight blue in dark, slight cool in light), three-tier text hierarchy, semantic state colors.

**Typography:** System font (SF Pro) throughout. No custom fonts. Monospaced for durations/timers. Rounded design for avatar initials and numeric display. Seven-step size scale defined in `Theme.FontSize` (caption 10 through largeTitle 22). User-adjustable font size boost (0–3pt) for entry rows.

**Spacing:** Compact but breathable. Panel horizontal padding 18pt, vertical 16pt. Entry rows: horizontal 12pt, vertical 8–10pt. HStack spacing 6–12pt depending on density. No rigid 4pt/8pt grid — spacing serves the content.

**Radius:** Three-tier: small (4pt badges/pills), medium (8pt cards/rows), large (14pt panel). All use `.continuous` style.

**Motion:** Minimal and purposeful. Three durations: fast 0.12s (exits, micro-feedback), standard 0.18s (state transitions), slow 0.30s (complex). `@Environment(\.accessibilityReduceMotion)` respected. `animationBehavior = .utilityWindow` on the panel. No decorative animations.

**Color palette:**
- Accent: System accent color (blue by default) — used for selection, CTAs, avatar backgrounds
- State: Green (running), orange (paused/warning), red (error/idle dot), yellow (favorites)
- Surfaces: Warm-tinted neutrals via opacity on white/black (not gray)
- Text: Three tiers at 0.92/0.72/0.55 opacity (dark) and 0.10-0.14/0.55/0.45 opacity-on-black (light)
- Never: Gradients in UI (reserved for icon only), saturated backgrounds, decorative color

### Design Principles

1. **Speed is the feature.** Every interaction path is optimized for minimum keystrokes. The UI exists to get out of the way. If a design choice makes the app feel slower — visually or mechanically — reject it.

2. **Native or nothing.** SwiftUI + AppKit, system font, system accent color, Keychain, Notification Center, NSPanel, SF Symbols. It should feel like it ships with macOS. No custom chrome that fights the platform.

3. **State over decoration.** Color communicates state (running, paused, error, favorite), not personality. When nothing is happening, the UI is quiet. Visual noise is a bug.

4. **Keyboard-first, mouse-welcome.** Every action is reachable via keyboard. Mouse/trackpad works everywhere but is never required. Focus states are always visible. The keyboard user and the mouse user see the same UI.

5. **Density with clarity.** Pack information tight — this is a utility panel, not a canvas app. But never sacrifice readability. Three-tier text hierarchy, consistent spacing, and selective bold weight keep dense layouts scannable.

<!-- hv-knowledge-start -->
## Project Knowledge

Durable learnings live in `.hv/KNOWLEDGE.md`. Consult it when work touches these topics:

- Build & Tooling
- Architecture
- Menubar

<!-- hv-knowledge-end -->

<!-- hv-vision-start -->
## Project Vision

Project milestones live in `.hv/MILESTONES.md`.

_(no milestones yet — run `/hv-vision` to brainstorm)_
<!-- hv-vision-end -->

<!-- hv-skills-start -->
## hv-skills

This project uses hv-skills for backlog tracking, planning, and skill orchestration. State lives in `.hv/` — most content is tracked (backlog, knowledge, decisions, plans, designs, milestones) so it travels with the repo. Only `.hv/bin/` (regenerated mirror of canonical `bin/`, overwritten on every `/hv-init`), `.hv/status.json`, `.hv/repos.json`, `.hv/config.local.json`, `.hv/handoff/`, and `.hv/qa-runs/` are gitignored. Use the skill helpers to update tracked content (never edit by hand). Edit canonical sources (`bin/`, `hv-*/`, `docs/`, `test/`) for skill changes.

**Capture & pick** — `/hv-capture` (with `--remove <ID>` to delete items), `/hv-go`, `/hv-next`, `/hv-pause`
**Plan & build** — `/hv-brainstorm`, `/hv-plan`, `/hv-spike`, `/hv-work` (`--preview` for read-only peek), `/hv-debug`
**Review & ship** — `/hv-review`, `/hv-qa` (opt-in gate via `ship.qa`), `/hv-ship` (`--undo` to roll back the last cycle, `--docs` to maintain public docs)
**Persist** — `/hv-learn` (durable knowledge; `--term <name>` for glossary), `/hv-decide` (hard boundaries — manual only)
**Vision & maps** — `/hv-vision`, `/hv-refactor`
**Maintenance** — `/hv-init`, `/hv-config`, `/hv-update`, `/hv-migrate` (v3→v4 codemod), `/hv-release`

Before acting on work that touches a topic listed in `## Project Knowledge`, `## Project Decisions`, or `## Project Vision`, pull only the relevant sections:

- `.hv/bin/hv-knowledge-query <topic>…`
- `.hv/bin/hv-decisions-query <topic>…`
- `.hv/bin/hv-glossary-read <term>…` (terms live as nested-bullet entries under `## Glossary` in `.hv/KNOWLEDGE.md`)
- `.hv/bin/hv-vision-active` (then `.hv/bin/hv-todo-by-milestone <id>` per active milestone)
<!-- hv-skills-end -->

<!-- hv-decisions-start -->
## Project Decisions

Hard boundaries live in `.hv/DECISIONS.md`. Consult them before acting on work that touches these topics:

- _(no decisions yet — run `/hv-decide` to capture a hard boundary)_

<!-- hv-decisions-end -->

<!-- hv-map-start -->
## Project Map

Subsystems live in `.hv/MAP.md` (detail in `.hv/map/<name>.md`). Pull with `.hv/bin/hv-map-query <name>`.

- _(no subsystems yet — write `.hv/map/<name>.md` as you discover subsystems)_
<!-- hv-map-end -->

<!-- hv-context-start -->
## Project Context

Domain terminology lives in `.hv/CONTEXT.md`. Use these canonical names; if a term you're using conflicts (synonym or drift), call it out.

- _(no terms yet — run `/hv-context` to capture domain terminology)_
<!-- hv-context-end -->

<!-- hv-qa-start -->
## Project QA

QA strategies live in `.hv/QA.md` (detail in `.hv/qa/<target>.md`). Pull with `.hv/bin/hv-qa-query <target>`. `/hv-qa run` consumes these; the skill never hardcodes runners.

- _(no QA strategy yet — run `/hv-qa first-run` to scaffold)_
<!-- hv-qa-end -->

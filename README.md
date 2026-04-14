# MocoCompanion

A fast, keyboard-driven macOS menu bar companion for [MOCO](https://www.mocoapp.com) time tracking.

<img src="docs/screenshots/Log.png" alt="MocoCompanion Log View" width="667">

[Installation](#installation) · [Features](#features) · [Documentation](docs/README.md) · [Requirements](#requirements)

## Features

### Quick Entry Panel
- Global hotkey (`⌘⌃⌥M`) to start/stop timers without leaving your current app
- Fuzzy search across all assigned projects and tasks
- Favorites and recent entries for instant access
- Manual time booking with flexible hour formats (`1.5`, `1h 30m`, `90m`)
- `#TICKET-123` tag extraction from descriptions
- Description autocomplete from your history

### Log View
- Today/Yesterday/Tomorrow views with planned vs tracked hours
- Inline editing of descriptions, hours, and project reassignment
- Keyboard shortcuts for every action (`E` edit, `D` delete, `F` favorite)
- Budget monitoring with project and task-level warnings
- Stats footer with total hours, billable percentage, and entry count

### Timeline & Autotracker
- Visual timeline with dual-column layout — app usage blocks alongside Moco entries
- Autotracker records which apps you use and suggests matching time entries
- Calendar integration — see events inline on the timeline
- Drag to create, move, and resize entries directly on the timeline
- Rule engine — auto-match app usage or calendar events to projects and tasks
- Bidirectional sync engine with shadow entries and conflict resolution

### System Integration
- Native macOS menu bar app (SwiftUI + AppKit)
- Light/Dark mode with customizable appearance
- German and English localization
- Idle reminders, forgotten timer alerts, and end-of-day summaries
- API key stored securely in the macOS Keychain

## Installation

### Homebrew (recommended)

```bash
brew install --cask l4ci/tap/mococompanion
```

### Manual

Download the latest release from [GitHub Releases](https://github.com/l4ci/MocoCompanion/releases) and drag `MocoCompanion.app` to your Applications folder.

## Setup

1. Open MocoCompanion — it appears as a menu bar icon
2. Enter your MOCO subdomain and API key in Settings (Get it from [here](https://{MOCO Subdomain}.mocoapp.com/profile/integrations))
3. Press `⌃⌥⌘M` (or your custom shortcut) to open the quick-entry panel or click on the menu bar icon

Your API key is stored securely in the macOS Keychain.

## Requirements

- macOS 26.0 (Tahoe) or later
- A MOCO account with API access

## Disclaimer

MocoCompanion is an **independent, unofficial** companion app for [MOCO](https://www.mocoapp.com). It is **not affiliated with, endorsed by, or associated with hundertzehn GmbH**.

"MOCO" is a trademark of hundertzehn GmbH, Zürich, Switzerland.

This app uses the public MOCO API. Users must have their own MOCO account and API credentials. No data is stored or transmitted to any third party — all communication happens directly between the app and your MOCO instance.

## License

[MIT](LICENSE) — Copyright (c) 2026 Volker Otto

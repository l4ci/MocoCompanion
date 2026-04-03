# MocoCompanion

A fast, keyboard-driven macOS menu bar companion for [MOCO](https://www.mocoapp.com) time tracking.

## Features

- ⌨️ Global hotkey to start/stop timers without leaving your current app
- 🔍 Fuzzy search across all assigned projects and tasks
- 📋 Today/Yesterday/Tomorrow views with planned vs tracked hours
- ⭐ Favorites and recent entries for quick access
- 💰 Budget monitoring with project and task-level warnings
- 🔔 Idle reminders, forgotten timer alerts, and end-of-day summaries
- 🎨 Light/Dark mode with customizable appearance
- 🇩🇪 German and English localization

## Installation

### Homebrew (recommended)

```bash
brew tap l4ci/mococompanion
brew install --cask mococompanion
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

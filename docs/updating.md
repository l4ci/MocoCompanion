# Updating MocoCompanion

Quit MocoCompanion before updating — the app must be closed so the new version can replace it. After updating, relaunch from your Applications folder or Spotlight.

## Homebrew (recommended)

If you installed MocoCompanion via Homebrew, run:

```bash
brew update && brew upgrade --cask mococompanion
```

`brew update` refreshes the formula index so Homebrew knows about the latest version. Without it, `brew upgrade` may silently skip the update.

## Manual download

Download the latest `.zip` from the [GitHub Releases page](https://github.com/l4ci/MocoCompanion/releases), unzip, and drag **MocoCompanion.app** into your Applications folder, replacing the old version.

## Verify

After updating, check your version in the menu bar: click the MocoCompanion icon → **Settings** → **General**. The version number is shown at the bottom.

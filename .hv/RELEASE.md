# Release Checklist — MocoCompanion

MocoCompanion ships as a signed/notarized macOS app distributed via GitHub Releases and a Homebrew tap. The full release pipeline lives in `scripts/release.sh` — **`/hv-release` is NOT sufficient on its own** because it does not build, sign, notarize, or update the Homebrew tap.

## How to release

Run the project pipeline, not `/hv-release`:

```bash
./scripts/release.sh <X.Y.Z>
```

The script bumps `MARKETING_VERSION` in `project.pbxproj` via sed, commits, tags, builds, signs, notarizes, pushes, creates the GitHub release (with `--generate-notes` — see manual edit step below), then updates the `l4ci/homebrew-tap` cask. Read `scripts/release.sh` end-to-end before invoking; it edits two repos and three remote artifacts.

## Pre-release gates

Each `- [ ]` line is a gate `/hv-release` walks before bumping the version. They also apply when running `scripts/release.sh` manually — work through them first.

- [ ] CHANGELOG.md has a section for the new version (write it BEFORE running the script; `--generate-notes` is just commit titles) (manual)
- [ ] `project.yml` `MARKETING_VERSION` matches the target (run `xcodegen` if you changed it; the script edits `project.pbxproj` directly, so drift between the two files is a known foot-gun) (manual)
- [ ] Developer ID Application certificate is in Keychain (`security find-identity -v -p codesigning`) (manual)
- [ ] Notarization credentials stored (`xcrun notarytool store-credentials "notarytool-profile"`) (manual)
- [ ] `gh auth status` is logged in
- [ ] `l4ci/homebrew-tap` is accessible via SSH (`ssh -T git@github.com` works; the script will switch HTTPS → SSH if needed)
- [ ] `main` is clean, pushed, and CI is green
- [ ] Working from inside the umbrella repo root, not a worktree (the script `cd`s relative paths)

## Post-release follow-up

- [ ] Replace `--generate-notes` body with the curated CHANGELOG.md section: `gh release edit v<X.Y.Z> --notes-file <path>` (manual)
- [ ] Verify the cask install works: `brew update && brew install --cask l4ci/tap/mococompanion`
- [ ] Smoke-test the signed .app from the GitHub release ZIP (Gatekeeper should accept it without right-click-open)

## Known issues

- `project.yml` ↔ `project.pbxproj` drift: `scripts/release.sh` edits `project.pbxproj` via sed but ignores `project.yml`. Anyone running `xcodegen` afterwards will overwrite the just-bumped version. Fix path: either teach the script to bump `project.yml` first then run `xcodegen`, or drop `project.yml` if Tuist/xcodegen isn't actively used.

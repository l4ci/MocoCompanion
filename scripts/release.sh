#!/bin/bash
set -euo pipefail

# Full release pipeline: bump version → build → sign → notarize → GitHub release → update Homebrew tap.
# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 0.5.0
#
# Prerequisites:
#   - Developer ID certificate in Keychain
#   - Notarytool credentials: xcrun notarytool store-credentials "notarytool-profile"
#   - gh CLI authenticated
#   - l4ci/homebrew-tap repo cloned (auto-cloned if missing)

REPO="l4ci/MocoCompanion"
TAP_REPO="l4ci/homebrew-tap"
TAP_DIR="/tmp/homebrew-tap"

if [ $# -eq 0 ]; then
    echo "Usage: ./scripts/release.sh <version>"
    echo "Example: ./scripts/release.sh 0.5.0"
    exit 1
fi

VERSION="$1"

echo "=== Releasing MocoCompanion v${VERSION} ==="
echo ""

# ── 1. Bump version in Xcode project ─────────────────────────────
echo "[1/9] Bumping version to ${VERSION}..."
sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $VERSION/" \
    MocoCompanion.xcodeproj/project.pbxproj

# Verify it took
FOUND=$(grep "MARKETING_VERSION = $VERSION" MocoCompanion.xcodeproj/project.pbxproj | wc -l | tr -d ' ')
if [ "$FOUND" -eq 0 ]; then
    echo "ERROR: Version bump failed — MARKETING_VERSION not updated"
    exit 1
fi
echo "    Updated MARKETING_VERSION in $FOUND places"

# ── 2. Commit + tag ──────────────────────────────────────────────
echo "[2/9] Committing and tagging..."
git add MocoCompanion.xcodeproj/project.pbxproj
git commit -m "Bump version to v${VERSION}"
git tag "v${VERSION}"

# ── 3. Build, sign, notarize ─────────────────────────────────────
echo "[3/9] Building release..."
./scripts/build-release.sh "$VERSION"

ZIP_NAME="MocoCompanion-${VERSION}.zip"
if [ ! -f "$ZIP_NAME" ]; then
    echo "ERROR: Build did not produce $ZIP_NAME"
    exit 1
fi

SHA=$(shasum -a 256 "$ZIP_NAME" | awk '{print $1}')
echo "    SHA256: $SHA"

# ── 4. Push to GitHub ────────────────────────────────────────────
echo "[4/9] Pushing to GitHub..."
git push origin main --tags

# ── 5. Create GitHub Release ─────────────────────────────────────
echo "[5/9] Creating GitHub Release..."
gh release create "v${VERSION}" "$ZIP_NAME" \
    --repo "$REPO" \
    --title "MocoCompanion v${VERSION}" \
    --generate-notes

# ── 6. Update Homebrew tap ────────────────────────────────────────
echo "[6/9] Updating Homebrew tap..."
if [ -d "$TAP_DIR" ]; then
    cd "$TAP_DIR" && git pull origin main
else
    git clone "git@github.com:${TAP_REPO}.git" "$TAP_DIR"
fi

# Ensure remote uses SSH so pushes work
cd "$TAP_DIR"
REMOTE_URL=$(git remote get-url origin)
if [[ "$REMOTE_URL" == https://* ]]; then
    echo "    Switching tap remote from HTTPS to SSH..."
    git remote set-url origin "git@github.com:${TAP_REPO}.git"
fi

CASK_FILE="$TAP_DIR/Casks/mococompanion.rb"
if [ ! -f "$CASK_FILE" ]; then
    echo "ERROR: Cask file not found at $CASK_FILE"
    exit 1
fi

sed -i '' "s/version \"[^\"]*\"/version \"$VERSION\"/" "$CASK_FILE"
sed -i '' "s/sha256 \"[^\"]*\"/sha256 \"$SHA\"/" "$CASK_FILE"

# ── 7. Push tap update ───────────────────────────────────────────
echo "[7/9] Pushing tap update..."
cd "$TAP_DIR"
git add Casks/mococompanion.rb
git commit -m "Update MocoCompanion to v${VERSION}"
git push origin main

# ── 8. Verify tap update ─────────────────────────────────────────
echo "[8/9] Verifying tap update on GitHub..."
REMOTE_VERSION=$(gh api "repos/${TAP_REPO}/contents/Casks/mococompanion.rb" --jq '.content' | base64 -d | grep 'version "' | head -1 | sed 's/.*version "\([^"]*\)".*/\1/')
if [ "$REMOTE_VERSION" != "$VERSION" ]; then
    echo "ERROR: Tap verification failed! Remote shows v${REMOTE_VERSION}, expected v${VERSION}"
    echo "  Fix manually: update Casks/mococompanion.rb in ${TAP_REPO}"
    exit 1
fi
echo "    Verified: tap shows v${REMOTE_VERSION}"

# ── 9. Done ──────────────────────────────────────────────────────
cd - > /dev/null
echo ""
echo "=== Released MocoCompanion v${VERSION} ==="
echo ""
echo "  GitHub:   https://github.com/${REPO}/releases/tag/v${VERSION}"
echo "  Homebrew: brew install --cask l4ci/tap/mococompanion"
echo "  SHA256:   $SHA"
echo ""
echo "⚠️  IMPORTANT: Edit the release notes on GitHub!"
echo "  The release was created with --generate-notes (commit list only)."
echo "  Add: user-facing changelog, install/update instructions, manual download note."
echo "  → gh release edit v${VERSION} --notes-file NOTES.md"
echo "  Or: https://github.com/${REPO}/releases/edit/v${VERSION}"

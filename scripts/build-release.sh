#!/bin/bash
set -euo pipefail

# Build, sign, notarize, and package MocoCompanion.app for distribution.
# Usage: ./scripts/build-release.sh [version]
# Example: ./scripts/build-release.sh 0.4.0
#
# Prerequisites (one-time):
#   1. Developer ID Application certificate in Keychain
#   2. Notarytool credentials stored:
#      xcrun notarytool store-credentials "notarytool-profile" \
#        --apple-id YOUR@EMAIL --team-id T85ZX7E2CQ --password APP_SPECIFIC_PASSWORD

TEAM_ID="T85ZX7E2CQ"
SIGNING_IDENTITY="Developer ID Application: Volker Otto ($TEAM_ID)"
NOTARYTOOL_PROFILE="notarytool-profile"

VERSION="${1:-$(grep MARKETING_VERSION MocoCompanion.xcodeproj/project.pbxproj | head -1 | sed 's/.*= //' | tr -d '";')}"
SCHEME="MocoCompanion"
CONFIG="Release"
ARCHIVE_PATH="build/MocoCompanion.xcarchive"
EXPORT_PATH="build/export"
APP_PATH="$EXPORT_PATH/MocoCompanion.app"
ZIP_NAME="MocoCompanion-${VERSION}.zip"

echo "=== MocoCompanion v${VERSION} ==="
echo ""

# ── 1. Clean ──────────────────────────────────────────────────────
echo "[1/6] Cleaning..."
rm -rf build/

# ── 2. Archive ────────────────────────────────────────────────────
echo "[2/6] Archiving..."
xcodebuild \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -archivePath "$ARCHIVE_PATH" \
    archive \
    MARKETING_VERSION="$VERSION" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    CODE_SIGN_STYLE=Manual \
    2>&1 | tail -3

# ── 3. Export + sign ──────────────────────────────────────────────
echo "[3/6] Exporting and signing..."
mkdir -p "$EXPORT_PATH"
cp -R "$ARCHIVE_PATH/Products/Applications/MocoCompanion.app" "$EXPORT_PATH/"

# Re-sign with Developer ID (archive may use development cert)
codesign --force --deep --options runtime \
    --sign "$SIGNING_IDENTITY" \
    --entitlements "MocoCompanion/MocoCompanion.entitlements" \
    "$APP_PATH"

# Verify signature
echo "    Verifying signature..."
codesign --verify --verbose=2 "$APP_PATH" 2>&1 | tail -2
spctl --assess --type execute --verbose "$APP_PATH" 2>&1 || true

# ── 4. Create ZIP for notarization ────────────────────────────────
echo "[4/6] Creating ZIP for notarization..."
ditto -c -k --keepParent "$APP_PATH" "build/$ZIP_NAME"

# ── 5. Notarize ──────────────────────────────────────────────────
echo "[5/6] Submitting for notarization (this may take a few minutes)..."
xcrun notarytool submit "build/$ZIP_NAME" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait

# ── 6. Staple ─────────────────────────────────────────────────────
echo "[6/6] Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"

# Re-create ZIP with stapled app
rm "build/$ZIP_NAME"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_NAME"

# Calculate SHA256 for Homebrew
SHA=$(shasum -a 256 "$ZIP_NAME" | awk '{print $1}')

echo ""
echo "=== Done ==="
echo "  Archive: $ZIP_NAME"
echo "  SHA256:  $SHA"
echo ""
echo "Homebrew cask formula:"
echo "  version \"$VERSION\""
echo "  sha256 \"$SHA\""
echo "  url \"https://github.com/l4ci/MocoCompanion/releases/download/v${VERSION}/${ZIP_NAME}\""
echo ""
echo "Next: upload $ZIP_NAME to GitHub Releases as v${VERSION}"

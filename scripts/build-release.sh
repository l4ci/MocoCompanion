#!/bin/bash
set -euo pipefail

# Build a distributable ZIP of MocoCompanion.app
# Usage: ./scripts/build-release.sh [version]
# Example: ./scripts/build-release.sh 0.1.0

VERSION="${1:-$(grep MARKETING_VERSION MocoCompanion.xcodeproj/project.pbxproj | head -1 | sed 's/.*= //' | tr -d '";')}"
SCHEME="MocoCompanion"
CONFIG="Release"
ARCHIVE_PATH="build/MocoCompanion.xcarchive"
EXPORT_PATH="build/export"
ZIP_NAME="MocoCompanion-${VERSION}.zip"
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

echo "🏗  Building MocoCompanion v${VERSION}..."

# Clean
rm -rf build/

# Archive
DEVELOPER_DIR="$DEVELOPER_DIR" xcodebuild \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -archivePath "$ARCHIVE_PATH" \
    archive \
    MARKETING_VERSION="$VERSION" \
    2>&1 | tail -5

# Export the app from the archive
mkdir -p "$EXPORT_PATH"
cp -R "$ARCHIVE_PATH/Products/Applications/MocoCompanion.app" "$EXPORT_PATH/"

# Strip extended attributes (prevents Gatekeeper issues)
xattr -cr "$EXPORT_PATH/MocoCompanion.app"

# Create ZIP
cd "$EXPORT_PATH"
zip -r -y "../../$ZIP_NAME" "MocoCompanion.app"
cd ../..

# Calculate SHA256 for Homebrew
SHA=$(shasum -a 256 "$ZIP_NAME" | awk '{print $1}')

echo ""
echo "✅ Built: $ZIP_NAME"
echo "📦 SHA256: $SHA"
echo ""
echo "Homebrew cask formula snippet:"
echo "  version \"$VERSION\""
echo "  sha256 \"$SHA\""
echo "  url \"https://github.com/l4ci/MocoCompanion/releases/download/v${VERSION}/${ZIP_NAME}\""

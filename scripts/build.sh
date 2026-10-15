#!/bin/bash
# Builds a universal Kairos.app and a release zip into ./build
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Kairos"

APP=build/Kairos.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Kairos"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature whose identity is the bundle ID, so macOS keeps the
# Accessibility permission across updates instead of asking again.
codesign --force --sign - \
    --requirements '=designated => identifier "com.muneerraza.kairos"' "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
ZIP="build/Kairos-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Built $APP"
echo "Built $ZIP  sha256 $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"

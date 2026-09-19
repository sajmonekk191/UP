#!/bin/zsh
# Builds UP! for Apple Silicon and Intel and packs it into a DMG and a ZIP for a GitHub release.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh --universal
APP="dist/UP!.app"
PLIST="$APP/Contents/Info.plist"

if [[ -n "${1:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${1}" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${1}" "$PLIST"
  codesign --force --deep --sign - "$APP"
fi
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")

DMG="dist/UP-$VERSION.dmg"
ZIP="dist/UP-$VERSION.zip"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG" "$ZIP"
hdiutil create -volname "UP! $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
ditto -c -k --keepParent "$APP" "$ZIP"

lipo -archs "$APP/Contents/MacOS/UP"
shasum -a 256 "$DMG" "$ZIP"
echo "Hotovo: $DMG a $ZIP"

#!/bin/bash
# Packages build/AudioDiverger.app into build/AudioDiverger-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
STAGE=build/dmg
DMG="build/AudioDiverger-$VERSION.dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/AudioDiverger.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "AudioDiverger" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "✅ $DMG"

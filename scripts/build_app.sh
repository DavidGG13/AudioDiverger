#!/bin/bash
# Builds build/AudioDiverger.app. Pass --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/AudioDiverger"

APP="build/AudioDiverger.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AudioDiverger"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature (enough to run locally and to get the audio-capture prompt).
codesign --force --sign - --timestamp=none "$APP"
echo "✅ Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    osascript -e 'quit app "AudioDiverger"' 2>/dev/null || true
    rm -rf /Applications/AudioDiverger.app
    cp -R "$APP" /Applications/
    echo "✅ Installed to /Applications/AudioDiverger.app"
fi

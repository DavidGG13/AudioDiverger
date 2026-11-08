#!/bin/bash
# Builds build/AudioDiverger.app.
#   --universal   build for Apple silicon + Intel
#   --install     copy the app to /Applications
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH_FLAGS=()
INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --universal) ARCH_FLAGS=(--arch arm64 --arch x86_64) ;;
        --install) INSTALL=1 ;;
    esac
done

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/AudioDiverger"

APP="build/AudioDiverger.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AudioDiverger"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature: enough to run and to get the audio-capture prompt.
codesign --force --sign - --timestamp=none "$APP"
echo "✅ Built $APP"

if [[ $INSTALL == 1 ]]; then
    osascript -e 'quit app "AudioDiverger"' 2>/dev/null || true
    rm -rf /Applications/AudioDiverger.app
    cp -R "$APP" /Applications/
    echo "✅ Installed to /Applications/AudioDiverger.app"
fi

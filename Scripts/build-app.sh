#!/bin/bash
# Builds MarkEditor.app from the SwiftPM executable + Support/Info.plist.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="${1:-release}"

swift build -c "$CONFIGURATION"

BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)/MarkEditor"
APP_PATH="build/MarkEditor.app"

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

cp Support/Info.plist "$APP_PATH/Contents/Info.plist"
cp "$BIN_PATH" "$APP_PATH/Contents/MacOS/MarkEditor"

if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$APP_PATH/Contents/Resources/AppIcon.icns"
fi

codesign --force --sign - "$APP_PATH"

echo "OK: $APP_PATH"

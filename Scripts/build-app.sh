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

# Stamp the build with the git hash so "Sobre o MarkEditor" identifies it.
GIT_HASH="$(git rev-parse --short HEAD 2>/dev/null || echo dev)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $GIT_HASH" "$APP_PATH/Contents/Info.plist"

if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$APP_PATH/Contents/Resources/AppIcon.icns"
fi

# Localizations: compile the string catalogs into <lang>.lproj folders.
# xcstringstool ships with Xcode; without it the app still runs, in English.
if xcrun --find xcstringstool >/dev/null 2>&1; then
    for catalog in Resources/*.xcstrings; do
        xcrun xcstringstool compile "$catalog" --output-directory "$APP_PATH/Contents/Resources"
    done
else
    echo "warning: xcstringstool not found (install Xcode); the app will run in English only"
fi

# Localized welcome guide: Resources/Welcome/<lang>.lproj/Welcome.md.
if [[ -d Resources/Welcome ]]; then
    cp -R Resources/Welcome/ "$APP_PATH/Contents/Resources/"
fi

codesign --force --sign - "$APP_PATH"

echo "OK: $APP_PATH"

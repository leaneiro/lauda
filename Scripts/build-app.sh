#!/bin/bash
# Builds Lauda.app from the SwiftPM executable + Support/Info.plist.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="${1:-release}"

swift build -c "$CONFIGURATION"

BIN_PATH="$(swift build -c "$CONFIGURATION" --show-bin-path)/Lauda"
APP_PATH="build/Lauda.app"

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

cp Support/Info.plist "$APP_PATH/Contents/Info.plist"
cp "$BIN_PATH" "$APP_PATH/Contents/MacOS/Lauda"

# Stamp the build with the git hash so "About Lauda" identifies it.
GIT_HASH="$(git rev-parse --short HEAD 2>/dev/null || echo dev)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $GIT_HASH" "$APP_PATH/Contents/Info.plist"

# App icon, and the icon Finder shows on Markdown files (Info.plist maps it).
for icon in AppIcon DocumentIcon; do
    if [[ -f "Resources/$icon.icns" ]]; then
        cp "Resources/$icon.icns" "$APP_PATH/Contents/Resources/$icon.icns"
    fi
done

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

# The preview's stylesheet and script (Sources/Lauda/Preview).
cp Sources/Lauda/Preview/preview.css Sources/Lauda/Preview/preview.js "$APP_PATH/Contents/Resources/"

codesign --force --sign - "$APP_PATH"

echo "OK: $APP_PATH"

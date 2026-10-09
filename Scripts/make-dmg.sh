#!/bin/bash
# Builds a distributable DMG: the classic window with Lauda on the left, the
# Applications folder on the right and an arrow between them, and nothing
# else. The Finder lays the window out on the writable image (icon view,
# fixed positions, the background from Resources/DMG) and keeps that in the
# volume's .DS_Store, which the compressed image carries. The app is
# universal, so one image serves Apple silicon and Intel Macs.
#
# Optional (requires Apple Developer Program), sign for frictionless install:
#   SIGN_IDENTITY="Developer ID Application: Seu Nome (TEAMID)" Scripts/make-dmg.sh
# and then notarize the result:
#   xcrun notarytool submit build/Lauda-<versao>.dmg --keychain-profile <perfil> --wait
#   xcrun stapler staple build/Lauda-<versao>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

Scripts/build-app.sh release

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" build/Lauda.app/Contents/Info.plist)"
DMG="build/Lauda-${VERSION}.dmg"
STAGING="build/dmg-staging"
VOLNAME="Lauda"
# The window and where the icons sit in it, which the background's arrow is
# drawn for (Scripts/make-dmg-background.swift): 660 by 400 points, the
# icons 128 points wide, centred 170 points down.
WINDOW_WIDTH=660
WINDOW_HEIGHT=400
ICON_SIZE=128
LAUDA_X=180
APPLICATIONS_X=480
ICON_Y=170

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" build/Lauda.app
fi

hdiutil detach "/Volumes/$VOLNAME" >/dev/null 2>&1 || true
rm -rf "$STAGING" "$DMG" build/tmp.dmg
mkdir -p "$STAGING/.background"
cp -R build/Lauda.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cp Resources/DMG/background.tiff "$STAGING/.background/background.tiff"

hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" -format UDRW -ov build/tmp.dmg >/dev/null

# Mounted writable: the volume gets the app icon, and the Finder lays the
# window out. The Finder has to show the window to write the layout, so it
# appears for a moment.
MOUNT_DIR="$(hdiutil attach build/tmp.dmg -nobrowse | grep -o '/Volumes/.*$' | tail -1)"
# A failure past this point must not leave the image mounted.
trap 'hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true' EXIT
if [[ -f Resources/AppIcon.icns && -d "$MOUNT_DIR" ]]; then
    cp Resources/AppIcon.icns "$MOUNT_DIR/.VolumeIcon.icns"
    xcrun SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
fi
osascript - "$MOUNT_DIR" "$WINDOW_WIDTH" "$WINDOW_HEIGHT" "$ICON_SIZE" "$LAUDA_X" "$APPLICATIONS_X" "$ICON_Y" <<'EOF'
on run {mountDir, windowWidth, windowHeight, iconSize, laudaX, applicationsX, iconY}
    set volumeName to do shell script "basename " & quoted form of mountDir
    tell application "Finder"
        tell disk volumeName
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set bounds of container window to {200, 160, 200 + (windowWidth as integer), 160 + (windowHeight as integer)}
            set viewOptions to icon view options of container window
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to iconSize as integer
            set background picture of viewOptions to file ".background:background.tiff"
            set position of item "Lauda.app" to {laudaX as integer, iconY as integer}
            set position of item "Applications" to {applicationsX as integer, iconY as integer}
            -- The Finder writes the layout to .DS_Store when the window closes.
            delay 1
            close
            delay 1
        end tell
    end tell
end run
EOF
# The Finder writes the layout once the window is closed; wait for it.
for _ in $(seq 1 20); do
    [[ -f "$MOUNT_DIR/.DS_Store" ]] && break
    sleep 0.5
done
[[ -f "$MOUNT_DIR/.DS_Store" ]] || { echo "error: the Finder did not write the window layout" >&2; exit 1; }
# Nothing but the layout goes into the image.
rm -rf "$MOUNT_DIR/.fseventsd" "$MOUNT_DIR/.Trashes"
sync
for attempt in 1 2 3; do
    hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 && break
    [[ $attempt -eq 3 ]] && { echo "error: could not detach $MOUNT_DIR" >&2; exit 1; }
    sleep 1
done
trap - EXIT

hdiutil convert build/tmp.dmg -format UDZO -o "$DMG" >/dev/null
rm -f build/tmp.dmg
rm -rf "$STAGING"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi

echo "OK: $DMG"

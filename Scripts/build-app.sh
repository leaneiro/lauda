#!/bin/bash
# Builds Lauda.app from the SwiftPM executable + Support/Info.plist.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="${1:-release}"

# Universal by default, so the app runs natively on Apple silicon and Intel
# Macs. ARCHS="$(uname -m)" builds for this Mac only, which is quicker while
# iterating.
ARCHS="${ARCHS:-arm64 x86_64}"
# Each architecture is built on its own with SwiftPM's native build system,
# then the two are joined. Swift Build, the default since Swift 6.4 and the
# only one SwiftPM uses for several architectures at once, links the app
# with its deployment target (14.0) recorded as the SDK it was built with,
# and macOS then runs it as an app of that time: measured on macOS 27, the
# toolbar's controls left the trailing edge. Built natively, the binary
# records the SDK it was really built with. Each architecture keeps a build
# folder of its own: sharing one, the second build failed on the first's
# records ("not registered").
BINARIES=()
for arch in $ARCHS; do
    BUILD_FLAGS=(-c "$CONFIGURATION" --arch "$arch" --build-system native --scratch-path ".build/native-$arch")
    swift build "${BUILD_FLAGS[@]}"
    BINARIES+=("$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)/Lauda")
done

APP_PATH="build/Lauda.app"

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

cp Support/Info.plist "$APP_PATH/Contents/Info.plist"
lipo -create "${BINARIES[@]}" -output "$APP_PATH/Contents/MacOS/Lauda"
for arch in $ARCHS; do
    if ! lipo "$APP_PATH/Contents/MacOS/Lauda" -verify_arch "$arch"; then
        echo "error: the app binary has no $arch code" >&2
        exit 1
    fi
done

# Stamp the build with the git hash so "About Lauda" identifies it.
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

# The preview's stylesheet and script (Sources/Lauda/Preview).
cp Sources/Lauda/Preview/preview.css Sources/Lauda/Preview/preview.js \
    Sources/Lauda/Preview/LaudaWordmark.woff Sources/Lauda/Preview/Newsreader-OFL.txt \
    "$APP_PATH/Contents/Resources/"

codesign --force --sign - "$APP_PATH"

echo "OK: $APP_PATH"

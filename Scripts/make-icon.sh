#!/bin/bash
# Builds Resources/AppIcon.icns from the PNGs in Resources/Icons. Each is
# drawn on its own from Resources/Icons/AppIcon.svg, with the white body's
# sides on whole pixels, so the small ones stay crisp instead of being
# scaled down from 1024. The Electron edition draws them, with its
#   npm run icons -- --mac ../markeditor/Resources/Icons
set -euo pipefail
cd "$(dirname "$0")/.."

build_icns() {
    local name="$1"
    local iconset="build/icon/$name.iconset"
    rm -rf "$iconset"
    mkdir -p "$iconset"
    for size in 16 32 128 256 512; do
        cp "Resources/Icons/$name-$size.png" "$iconset/icon_${size}x${size}.png"
        cp "Resources/Icons/$name-$((size * 2)).png" "$iconset/icon_${size}x${size}@2x.png"
    done
    iconutil -c icns -o "Resources/$name.icns" "$iconset"
    echo "OK: Resources/$name.icns"
}

build_icns AppIcon

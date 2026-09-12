#!/bin/bash
# Builds Resources/AppIcon.icns from the PNGs
# in Resources/Icons. Every size is its own hand-tuned drawing, so the small
# ones stay crisp instead of being scaled down from 1024.
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

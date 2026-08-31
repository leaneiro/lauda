#!/bin/bash
# Regenerates Resources/AppIcon.icns from Scripts/GenerateIcon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK_DIR="build/icon"
ICONSET="$WORK_DIR/AppIcon.iconset"
rm -rf "$WORK_DIR"
mkdir -p "$ICONSET"

swift Scripts/GenerateIcon.swift "$WORK_DIR/icon_1024.png"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$WORK_DIR/icon_1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$WORK_DIR/icon_1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

mkdir -p Resources
iconutil -c icns -o Resources/AppIcon.icns "$ICONSET"
echo "OK: Resources/AppIcon.icns"

#!/bin/bash
# Regenerates Sources/Lauda/Preview/LaudaWordmark.woff: Newsreader SemiBold at
# the 72 pt optical size (the typeface of the app icon's L), cut down to the
# letters of "Lauda". Copyright and license names stay inside the font.
# Needs fontTools (pip install fonttools).
#   Scripts/make-wordmark-font.sh path/to/Newsreader-VariableFont_opsz,wght.ttf
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCE="${1:?usage: $0 path/to/Newsreader-VariableFont_opsz,wght.ttf}"
WORK_DIR="build/wordmark"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

fonttools varLib.instancer "$SOURCE" wght=600 opsz=72 -o "$WORK_DIR/instance.ttf"
pyftsubset "$WORK_DIR/instance.ttf" --text="Lauda" --no-hinting --layout-features='*' \
    --name-IDs='*' --flavor=woff --output-file=Sources/Lauda/Preview/LaudaWordmark.woff
echo "OK: Sources/Lauda/Preview/LaudaWordmark.woff"

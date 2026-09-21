#!/bin/zsh
# Lint that catches slips, not style. The Swift here is formatted by hand,
# and swift-format's opinions on indentation, blank lines, line length and
# the semicolons a scanner uses differ from the project's, so those are
# left out (see .swift-format for the rules that are off altogether).
# Everything else it finds is a genuine slip and fails the build.
set -u
cd "$(dirname "$0")/.."

ignored='Indentation|AddLines|LineLength|TrailingComma|DoNotUseSemicolons'
found=$(swift format lint --recursive Sources Tests 2>&1 \
    | grep 'warning: \[' \
    | grep -vE "\[($ignored)\]")

if [ -n "$found" ]; then
    echo "$found"
    echo "swift format lint: $(echo "$found" | wc -l | tr -d ' ') to fix"
    exit 1
fi
echo "OK: swift format lint"

# The preview's script, with the rules that don't fit it turned off in
# biome.json. Skipped where there is no npx, so the script still runs on a
# machine without Node.
if command -v npx >/dev/null 2>&1; then
    npx --yes @biomejs/biome@2 lint Sources/Lauda/Preview/preview.js || exit 1
    echo "OK: biome"
elif command -v node >/dev/null 2>&1; then
    node --check Sources/Lauda/Preview/preview.js || exit 1
    echo "OK: preview.js parses"
fi

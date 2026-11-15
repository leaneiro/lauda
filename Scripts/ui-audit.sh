#!/bin/zsh
# The interface audit: captures every screen of the app as it is in the
# working tree (the candidate) and as it is at a commit (the baseline,
# `main` unless another is given), and says what changed between the two.
#
#   Scripts/ui-audit.sh [baseline ref]
#
# Nothing shows on the screen and nothing of the user's is touched: the
# window lives off screen and the documents are made up, in a temporary
# folder (see Tests/LaudaTests/UIAudit). The screen must be unlocked, since
# the window server draws nothing for a locked one.
#
# The baseline is the commit's own code with today's audit laid over it, so
# both sides walk the same screens. Its captures are kept in .build and
# made again only when the commit or the audit changes.
set -eu
cd "$(dirname "$0")/.."
ROOT="$PWD"

REF="${1:-main}"
COMMIT="$(git rev-parse --short "$REF^{commit}")"
AUDIT_SOURCES="Tests/LaudaTests/UIAudit"
WORK="$ROOT/.build/ui-audit"
OUT="${UI_AUDIT_DIR:-/tmp/lauda-ui-audit-$(date +%Y%m%d-%H%M%S)}"

audit_version="$(cat "$AUDIT_SOURCES"/*.swift | shasum | cut -c1-10)"
BASELINE="$WORK/baseline-$COMMIT-$audit_version"

capture() {  # <source root> <scratch path> <output folder>
    rm -rf "$3"
    mkdir -p "$3"
    # A walk that stops halfway leaves some captures behind, and kept as a
    # baseline they would show every later screen as new: the run has to
    # pass, not just leave pictures.
    if ! (cd "$1" && UI_AUDIT_OUT="$3" swift test --scratch-path "$2" --filter UIAuditTests >"$3/run.log" 2>&1); then
        grep -E "error|✘|recorded|signal" "$3/run.log" >&2 || tail -20 "$3/run.log" >&2
        echo "the audit did not finish in $1" >&2
        exit 1
    fi
    grep -E "✔ Test run" "$3/run.log" || true
    rm -f "$3/run.log"
    if ! ls "$3"/*/*.png >/dev/null 2>&1; then
        echo "no captures came out of $1 (is the screen locked?)" >&2
        exit 1
    fi
}

mkdir -p "$WORK"
if [ ! -d "$BASELINE" ]; then
    echo "==> baseline: $REF ($COMMIT)"
    rm -rf "$WORK/baseline-src"
    mkdir -p "$WORK/baseline-src"
    git archive "$COMMIT" | tar -x -C "$WORK/baseline-src"
    rm -rf "$WORK/baseline-src/$AUDIT_SOURCES"
    cp -R "$AUDIT_SOURCES" "$WORK/baseline-src/$AUDIT_SOURCES"
    capture "$WORK/baseline-src" "$WORK/baseline-build" "$BASELINE.partial"
    mv "$BASELINE.partial" "$BASELINE"
else
    echo "==> baseline: $REF ($COMMIT), captures kept from an earlier run"
fi

echo "==> candidate: the working tree"
mkdir -p "$OUT"
capture "$ROOT" "$ROOT/.build" "$OUT/candidate"
cp -R "$BASELINE" "$OUT/baseline"

if [ ! -x "$WORK/compare" ] || [ Scripts/ui-audit-compare.swift -nt "$WORK/compare" ]; then
    swiftc -O Scripts/ui-audit-compare.swift -o "$WORK/compare"
fi
"$WORK/compare" "$OUT/baseline" "$OUT/candidate" "$OUT"

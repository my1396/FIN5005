#!/usr/bin/env bash
#
# setup-local-cache.sh — point course_web/.quarto at machine-local storage.
#
# WHY THIS EXISTS
#   This project lives inside OneDrive, which has no ignore/exclusion mechanism
#   on macOS. Quarto's .quarto/ cache is large and churny: it accumulates one
#   quarto-session-temp* directory per render, and abandoned ones pile up (we
#   once found 1,570 of them). Worse, an unmaterialised OneDrive placeholder
#   directory makes readdir() block forever, and because quarto walks the whole
#   project tree *before* printing anything, `quarto render` then hangs with no
#   output and no error at all.
#
#   Fix: keep .quarto out of OneDrive. It is pure regenerable cache, so it does
#   not need syncing. Only the symlink syncs; the cache behind it stays local.
#
# WHEN TO RUN
#   Once on each machine, BEFORE the first `quarto render` on that machine.
#   Ordering matters: if quarto runs first it creates a real .quarto directory
#   inside OneDrive, which then syncs to the other machine and collides with the
#   symlink there.
#
#   Safe to re-run at any time — it is idempotent and a no-op once correct.
#
# NOTE
#   Do NOT copy ~/.quarto-cache between machines; it is machine-local derived
#   state. The cache that IS shared across machines is _freeze/, which is
#   git-tracked and syncs normally.

set -euo pipefail

# Locate course_web as this script's own directory, so nothing depends on where
# OneDrive happens to mount the project.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fixed name so every machine agrees on the symlink target that gets synced.
CACHE_DIR="${QUARTO_LOCAL_CACHE:-$HOME/.quarto-cache/FIN5005-course_web}"

LINK="$PROJECT_DIR/.quarto"

if [ ! -f "$PROJECT_DIR/_quarto.yml" ]; then
    echo "error: no _quarto.yml beside this script — is it still in course_web/?" >&2
    exit 1
fi

mkdir -p "$CACHE_DIR"

if [ -L "$LINK" ] && [ "$(readlink "$LINK")" = "$CACHE_DIR" ]; then
    echo "ok: .quarto already points at $CACHE_DIR (no change)"
else
    if [ -e "$LINK" ] || [ -L "$LINK" ]; then
        if [ -d "$LINK" ] && [ ! -L "$LINK" ]; then
            echo "found a real .quarto directory in OneDrive — removing (regenerable cache)"
        else
            echo "replacing existing .quarto entry"
        fi
        rm -rf "$LINK"
    else
        echo "no .quarto present — creating symlink"
    fi
    ln -s "$CACHE_DIR" "$LINK"
    echo "linked: .quarto -> $CACHE_DIR"
fi

echo
echo "verify:"
ls -ld "$LINK"

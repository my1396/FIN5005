#!/usr/bin/env bash
#
# setup-local-cache.sh — point every quarto project's .quarto cache in this
# tree at machine-local storage.
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
# WHY A LIST OF ROOTS
#   A subfolder that contains its own _quarto.yml is a *separate* quarto
#   project, and quarto gives it its own .quarto/ cache. _quiz/ is one: it needs
#   to be standalone so `quarto preview` works on it (quarto ignores any
#   directory whose name starts with "_", so _quiz/ is invisible to the book
#   project) and so it stops inheriting the book's PDF preamble, which clashes
#   with latex/preamble.tex over \usepackage{geometry}.
#
#   Each root gets its OWN cache directory. They must not share one: idx/,
#   xref/ and project-cache/ are project-scoped, so two projects pointed at a
#   single cache would clobber each other.
#
# WHEN TO RUN
#   Once on each machine, BEFORE the first `quarto render` on that machine.
#   Ordering matters: if quarto runs first it creates a real .quarto directory
#   inside OneDrive, which then syncs to the other machine and collides with the
#   symlink there. (If that has already happened, this script migrates the
#   directory out rather than discarding it.)
#
#   Safe to re-run at any time — it is idempotent and a no-op once correct.
#
# ADDING A PROJECT
#   Give the new subfolder a _quarto.yml, add its path to PROJECT_ROOTS below,
#   and re-run. Also make sure its .quarto is git-ignored: _quiz/ is covered
#   because .gitignore ignores /_quiz/ wholesale, but a project in a tracked
#   directory would need its own rule (write it as `path/.quarto`, with NO
#   trailing slash — git sees the symlink as a file, so `path/.quarto/` would
#   not match it).
#
# NOTE
#   Do NOT copy ~/.quarto-cache between machines; it is machine-local derived
#   state. The cache that IS shared across machines is _freeze/, which is
#   git-tracked and syncs normally. Note that _quiz/ has no shared _freeze/:
#   the whole directory is git-ignored, so its results stay machine-local.

set -euo pipefail

# Locate course_web as this script's own directory, so nothing depends on where
# OneDrive happens to mount the project.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Every quarto project root in this tree, relative to course_web.
# "." is the book itself and must stay first.
PROJECT_ROOTS=(
    "."
    "_quiz"
    "_lab"
    "_exam"
    "_homework"
    "Rscripts"
)

# Fixed name so every machine agrees on the symlink target that gets synced.
# Sub-project caches are siblings suffixed with the subfolder name.
CACHE_BASE="${QUARTO_LOCAL_CACHE:-$HOME/.quarto-cache/FIN5005-course_web}"

# cache_dir_for <relative-root> -> absolute cache path
#   .      -> $CACHE_BASE
#   _quiz  -> $CACHE_BASE-quiz     (leading "_" dropped, "/" becomes "-")
cache_dir_for() {
    local rel="$1" slug
    if [ "$rel" = "." ]; then
        printf '%s' "$CACHE_BASE"
        return
    fi
    slug="$(printf '%s' "$rel" | sed 's#^_##; s#/_#/#g; s#/#-#g')"
    printf '%s-%s' "$CACHE_BASE" "$slug"
}

link_root() {
    local rel="$1"
    local root="$PROJECT_DIR/$rel"
    local link="$root/.quarto"
    local cache_dir
    cache_dir="$(cache_dir_for "$rel")"

    if [ ! -f "$root/_quarto.yml" ]; then
        if [ "$rel" = "." ]; then
            echo "error: no _quarto.yml beside this script — is it still in course_web/?" >&2
            exit 1
        fi
        # A sub-project that was reverted to _metadata.yml is no longer a
        # project root; nothing to link. Not an error.
        echo "skip: $rel has no _quarto.yml (not a project root)"
        return
    fi

    if [ -L "$link" ] && [ "$(readlink "$link")" = "$cache_dir" ]; then
        echo "ok:   $rel/.quarto already points at $cache_dir"
        return
    fi

    if [ -d "$link" ] && [ ! -L "$link" ]; then
        # A real cache directory inside OneDrive. Prefer moving it to the
        # local target over discarding it — it may hold expensive freeze
        # results, and a move costs nothing.
        if [ ! -e "$cache_dir" ]; then
            mkdir -p "$(dirname "$cache_dir")"
            mv "$link" "$cache_dir"
            echo "move: $rel/.quarto was a real directory in OneDrive -> $cache_dir"
        else
            rm -rf "$link"
            echo "drop: $rel/.quarto discarded ($cache_dir already exists; cache is regenerable)"
        fi
    elif [ -e "$link" ] || [ -L "$link" ]; then
        rm -rf "$link"
        echo "repl: replacing existing $rel/.quarto entry"
    fi

    mkdir -p "$cache_dir"
    ln -s "$cache_dir" "$link"
    echo "link: $rel/.quarto -> $cache_dir"
}

for rel in "${PROJECT_ROOTS[@]}"; do
    link_root "$rel"
done

echo
echo "verify:"
for rel in "${PROJECT_ROOTS[@]}"; do
    [ -e "$PROJECT_DIR/$rel/.quarto" ] || [ -L "$PROJECT_DIR/$rel/.quarto" ] || continue
    ls -ld "$PROJECT_DIR/$rel/.quarto"
done

#!/usr/bin/env bash
#
# set-file-icon.sh — give whole classes of files a custom Finder icon.
#
# With no arguments it applies every pairing in DEFAULT_PAIRINGS below:
# quarto.svg on .qmd, jupyter.svg on .ipynb, r.svg on the R family, tex.svg on
# .tex. --icon and --ext together override that with any one pairing instead.
#
# WHERE THE ARTWORK LIVES
#   Two layers, tried in order for each icon (ICON_DIRS, below):
#     1. ./images/file_icon — relative to wherever you are standing when you
#        run this, so a project can carry its own artwork and override the
#        shared set. Missing, or missing that one icon, and layer 2 answers.
#     2. ~/Documents/mac_setup/images — the shared set, kept out of any one
#        project because it is tooling rather than site content.
#   The lookup is per icon, not per folder: a project that keeps only its own
#   quarto.svg locally still gets r.svg and the rest from the shared set.
#   FILE_ICON_DIR, if set, is searched ahead of both.
#
#   That applies to a bare filename, which is why "-i r.svg" works from any
#   directory. Anything with a slash in it is a path and is used as given.
#
# WHY THIS EXISTS
#   macOS has no "icon for this file extension" setting. An extension only gets
#   an icon when some installed app claims its UTI in its Info.plist, and
#   nothing claims .qmd — so Finder falls back to the generic blank page and a
#   folder of .qmd files is a wall of identical white rectangles.
#
#   The only way to change that without shipping an app bundle is the custom
#   icon that Finder's Get Info panel sets: per-file metadata, stored in the
#   file's resource fork (com.apple.ResourceFork) and flagged in
#   com.apple.FinderInfo. This script does the same thing in bulk.
#
# HOW IT WORKS
#   1. sips rasterises the SVG at all ten icon sizes (16..512 @1x/@2x) and
#      iconutil packs them into a temporary .icns. sips reads SVG natively on
#      macOS 13+, so the arcs stay smooth at every size — ImageMagick's built-in
#      SVG renderer visibly facets them, so it is only a fallback here.
#   2. NSWorkspace's setIcon:forFile: stamps that .icns onto each file, driven
#      from AppleScriptObjC so nothing outside macOS itself has to be installed.
#
# CONSEQUENCES OF BEING PER-FILE
#   - A file created after the last run gets the generic icon. Re-run then;
#     the script is idempotent, so re-running over the whole tree is free.
#   - Each extension is a separate run, and a run only touches the extensions
#     it is given: stamping .ipynb leaves the .qmd icons alone.
#   - The icon is local metadata, not file content: it does not go through git,
#     and OneDrive does not carry resource forks between machines reliably.
#     Run this once per machine.
#   - Copying a file usually carries the icon along; exporting or re-saving it
#     through some editors drops it.
#
# WHY MTIME IS PRESERVED
#   Setting an icon rewrites the file's metadata, which bumps its modification
#   time. Left alone, that would make quarto consider every source changed and
#   re-render the entire book, throwing away _freeze/. So the mtime is captured
#   before the icon is set and restored after (the icon survives this). Pass
#   --no-keep-mtime if you ever want the true "touched" times.
#
# USAGE
#   ./set-file-icon.sh                   # every default pairing, in the current directory
#   ./set-file-icon.sh -e ipynb -i jupyter.svg     # change ipynb icons 
#   ./set-file-icon.sh -i r.svg -e r -e rmd -e rhistory -e rprofile -e rt    # match a list of extensions, case-insensitive ['r' , 'md', 'rhistory', 'profile', 'rt']
#   FILE_ICON_DIR=~/icons ./set-file-icon.sh     # load icons from ~/icons instead
#   ./set-file-icon.sh -n                # dry run: list what would change
#   ./set-file-icon.sh ..                # the whole FIN5005 tree
#   ./set-file-icon.sh _exam/99-1.qmd    # one file
#   ./set-file-icon.sh --revert          # put the generic icons back
#
#   Requires macOS. Everything it uses (sips, iconutil, osascript) ships with
#   the system; ImageMagick or rsvg-convert are used only if sips turns out not
#   to understand the SVG.

set -euo pipefail

## ========================================================================== ##
## 1. Defaults -----------------------------------------------------------------
## ========================================================================== ##

# Where icon artwork is looked up, best match first. The lookup is per icon,
# not per folder: a project that keeps only its own quarto.svg in
# images/file_icon gets that one locally and the rest from the shared set.
ICON_DIRS=()
if [ -n "${FILE_ICON_DIR:-}" ]; then
    ICON_DIRS+=("$FILE_ICON_DIR")
fi
ICON_DIRS+=(
    "$PWD/images/file_icon"                      # this project's own icons
    "/Users/menghan/Documents/mac_setup/images"  # the shared fallback set
)

# What a bare `./set-file-icon.sh` does: one line per icon, "<icon> <ext>...".
# Extensions are matched case-insensitively, so "r" also covers .R and .Rmd is
# reached by "rmd". Add a line here to cover another file type by default.
DEFAULT_PAIRINGS=(
    "quarto.svg   qmd"
    "jupyter.svg  ipynb"
    "r.svg        r rmd rhistory rprofile rt"
    "tex.svg      tex"
)

# Both stay empty unless asked for: that is how the run below tells "use every
# default pairing" apart from "use the one pairing I named".
ICON_SRC=""
EXTS=()
TARGETS=()

# Fraction of the icon tile left empty on each side. The quarto mark already
# leaves a little air inside its own viewBox, so a small value here is enough to
# match how much of the tile a stock macOS document icon fills.
PAD=0.05

REVERT=false
DRY_RUN=false
KEEP_MTIME=true
VERBOSE=false
REFRESH_FINDER=false
SAVE_ICNS=""

# Directories never worth walking: caches, rendered output, vendored libraries.
# docs/ is the rendered site and _freeze/ is quarto's cache — any source found
# there is a copy, not a source.
PRUNE_NAMES=(docs _site _freeze _book site_libs node_modules renv packrat
             _extensions _templates)

# How many paths to hand a single osascript run. Only about process startup:
# one call per file would spend most of the runtime launching osascript.
CHUNK=200

usage() {
    # Unquoted heredoc: the pairing list is printed from DEFAULT_PAIRINGS
    # itself, so --help cannot drift out of step with what a bare run does.
    cat <<USAGE
set-file-icon.sh — give classes of files a custom Finder icon (macOS only).

usage: set-file-icon.sh [options] [file-or-directory ...]
       default target is the current directory.

with no options, every default pairing is applied:
$(for p in "${DEFAULT_PAIRINGS[@]}"; do
      read -r -a f <<< "$p"
      exts="$(printf '.%s ' "${f[@]:1}")"
      printf '    %-12s -> %s\n' "${f[0]}" "${exts% }"
  done)
icons are looked up per name, first of these that has one wins
(FILE_ICON_DIR, if set, is searched ahead of them):
$(for d in "${ICON_DIRS[@]}"; do
      if [ -d "$d" ]; then printf '    %s\n' "$d"
      else printf '    %s  (not present)\n' "$d"; fi
  done)
    e.g.  FILE_ICON_DIR=~/icons ./set-file-icon.sh

  -i, --icon PATH     icon source: .svg, a square bitmap, or .icns. A bare
                      filename is looked up in the folders above
  -e, --ext EXT       extension to stamp, repeatable, case-insensitive.
                      Needs --icon: the two together replace the defaults
  -p, --pad FRAC      empty margin per side, 0-0.4 (default: 0.05, svg only)
  -r, --revert        remove the custom icon instead of setting it
  -n, --dry-run       list what would change, write nothing
  -v, --verbose       name every file as it is stamped
      --no-keep-mtime let the icon bump modification times
                      (default: restore them, so quarto does not re-render)
      --save-icns P   also keep the generated .icns at P
      --refresh-finder  relaunch Finder afterwards, if it cached old icons
  -h, --help          this message

See the comments at the top of this file for why per-file icons are the only
option on macOS, and what that implies for new files and other machines.
USAGE
    exit "${1:-0}"
}

## ========================================================================== ##
## 2. Command line -------------------------------------------------------------
## ========================================================================== ##

while [ $# -gt 0 ]; do
    case "$1" in
        -i|--icon)        ICON_SRC="$2"; shift 2 ;;
        -e|--ext)         EXTS+=("${2#.}"); shift 2 ;;
        -p|--pad)         PAD="$2"; shift 2 ;;
        -r|--revert)      REVERT=true; shift ;;
        -n|--dry-run)     DRY_RUN=true; shift ;;
        -v|--verbose)     VERBOSE=true; shift ;;
        --no-keep-mtime)  KEEP_MTIME=false; shift ;;
        --keep-mtime)     KEEP_MTIME=true; shift ;;
        --refresh-finder) REFRESH_FINDER=true; shift ;;
        --save-icns)      SAVE_ICNS="$2"; shift 2 ;;
        -h|--help)        usage 0 ;;
        --)               shift; while [ $# -gt 0 ]; do TARGETS+=("$1"); shift; done ;;
        -*)               echo "error: unknown option $1" >&2; usage 2 >&2 ;;
        *)                TARGETS+=("$1"); shift ;;
    esac
done

# --ext without --icon used to fall back to the quarto icon, which made sense
# when there was only one pairing. Now that a bare run covers four of them,
# silently stamping quarto.svg on some unrelated extension would just be a
# surprise, so say so instead. (Reverting needs no icon, hence the exception.)
if [ "${#EXTS[@]}" -gt 0 ] && [ -z "$ICON_SRC" ] && ! $REVERT; then
    echo "error: --ext needs --icon to say which icon those files should get" >&2
    echo "       (or use --revert, which needs no icon)" >&2
    exit 2
fi

# One .icns per pairing, so a single file to save is only meaningful when a
# single pairing was named.
if [ -n "$SAVE_ICNS" ] && [ -z "$ICON_SRC" ]; then
    echo "error: --save-icns needs --icon; a default run builds several icons" >&2
    exit 2
fi

# No target given means the directory you are standing in, not the one the
# script happens to live in — so it can be put on PATH and used anywhere. $PWD
# rather than "." so the paths it prints back say where they are.
[ "${#TARGETS[@]}" -gt 0 ] || TARGETS=("$PWD")

if [ "$(uname -s)" != "Darwin" ]; then
    echo "error: custom file icons are a macOS feature; this is $(uname -s)" >&2
    exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/file-icons.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

## ========================================================================== ##
## 3. Building the .icns -------------------------------------------------------
## ========================================================================== ##

# resolve_icon <spec> -> path on stdout, or nothing and status 1
#   Anything with a slash is a path and is used as given. A bare filename is
#   searched for in ICON_DIRS in order, first hit winning, so the project's own
#   images/file_icon overrides the shared set one icon at a time. A bare name
#   sitting in the current directory beats both, so a quick local experiment
#   needs no icon folder at all.
#
#   Callers must check the status: this runs inside $(...), where exiting would
#   only end the subshell and leave the script running with an empty path.
resolve_icon() {
    local spec="$1" dir
    case "$spec" in
        */*) printf '%s' "$spec"; return 0 ;;
    esac
    if [ -f "$spec" ]; then
        printf '%s' "$spec"
        return 0
    fi
    for dir in "${ICON_DIRS[@]}"; do
        if [ -f "$dir/$spec" ]; then
            printf '%s' "$dir/$spec"
            return 0
        fi
    done

    # Name every place that was tried: with two layers, "not found" on its own
    # is not enough to tell which one was meant to have it.
    echo "error: no icon named '$spec' found. Looked in:" >&2
    for dir in "${ICON_DIRS[@]}"; do
        echo "         $dir" >&2
    done
    return 1
}

# render_svg <svg> <pixels> <out.png>
#   sips first: it renders through the system's vector pipeline, so curves stay
#   curves. The others are only reached on macOS versions whose sips predates
#   SVG support.
render_svg() {
    local svg="$1" px="$2" out="$3"
    if sips -s format png -Z "$px" "$svg" --out "$out" >/dev/null 2>&1 \
        && [ -s "$out" ]; then
        return 0
    fi
    if command -v rsvg-convert >/dev/null 2>&1; then
        rsvg-convert -w "$px" -h "$px" -o "$out" "$svg" && return 0
    fi
    if command -v magick >/dev/null 2>&1; then
        magick -background none "$svg" -resize "${px}x${px}" \
            -gravity center -extent "${px}x${px}" "$out" && return 0
    fi
    return 1
}

# svg_geometry <svg> -> "W H" in user units
#   width/height attributes win when present, because that is the SVG's
#   intrinsic size; otherwise the viewBox extent is it.
svg_geometry() {
    local svg="$1" tag w h vb
    # Only the root <svg ...> tag, and only the first one: a document may well
    # contain nested svg elements, and their sizes are not the document's.
    tag="$(tr '\n' ' ' < "$svg" \
        | awk 'match($0, /<svg[^>]*>/) { print substr($0, RSTART, RLENGTH); exit }')"
    [ -n "$tag" ] || return 1

    w="$(printf '%s' "$tag" | sed -n 's/.*[[:space:]]width="\([0-9.]*\)[a-z]*".*/\1/p')"
    h="$(printf '%s' "$tag" | sed -n 's/.*[[:space:]]height="\([0-9.]*\)[a-z]*".*/\1/p')"
    if [ -n "$w" ] && [ -n "$h" ]; then
        printf '%s %s' "$w" "$h"
        return 0
    fi

    # No usable width/height (absent, or a percentage): the viewBox extent is
    # then the intrinsic size.
    vb="$(printf '%s' "$tag" \
        | sed -n 's/.*viewBox="[[:space:]]*\([-0-9.eE]*\)[ ,]*\([-0-9.eE]*\)[ ,]*\([-0-9.eE]*\)[ ,]*\([-0-9.eE]*\).*/\3 \4/p')"
    [ -n "$vb" ] || return 1
    printf '%s' "$vb"
}

# pad_svg <svg> <out.svg>
#   Wraps the original SVG in an outer one whose viewBox is a square big enough
#   to hold it plus the margin. Nesting an <svg> keeps the original's own
#   viewBox and aspect handling intact, so nothing inside it has to be parsed or
#   rewritten — and a non-square source comes out centred rather than stretched.
pad_svg() {
    local svg="$1" out="$2" geom w h body
    geom="$(svg_geometry "$svg")" || {
        echo "warn: no width/height or viewBox in $svg; using it unpadded" >&2
        cp "$svg" "$out"
        return 0
    }
    w="${geom% *}"
    h="${geom#* }"

    # Strip the XML declaration and any doctype: legal at the top of a document,
    # not legal in the middle of the one we are about to build.
    body="$(tr '\n' ' ' < "$svg" | sed -e 's/<?xml[^>]*?>//g' -e 's/<!DOCTYPE[^>]*>//g')"

    awk -v w="$w" -v h="$h" -v p="$PAD" -v body="$body" 'BEGIN {
        side = (w > h ? w : h)
        m    = side * p / (1 - 2 * p)
        s    = side + 2 * m
        minx = -(m + (side - w) / 2)
        miny = -(m + (side - h) / 2)
        printf "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%.4f\" height=\"%.4f\" viewBox=\"%.4f %.4f %.4f %.4f\">%s</svg>\n", s, s, minx, miny, s, s, body
    }' > "$out"
}

# The ten entries an .iconset is expected to carry: every Finder size at 1x and
# 2x. Each is rendered from the vector source rather than downsampled from one
# big PNG, so the small sizes stay sharp.
ICONSET_SPECS=(
    "16    icon_16x16"
    "32    icon_16x16@2x"
    "32    icon_32x32"
    "64    icon_32x32@2x"
    "128   icon_128x128"
    "256   icon_128x128@2x"
    "256   icon_256x256"
    "512   icon_256x256@2x"
    "512   icon_512x512"
    "1024  icon_512x512@2x"
)

build_icns() {
    local src="$1" out="$2" ext lower iconset spec px name w h

    [ -f "$src" ] || { echo "error: no icon source at $src" >&2; exit 1; }
    lower="$(printf '%s' "$src" | tr '[:upper:]' '[:lower:]')"
    ext="${lower##*.}"

    if [ "$ext" = "icns" ]; then
        cp "$src" "$out"
        echo "icon: using $src as-is"
        return 0
    fi

    iconset="$WORK_DIR/icon.iconset"
    mkdir -p "$iconset"

    if [ "$ext" = "svg" ]; then
        local padded="$WORK_DIR/padded.svg"
        pad_svg "$src" "$padded"
        for spec in "${ICONSET_SPECS[@]}"; do
            read -r px name <<< "$spec"
            render_svg "$padded" "$px" "$iconset/$name.png" || {
                echo "error: could not rasterise $src at ${px}px." >&2
                echo "       sips could not read the SVG and neither" >&2
                echo "       rsvg-convert nor ImageMagick is installed." >&2
                exit 1
            }
        done
        echo "icon: rendered $src at 10 sizes (pad ${PAD})"
    else
        # A bitmap source has to be square: iconutil rejects an iconset whose
        # members are not exactly the dimensions their filenames claim, and
        # sips -Z fits the long edge, so a 200x100 source would come out 200x100.
        w="$(sips -g pixelWidth "$src" 2>/dev/null | awk '/pixelWidth/{print $2}')"
        h="$(sips -g pixelHeight "$src" 2>/dev/null | awk '/pixelHeight/{print $2}')"
        [ -n "$w" ] && [ -n "$h" ] || { echo "error: cannot read $src as an image" >&2; exit 1; }
        [ "$w" = "$h" ] || { echo "error: $src is ${w}x${h}; a bitmap icon source must be square" >&2; exit 1; }
        [ "$w" -ge 512 ] || echo "warn: $src is only ${w}px; large icon sizes will look soft" >&2
        for spec in "${ICONSET_SPECS[@]}"; do
            read -r px name <<< "$spec"
            sips -s format png -Z "$px" "$src" --out "$iconset/$name.png" >/dev/null 2>&1 \
                || { echo "error: sips could not resize $src to ${px}px" >&2; exit 1; }
        done
        echo "icon: resized $src to 10 sizes"
    fi

    iconutil -c icns "$iconset" -o "$out"
}

## ========================================================================== ##
## 4. Finding the files --------------------------------------------------------
## ========================================================================== ##

# A target may be a single file or a directory to walk. Dot-directories go
# first: .quarto is a symlink pointing out of OneDrive, and .git and .Rproj.user
# hold nothing renderable. The '.?*' pattern is deliberate — plain '.*' would
# also match "." and prune the starting directory. _files/ directories hold
# rendered figures rather than sources.
collect_files() {
    local target prune_expr name find_expr ext first

    prune_expr=( '(' -name '.?*' )
    for name in "${PRUNE_NAMES[@]}"; do
        prune_expr+=( -o -name "$name" )
    done
    prune_expr+=( -o -name '*_files' ')' )

    # -iname, not -name: R alone spells its files .R, .Rmd, .Rprofile and
    # .Rhistory, and a mac's filesystem is case-insensitive anyway, so "-e r"
    # has to mean .R as much as .r. Note that this also catches dotfiles —
    # "*.rprofile" matches .Rprofile, since the leading * may match nothing.
    find_expr=( '(' )
    first=true
    for ext in "${EXTS[@]}"; do
        if $first; then first=false; else find_expr+=( -o ); fi
        find_expr+=( -iname "*.$ext" )
    done
    find_expr+=( ')' )

    for target in "${TARGETS[@]}"; do
        if [ -f "$target" ]; then
            printf '%s\0' "$target"
        elif [ -d "$target" ]; then
            find "$target" -mindepth 1 \
                \( -type d "${prune_expr[@]}" -prune \) -o \
                \( -type f "${find_expr[@]}" -print0 \)
        else
            echo "warn: no such file or directory: $target" >&2
        fi
    done
}

## ========================================================================== ##
## 5. Stamping the icon --------------------------------------------------------
## ========================================================================== ##

# AppleScriptObjC is the shortest path to NSWorkspace from a shell script, and
# NSWorkspace is the only supported way to set a custom icon. Passing "-" as the
# icon means "remove the custom icon" — setIcon: takes a nil image for that.
SET_ICON_SCPT="$WORK_DIR/set-icon.applescript"
cat > "$SET_ICON_SCPT" <<'APPLESCRIPT'
use framework "Foundation"
use framework "AppKit"
use scripting additions

on run argv
	set iconPath to item 1 of argv
	set theImage to missing value
	if iconPath is not "-" then
		set theImage to current application's NSImage's alloc()'s ¬
			initWithContentsOfFile:iconPath
		if theImage is missing value then error "cannot read icon file: " & iconPath
	end if

	set ws to current application's NSWorkspace's sharedWorkspace()
	set failures to 0
	repeat with i from 2 to (count of argv)
		set thePath to item i of argv
		set ok to (ws's setIcon:theImage forFile:thePath options:0)
		if (ok as boolean) is false then
			set failures to failures + 1
			log "fail: " & thePath
		end if
	end repeat
	return failures as text
end run
APPLESCRIPT

# stamp_chunk <file>...
#   Captures each file's mtime, sets (or clears) the icon, then puts the mtimes
#   back. The icon survives the touch: it lives in metadata the touch does not
#   address.
stamp_chunk() {
    local -a files=("$@")
    local -a stamps=()
    local f i icon_arg failures

    if $KEEP_MTIME; then
        for f in "${files[@]}"; do
            stamps+=("$(stat -f '%Sm' -t '%Y%m%d%H%M.%S' "$f")")
        done
    fi

    if $REVERT; then icon_arg="-"; else icon_arg="$ICNS"; fi

    failures="$(osascript "$SET_ICON_SCPT" "$icon_arg" "${files[@]}")" || {
        echo "error: osascript failed while setting icons" >&2
        exit 1
    }
    [ "$failures" = "0" ] || echo "warn: $failures file(s) in this batch refused the icon" >&2

    if $KEEP_MTIME; then
        i=0
        for f in "${files[@]}"; do
            touch -m -t "${stamps[$i]}" "$f"
            i=$((i + 1))
        done
    fi

    # Reverting leaves an emptied resource fork behind. Harmless, but it keeps
    # the file flagged with an @ in ls, which looks like the icon is still set.
    if $REVERT; then
        for f in "${files[@]}"; do
            xattr -d com.apple.ResourceFork "$f" 2>/dev/null || true
        done
    fi
}

## ========================================================================== ##
## 6. Run ----------------------------------------------------------------------
## ========================================================================== ##

TOTAL=0

# run_pairing <icon> <ext>...
#   One icon over one set of extensions: build it, walk the targets, stamp what
#   matches. Reverting passes an empty icon, since nothing has to be built.
run_pairing() {
    local icon="$1"; shift
    local label count=0 file ext_list
    local batch=()

    EXTS=("$@")
    ext_list="$(printf '.%s ' "${EXTS[@]}")"

    if ! $REVERT; then
        label="$(basename "$icon")"
        ICNS="$WORK_DIR/$label.icns"
        build_icns "$icon" "$ICNS"
        if [ -n "$SAVE_ICNS" ]; then
            cp "$ICNS" "$SAVE_ICNS"
            echo "icon: saved a copy at $SAVE_ICNS"
        fi
    fi

    while IFS= read -r -d '' file; do
        count=$((count + 1))
        if $DRY_RUN || $VERBOSE; then
            if $REVERT; then echo "clear: $file"; else echo "set:   $file"; fi
        fi
        $DRY_RUN && continue

        batch+=("$file")
        if [ "${#batch[@]}" -ge "$CHUNK" ]; then
            stamp_chunk "${batch[@]}"
            batch=()
        fi
    done < <(collect_files)

    if ! $DRY_RUN && [ "${#batch[@]}" -gt 0 ]; then
        stamp_chunk "${batch[@]}"
    fi

    TOTAL=$((TOTAL + count))

    if [ "$count" -eq 0 ]; then
        echo "none: no ${ext_list% } files found"
    elif $DRY_RUN; then
        if $REVERT; then
            echo "would clear: $count ${ext_list% } file(s)"
        else
            echo "would set:   $count file(s) to $label"
        fi
    elif $REVERT; then
        echo "done: custom icon removed from $count ${ext_list% } file(s)"
    else
        echo "done: $count file(s) now show $label"
    fi
}

if [ -n "$ICON_SRC" ] || [ "${#EXTS[@]}" -gt 0 ]; then
    # An explicit pairing. --revert on its own lands here only if --ext came
    # with it; a bare --revert falls through to the defaults below and so
    # clears every extension this script knows about.
    pairing_count=1
    # Reverting strips whatever icon is on the file, so no artwork is needed
    # and none is looked up — which is what lets --revert --ext work with no
    # --icon at all.
    icon=""
    if ! $REVERT; then
        icon="$(resolve_icon "$ICON_SRC")" || exit 1
    fi
    if [ "${#EXTS[@]}" -gt 0 ]; then
        run_pairing "$icon" "${EXTS[@]}"
    else
        run_pairing "$icon" qmd
    fi
else
    pairing_count="${#DEFAULT_PAIRINGS[@]}"
    for pairing in "${DEFAULT_PAIRINGS[@]}"; do
        # "icon.svg ext ext ..." -> fields[0] is the icon, the rest extensions.
        read -r -a fields <<< "$pairing"
        icon=""
        if ! $REVERT; then
            icon="$(resolve_icon "${fields[0]}")" || exit 1
        fi
        run_pairing "$icon" "${fields[@]:1}"
    done
fi

echo
if [ "$pairing_count" -gt 1 ]; then
    if $DRY_RUN; then
        echo "total: $TOTAL file(s) across $pairing_count pairings (dry run, nothing written)"
    else
        echo "total: $TOTAL file(s) across $pairing_count pairings"
    fi
elif $DRY_RUN; then
    echo "total: dry run, nothing written"
fi

if $REFRESH_FINDER && ! $DRY_RUN; then
    # Finder usually picks the change up on its own; this is for when it has
    # cached the old icon in an already-open window. It relaunches itself.
    killall Finder 2>/dev/null || true
    echo "done: Finder relaunched"
fi

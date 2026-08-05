#!/usr/bin/env bash
# Shared helpers for the release scripts. Sourced, never run directly.

set -euo pipefail

# ---------------------------------------------------------------- constants --
TEAM_ID="9CLTNBW4Z3"
SIGN_IDENTITY="Developer ID Application: Milán Várady (${TEAM_ID})"
NOTARY_PROFILE="${APPLITE_NOTARY_PROFILE:-applite-notary}"
GH_REPO="milanvarady/Applite"
PAGES_APPCAST="https://milanvarady.github.io/Applite/appcast.xml"
NOTES_URL_BASE="https://aerolite.dev/applite/releases"
ARCHIVE_ROOT="${APPLITE_ARCHIVE_ROOT:-$HOME/Documents/Applite/versions}"

RELEASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$RELEASE_DIR/../.." && pwd)"
PBXPROJ="$REPO_ROOT/Applite.xcodeproj/project.pbxproj"
INFO_PLIST="$REPO_ROOT/Applite/Applite-Info.plist"
APPCAST="$REPO_ROOT/appcast.xml"

DRY_RUN=${DRY_RUN:-0}

# ------------------------------------------------------------------ output --
if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'
    C_YELLOW=$'\033[1;33m'; C_RED=$'\033[1;31m'; C_DIM=$'\033[2m'
else
    C_RESET=''; C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_DIM=''
fi

log()  { printf '%s==>%s %s\n' "$C_BLUE"   "$C_RESET" "$*"; }
ok()   { printf '%s ok %s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
no()   { printf '%s XX %s %s\n' "$C_RED"   "$C_RESET" "$*" >&2; }
warn() { printf '%s !! %s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
fix()  { printf '      %sfix:%s %s\n' "$C_DIM" "$C_RESET" "$*" >&2; }
note() { printf '      %s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
die()  { no "$*"; exit 1; }

# ------------------------------------------------------------- dry-run gate --
# Wrap anything that publishes or mutates state outside build/. Build steps are
# deliberately NOT wrapped: a dry run that doesn't produce a real signed DMG
# isn't a rehearsal.
run_pub() {
    if [[ $DRY_RUN -eq 1 ]]; then
        printf '%s[dry-run] %s%s\n' "$C_DIM" "$(printf '%q ' "$@")" "$C_RESET"
    else
        "$@"
    fi
}

# --------------------------------------------------------------- long tools --
# Run a slow command, keep the full output in a log, show only the interesting
# lines live, and fail on *its* status — not the filter's. A plain
# `cmd | tee log | grep … || true` reports success whenever grep matches nothing,
# which is exactly the case for a clean failure.
run_logged() {
    local log="$1" pattern="$2"; shift 2
    local rc
    set +e
    "$@" 2>&1 | tee "$log" | grep -E "$pattern"
    rc=${PIPESTATUS[0]}
    set -e
    if (( rc != 0 )); then
        tail -40 "$log" >&2
        die "$1 failed (exit $rc) — full log: $log"
    fi
}

# ------------------------------------------------------------------- paths --
build_dir()   { printf '%s/build/release/v%s' "$REPO_ROOT" "$1"; }
# Rehearsals keep their markers somewhere else. Sharing them with a real run
# meant a `--dry-run` could mark every step done — including the ones run_pub had
# stubbed out — and the real release afterwards would skip everything, exit 0,
# and publish nothing.
state_dir()   { printf '%s/%s' "$(build_dir "$1")" "${STATE_SUBDIR:-state}"; }
logs_dir()    { printf '%s/logs'  "$(build_dir "$1")"; }
notes_dir()   { printf '%s/notes' "$(build_dir "$1")"; }

# Sparkle's CLI tools live in the SPM artifact cache. There are several stale
# DerivedData copies on this machine, so we always resolve against the release's
# own -derivedDataPath and never guess with `find | head -1`.
sparkle_bin() {
    printf '%s/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin' "$(build_dir "$1")"
}

# ------------------------------------------------------------------ plists --
plist_get() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null; }

# ------------------------------------------------------------ build settings --
# Reads the *effective* value of a build setting for a configuration. Unlike a
# grep over project.pbxproj this proves the setting actually resolves, which is
# the only way to catch a project-level or xcconfig override.
build_setting() {
    local key="$1" config="${2:-Release}"
    xcodebuild -project "$REPO_ROOT/Applite.xcodeproj" -scheme Applite \
        -configuration "$config" -showBuildSettings 2>/dev/null \
        | awk -F' = ' -v k="$key" '$1 ~ ("^ *" k "$") { print $2; exit }'
}

# -------------------------------------------------------------------- steps --
# Markers are files under state/. Re-running the same command is the resume
# mechanism; the human gates never write a marker until their condition holds.
step_done()  { [[ -f "$(state_dir "$1")/$2.done" ]]; }
mark_done()  { date -u +%Y-%m-%dT%H:%M:%SZ > "$(state_dir "$1")/$2.done"; }
clear_step() { rm -f "$(state_dir "$1")/$2.done"; }

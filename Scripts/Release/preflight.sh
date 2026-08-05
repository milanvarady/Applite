#!/usr/bin/env bash
#
# Check that this machine can actually cut a release. Runs standalone:
#
#     Scripts/Release/preflight.sh            # environment only
#     Scripts/Release/preflight.sh 1.4.0      # also checks the tag/version
#
# Every check reports independently and the script collects all failures before
# exiting, so one run tells you the whole list rather than the first item.

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

PREFLIGHT_VERSION=""
FAIL=0
bad() { no "$1"; FAIL=1; }

# Sparkle's tools ship as an SPM binary artifact, so they only exist once the
# package graph has been resolved into our own DerivedData.
# This is called from a command substitution: everything except the path itself
# must go to stderr, or it ends up spliced into the path.
ensure_sparkle_bin() {
    local dd bin
    if [[ -n "$PREFLIGHT_VERSION" ]]; then
        dd="$(build_dir "$PREFLIGHT_VERSION")/DerivedData"
    else
        dd="$REPO_ROOT/build/release/tools/DerivedData"
    fi
    bin="$dd/SourcePackages/artifacts/sparkle/Sparkle/bin"
    if [[ ! -x "$bin/generate_keys" ]]; then
        log "resolving Swift packages (first run only)" >&2
        xcodebuild -project "$REPO_ROOT/Applite.xcodeproj" -scheme Applite \
            -derivedDataPath "$dd" -resolvePackageDependencies -quiet >/dev/null 2>&1 || true
    fi
    printf '%s' "$bin"
}

preflight_toolchain() {
    local dev; dev="$(xcode-select -p 2>/dev/null || true)"
    if [[ "$dev" == *"/Xcode"*".app/"* ]]; then
        ok "xcode-select → $dev"
    else
        bad "xcode-select points at '${dev:-nothing}', not a full Xcode"
        fix "sudo xcode-select -s /Applications/Xcode.app"
    fi

    if command -v create-dmg >/dev/null 2>&1; then
        ok "create-dmg → $(command -v create-dmg)"
    else
        bad "create-dmg is not installed"
        fix "brew install create-dmg"
    fi

    if command -v gh >/dev/null 2>&1; then
        if gh auth status >/dev/null 2>&1; then
            ok "gh authenticated as $(gh api user --jq .login 2>/dev/null || echo '?')"
        else
            bad "gh is installed but not authenticated"
            fix "gh auth login"
        fi
    else
        bad "gh is not installed"
        fix "brew install gh"
    fi

    if xcrun --find notarytool >/dev/null 2>&1; then
        ok "notarytool available"
    else
        bad "xcrun notarytool not found"
        fix "install the full Xcode, not just the Command Line Tools"
    fi
}

preflight_certificate() {
    if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGN_IDENTITY"; then
        ok "Developer ID Application certificate present"
    else
        bad "no '$SIGN_IDENTITY' in the keychain"
        fix "Xcode ▸ Settings ▸ Accounts ▸ team $TEAM_ID ▸ Manage Certificates… ▸ +"
        fix "  ▸ 'Developer ID Application'  (only the Account Holder can create one)"
        fix "verify with: security find-identity -v -p codesigning"
    fi
}

preflight_notary() {
    # No --limit: notarytool has no such option, and passing it made this check
    # fail even with perfectly good credentials. Keep notarytool's own message —
    # "profile not found" and "password rejected" need different fixes.
    local out
    if out="$(xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" 2>&1)"; then
        ok "notarytool profile '$NOTARY_PROFILE' works"
    else
        bad "notarytool keychain profile '$NOTARY_PROFILE' is missing or unusable"
        printf '%s\n' "$out" | head -3 | sed 's/^/      /' >&2
        fix "xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
        fix "    --apple-id <your-apple-id> --team-id $TEAM_ID"
        fix "(omit --password and let it prompt)"
    fi
}

preflight_sparkle_key() {
    local bin want have
    bin="$(ensure_sparkle_bin)"
    want="$(plist_get "$INFO_PLIST" SUPublicEDKey || true)"

    if [[ ! -x "$bin/generate_keys" ]]; then
        bad "Sparkle tools not found at $bin"
        fix "open the project in Xcode once, or run: xcodebuild -resolvePackageDependencies"
        return
    fi
    if [[ -z "$want" ]]; then
        bad "SUPublicEDKey missing from $INFO_PLIST"
        return
    fi

    # generate_keys -p exits 0 even when no key exists, so compare the output.
    have="$("$bin/generate_keys" -p 2>/dev/null || true)"
    have="${have//[$'\n\r']/}"

    if [[ "$have" == "$want" ]]; then
        ok "Sparkle signing key matches SUPublicEDKey"
    else
        bad "Sparkle EdDSA signing key missing or MISMATCHED"
        note "keychain has:  ${have:-<no key>}"
        note "app expects:   $want"
        fix "restore from your backup:  $bin/generate_keys -f <private-key-file>"
        fix "then re-check:             $bin/generate_keys -p"
        fix "DO NOT generate a new key — every installed copy of Applite pins the old"
        fix "public key and would silently stop updating forever."
    fi
}

preflight_repo() {
    local branch
    branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
    [[ "$branch" == main ]] && ok "on branch main" \
        || { bad "on branch '$branch', expected main"; fix "git switch main"; }

    if git -C "$REPO_ROOT" diff --quiet && git -C "$REPO_ROOT" diff --cached --quiet; then
        ok "working tree is clean"
    else
        bad "working tree is dirty"
        fix "commit or stash before releasing"
    fi

    if git -C "$REPO_ROOT" fetch -q origin main 2>/dev/null; then
        if [[ "$(git -C "$REPO_ROOT" rev-parse HEAD)" == "$(git -C "$REPO_ROOT" rev-parse origin/main)" ]]; then
            ok "in sync with origin/main"
        else
            bad "HEAD differs from origin/main"
            fix "git pull --ff-only   (or push what you have)"
        fi
    else
        warn "could not fetch origin — skipping the sync check"
    fi

    if [[ -n "$PREFLIGHT_VERSION" ]]; then
        if git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/v$PREFLIGHT_VERSION" >/dev/null; then
            bad "tag v$PREFLIGHT_VERSION already exists"
            fix "pick a new version, or: git tag -d v$PREFLIGHT_VERSION"
        else
            ok "tag v$PREFLIGHT_VERSION is free"
        fi
    fi
}

preflight_appcast() {
    if ! xmllint --noout "$APPCAST" 2>/dev/null; then
        bad "appcast.xml is not well-formed XML"
        return
    fi
    if python3 "$RELEASE_DIR/appcast_insert.py" "$APPCAST" --check-only; then
        ok "appcast.xml is valid (newest published build: $(
            python3 "$RELEASE_DIR/appcast_insert.py" "$APPCAST" --max-version))"
    else
        FAIL=1
    fi
}

preflight_all() {
    PREFLIGHT_VERSION="${1:-}"
    FAIL=0

    log "preflight${PREFLIGHT_VERSION:+ for $PREFLIGHT_VERSION}"
    preflight_toolchain
    preflight_certificate
    preflight_notary
    preflight_sparkle_key
    preflight_repo
    preflight_appcast

    if (( FAIL )); then
        echo
        die "preflight failed — fix the items above and run it again"
    fi
    echo
    ok "ready to release"
}

# Only run when executed directly; release.sh sources this file.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    preflight_all "$@"
fi

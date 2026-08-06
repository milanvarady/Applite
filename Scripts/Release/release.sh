#!/usr/bin/env bash
#
# Cut an Applite release: build, sign, notarize, package, publish.
#
#     Scripts/Release/release.sh run 1.4.0
#
# The pipeline stops twice, at the two places that need a human: writing the
# release notes, and deploying them to aerolite.dev. Both are conditions rather
# than prompts — do the thing, then run the exact same command again and it picks
# up where it left off. See Scripts/Release/README.md.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
source "$HERE/preflight.sh"

# Order matters. Every entry has a matching step_<name> function, dashes mapped
# to underscores.
STEPS=(
    preflight
    bump
    notes-draft
    notes-gate
    archive
    export
    verify-app
    notarize-app
    dmg
    notarize-dmg
    sign-update
    notes-website
    github-release
    appcast
    site-gate
    publish-appcast
    archive-artifacts
)

VERSION=""
FORCE=0
SKIP_NOTARIZE=0
CRITICAL=0
FROM_STEP=""
ONLY_STEP=""
BUILD_OVERRIDE=""

usage() {
    cat <<'EOF'
usage:
  release.sh preflight [version]      check this machine can cut a release
  release.sh run <version> [flags]    run (or resume) the pipeline
  release.sh status <version>         show which steps have completed
  release.sh notes <version>          regenerate the release-note drafts
  release.sh clean <version>          delete the build directory

one-time setup:
  release.sh sparkle-bin              print the path to Sparkle's CLI tools
  release.sh import-key <file>        verify and import the Sparkle signing key

flags for `run`:
  --dry-run           build and notarize for real, publish nothing
  --skip-notarize     skip Apple's servers (fast rehearsal; implies --dry-run)
  --critical          mark the update critical in the appcast and on the website
  --build <n>         override the computed build number
  --from <step>       redo this step and everything after it
  --only <step>       run exactly one step, ignoring its marker
  --force             ignore all step markers
EOF
}

# ------------------------------------------------------------ persisted vars --
# Values computed in one step are needed by later steps, and a resumed run skips
# the step that produced them — so they go to disk, not just to a shell variable.
var_set() { mkdir -p "$(state_dir "$VERSION")/vars"; printf '%s' "$2" > "$(state_dir "$VERSION")/vars/$1"; }
var_get() { cat "$(state_dir "$VERSION")/vars/$1" 2>/dev/null || true; }
var_req() {
    local v; v="$(var_get "$1")"
    [[ -n "$v" ]] || die "missing '$1' from an earlier step — rerun with --from $2"
    printf '%s' "$v"
}

# --------------------------------------------------------------------- paths --
BUILD=""; APP=""; DMG=""
set_paths() {
    BUILD="$(build_dir "$VERSION")"
    APP="$BUILD/export/Applite.app"
    DMG="$BUILD/Applite.dmg"
}

# -------------------------------------------------------------- notarization --
# create-dmg's own --notarize does not inspect the submission status, so a
# rejection surfaces as a confusing stapler error. We parse it and fetch the log.
submit_and_wait() {
    local file="$1" logbase="$2" id status
    log "submitting $(basename "$file") to Apple — this usually takes a few minutes"
    xcrun notarytool submit "$file" \
        --keychain-profile "$NOTARY_PROFILE" --wait --timeout 30m \
        --output-format json > "$logbase.json"

    id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id",""))' "$logbase.json")"
    status="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status",""))' "$logbase.json")"
    [[ -n "$id" ]] && printf '%s' "$id" > "$logbase.submission-id"

    if [[ "$status" != "Accepted" ]]; then
        warn "notarization returned '$status' — fetching the log"
        xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" "$logbase.log.json" 2>/dev/null || true
        [[ -f "$logbase.log.json" ]] && cat "$logbase.log.json" >&2
        die "notarization failed (submission $id)"
    fi
    ok "notarized ($id)"
}

# =============================================================== step: preflight
step_preflight() {
    preflight_all "$VERSION"
}

# ==================================================================== step: bump
step_bump() {
    local appcast_max project_cur new_build
    appcast_max="$(python3 "$HERE/appcast_insert.py" "$APPCAST" --max-version)"
    project_cur="$(build_setting CURRENT_PROJECT_VERSION Release)"

    if [[ -n "$BUILD_OVERRIDE" ]]; then
        new_build="$BUILD_OVERRIDE"
        log "build $new_build (--build override)"
    elif (( project_cur > appcast_max )); then
        # The project was bumped after the last release but never shipped.
        new_build="$project_cur"
        log "build $new_build — project is at $project_cur, newest published is $appcast_max (never shipped), reusing it"
    else
        new_build=$(( appcast_max + 1 ))
        log "build $new_build — newest published is $appcast_max"
    fi
    (( new_build > appcast_max )) \
        || die "build $new_build is not greater than the published $appcast_max"

    # agvtool is not usable here: `what-marketing-version` misreports an empty
    # CFBundleShortVersionString in Applite-Info.plist, and `new-marketing-version`
    # would write that key into the plist, permanently shadowing MARKETING_VERSION
    # from GENERATE_INFOPLIST_FILE.
    local n_mv n_bv
    n_mv="$(grep -c '^[[:space:]]*MARKETING_VERSION = ' "$PBXPROJ")"
    n_bv="$(grep -c '^[[:space:]]*CURRENT_PROJECT_VERSION = ' "$PBXPROJ")"
    (( n_mv == 2 )) || die "expected 2 MARKETING_VERSION lines in project.pbxproj, found $n_mv"
    (( n_bv == 2 )) || die "expected 2 CURRENT_PROJECT_VERSION lines in project.pbxproj, found $n_bv"

    /usr/bin/sed -i '' -E \
        -e "s/^([[:space:]]*MARKETING_VERSION = )[^;]*;/\1${VERSION};/" \
        -e "s/^([[:space:]]*CURRENT_PROJECT_VERSION = )[^;]*;/\1${new_build};/" \
        "$PBXPROJ"

    # Verify the effective setting for both configurations. A grep cannot prove a
    # setting resolves — a project-level or xcconfig override would sail past it.
    local cfg got_mv got_bv
    for cfg in Debug Release; do
        got_mv="$(build_setting MARKETING_VERSION "$cfg")"
        got_bv="$(build_setting CURRENT_PROJECT_VERSION "$cfg")"
        [[ "$got_mv" == "$VERSION" && "$got_bv" == "$new_build" ]] \
            || die "$cfg still resolves to $got_mv ($got_bv) after the bump"
    done
    ok "project.pbxproj → $VERSION ($new_build), verified in Debug and Release"

    var_set build "$new_build"
    # Re-running bump (--force, or a resume) is a no-op sed on an already
    # committed tree; `git commit` would then fail with "nothing to commit" and
    # take the whole pipeline down under set -e.
    if git -C "$REPO_ROOT" diff --quiet -- "$PBXPROJ"; then
        note "project.pbxproj already at $VERSION ($new_build), nothing to commit"
    else
        run_pub git -C "$REPO_ROOT" commit -am "Release $VERSION (build $new_build)"
    fi
}

# ============================================================= step: notes-draft
step_notes_draft() {
    local notes prev
    notes="$(notes_dir "$VERSION")"
    mkdir -p "$notes"
    prev="$(git -C "$REPO_ROOT" describe --tags --abbrev=0 --match 'v[0-9]*' HEAD 2>/dev/null || true)"
    var_set prev_tag "$prev"

    # Reference material: every commit since the last tag, grouped by the
    # "Docs:" / "i18n:" / "Testing:" subject prefixes already used in this repo.
    {
        printf '# %s — raw changelog\n\n' "$VERSION"
        if [[ -n "$prev" ]]; then
            printf '%s..HEAD — %s commits, %s\n' "$prev" \
                "$(git -C "$REPO_ROOT" rev-list --count --no-merges "$prev"..HEAD)" \
                "$(git -C "$REPO_ROOT" diff --shortstat "$prev"..HEAD)"
            git -C "$REPO_ROOT" log --no-merges --pretty=format:'%s|%h' "$prev"..HEAD | awk -F'|' '
                { s = $1; h = $2
                  if (match(s, /^[A-Za-z0-9()+ .-]{1,24}: /)) {
                      g = substr(s, 1, RSTART+RLENGTH-3); m = substr(s, RSTART+RLENGTH)
                  } else { g = ""; m = s }
                  if (g == "") { misc = misc sprintf("- %s (`%s`)\n", s, h); next }
                  k = tolower(g); name[k] = g; count[k]++
                  body[k] = body[k] sprintf("- %s (`%s`)\n", m, h)
                  full[k] = full[k] sprintf("- %s (`%s`)\n", s, h)
                  if (!(k in seen)) { seen[k] = 1; order[++n] = k }
                }
                END {
                  # A prefix used once is a sentence that happens to contain a
                  # colon ("Finding 5: ..."), not a category. Those go to Other
                  # with their subject intact.
                  for (i = 1; i <= n; i++) {
                      k = order[i]
                      if (count[k] >= 2) printf "\n## %s\n\n%s", name[k], body[k]
                      else misc = misc full[k]
                  }
                  if (misc != "") printf "\n## Other\n\n%s", misc
                }'

            # PR titles are the curated version of the same history, and are
            # usually the better starting point for the user-facing notes.
            # Must be UTC. GitHub reports mergedAt as "...Z" and the jq compare is
            # a plain string compare, so a local "+02:00" stamp silently drops
            # every PR merged in the offset-wide window just after the tag.
            local since
            since="$(TZ=UTC0 git -C "$REPO_ROOT" log -1 --date=iso-strict-local --format=%cd "$prev" 2>/dev/null || true)"
            if [[ -n "$since" ]]; then
                printf '\n## Merged pull requests\n\n'
                gh pr list --repo "$GH_REPO" --state merged --limit 200 \
                    --json number,title,mergedAt \
                    --jq "[.[] | select(.mergedAt > \"$since\")] | .[] | \"- #\(.number) \(.title)\"" \
                    2>/dev/null || printf '(could not reach GitHub)\n'
            fi
        else
            printf 'No previous tag found; listing all commits.\n\n'
            git -C "$REPO_ROOT" log --no-merges --pretty=format:'- %s (`%h`)'
        fi
        printf '\n'
    } > "$notes/changelog-raw.md"

    # The GitHub release body, verbatim. Everything that changed.
    if [[ ! -f "$notes/release-notes.md" ]]; then
        cat > "$notes/release-notes.md" <<EOF
<!-- APPLITE-RELEASE-NOTES-DRAFT: delete THIS LINE when the notes are final -->
<!-- The GitHub release body. Reference: changelog-raw.md -->
<!-- Delete any section you don't need; empty ones are dropped automatically. -->

### New Features

-

### Improvements

-

### Fixes

-

### Known Issues

-
EOF
    fi

    # The Sparkle update panel and the aerolite page. Deliberately a separate file:
    # the panel is a small window someone skims mid-update, so it needs a filtered
    # handful of one-liners rather than the full release body.
    if [[ ! -f "$notes/website-notes.md" ]]; then
        cat > "$notes/website-notes.md" <<EOF
<!-- APPLITE-RELEASE-NOTES-DRAFT: delete THIS LINE when the notes are final -->
<!-- Shown in the Sparkle update window and on aerolite.dev. -->
<!-- Keep it to a glance: ~5 bullets, one line each, no jargon. -->
<!-- These headings are parsed into the aerolite snippet — keep them as they are. -->

### New Features

-

### Improvements

-
EOF
    fi

    ok "drafts written to $notes"
}

# ============================================================== step: notes-gate
step_notes_gate() {
    local notes full short pending=()
    notes="$(notes_dir "$VERSION")"
    full="$notes/release-notes.md"
    short="$notes/website-notes.md"

    # grep exits 2 on a missing file, which an `if` reads as "no sentinel found"
    # — i.e. the gate would wave through notes that don't exist at all.
    for f in "$full" "$short"; do
        [[ -f "$f" ]] || die "no notes at $f — run: $0 notes $VERSION"
        grep -q 'APPLITE-RELEASE-NOTES-DRAFT' "$f" && pending+=("$f")
    done

    if (( ${#pending[@]} )); then
        cat <<EOF

  The release notes are still a draft.

    1. Skim   $notes/changelog-raw.md

    2. Write  $full
       The GitHub release body. Everything that changed, in full.

    3. Write  $short
       The Sparkle update panel and the aerolite page. A handful of one-line
       bullets — this is a glance, not a changelog.

    4. Delete the APPLITE-RELEASE-NOTES-DRAFT line from each:
$(printf '         %s\n' "${pending[@]}")
    5. Run the same command again:
         Scripts/Release/release.sh run $VERSION

EOF
        exit 0
    fi
    ok "release notes finalised"
}

# ================================================================= step: archive
step_archive() {
    mkdir -p "$(logs_dir "$VERSION")"
    log "archiving (clean build — a few minutes)"
    run_logged "$(logs_dir "$VERSION")/archive.log" '^\*\*|error:' \
        xcodebuild archive \
            -project "$REPO_ROOT/Applite.xcodeproj" \
            -scheme Applite \
            -configuration Release \
            -destination 'generic/platform=macOS' \
            -derivedDataPath "$BUILD/DerivedData" \
            -archivePath "$BUILD/Applite.xcarchive" \
            -skipPackagePluginValidation -skipMacroValidation \
            ONLY_ACTIVE_ARCH=NO
    [[ -d "$BUILD/Applite.xcarchive" ]] || die "archive reported success but produced nothing"
    ok "archived"
}

# ================================================================== step: export
step_export() {
    rm -rf "$BUILD/export"
    log "exporting with Developer ID"
    run_logged "$(logs_dir "$VERSION")/export.log" '^\*\*|error:' \
        xcodebuild -exportArchive \
            -archivePath "$BUILD/Applite.xcarchive" \
            -exportPath "$BUILD/export" \
            -exportOptionsPlist "$HERE/ExportOptions.plist"
    [[ -d "$APP" ]] || die "export reported success but produced no app"
    ok "exported $APP"
}

# ============================================================== step: verify-app
step_verify_app() {
    local info="$APP/Contents/Info.plist" ci

    codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -2
    ci="$(codesign -dv --verbose=4 "$APP" 2>&1)"
    grep -qF "Authority=$SIGN_IDENTITY" <<<"$ci" || die "not signed with '$SIGN_IDENTITY'"
    grep -q 'flags=.*runtime'          <<<"$ci" || die "hardened runtime is not enabled"
    grep -q 'Timestamp='               <<<"$ci" || die "no secure timestamp on the signature"
    ok "Developer ID, hardened runtime, secure timestamp"

    # Sparkle ships nested code (Updater.app, Autoupdate, XPC services) that has to
    # be signed too; a broken nested signature only shows up at notarization.
    codesign --verify --strict "$APP/Contents/Frameworks/Sparkle.framework" \
        || die "Sparkle.framework signature is broken"
    ok "Sparkle.framework verified"

    local archs
    archs="$(lipo -archs "$APP/Contents/MacOS/Applite" | tr ' ' '\n' | sort | tr '\n' ' ')"
    [[ "$archs" == "arm64 x86_64 " ]] || die "not universal: $archs"
    ok "universal (arm64 + x86_64)"

    local short build minos feed
    short="$(plist_get "$info" CFBundleShortVersionString)"
    build="$(plist_get "$info" CFBundleVersion)"
    minos="$(plist_get "$info" LSMinimumSystemVersion)"
    feed="$(plist_get "$info" SUFeedURL)"

    [[ "$short" == "$VERSION" ]] || die "built app says $short, expected $VERSION"
    [[ "$build" == "$(var_req build bump)" ]] || die "built app says build $build, expected $(var_get build)"
    [[ "$feed" == "$PAGES_APPCAST" ]] || die "SUFeedURL in the built app is '$feed'"
    [[ -n "$minos" ]] || die "LSMinimumSystemVersion missing from the built app"

    # Read from the artifact, never hardcode — this is exactly how every existing
    # appcast item ended up claiming minimumSystemVersion 13.0.
    var_set short "$short"; var_set minos "$minos"
    ok "version $short (build $build), minimum macOS $minos, feed URL correct"
}

# =========================================================== step: notarize-app
step_notarize_app() {
    if (( SKIP_NOTARIZE )); then
        warn "skipping notarization of the app (--skip-notarize)"
        return
    fi
    ditto -c -k --keepParent --sequesterRsrc "$APP" "$BUILD/Applite-notarize.zip"
    submit_and_wait "$BUILD/Applite-notarize.zip" "$(logs_dir "$VERSION")/notarize-app"

    # Staple the .app itself, not just the DMG: Sparkle copies Applite.app out of
    # the disk image, and the DMG's ticket does not travel with the extracted app.
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl -a -vvv -t exec "$APP" 2>&1 | grep -q 'accepted' || die "Gatekeeper rejects the app"
    ok "app notarized, stapled and accepted by Gatekeeper"
}

# ===================================================================== step: dmg
step_dmg() {
    local bg="$BUILD/dmgbg" icns
    local volicon=()
    rm -rf "$BUILD/dmgroot" "$bg"; mkdir -p "$BUILD/dmgroot" "$bg"

    # ditto, not cp: preserves extended attributes and the stapled ticket.
    ditto "$APP" "$BUILD/dmgroot/Applite.app"

    # Background is drawn from source at build time; nothing is checked in. The
    # 1x/2x pair becomes one multi-representation TIFF so Finder renders it
    # crisply on Retina. Geometry must match the create-dmg flags below.
    swift "$HERE/make_dmg_background.swift" "$bg/bg.png"    560 400 1
    swift "$HERE/make_dmg_background.swift" "$bg/bg@2x.png" 560 400 2
    tiffutil -cathidpicheck "$bg/bg.png" "$bg/bg@2x.png" -out "$bg/background.tiff" >/dev/null

    icns="$BUILD/dmgroot/Applite.app/Contents/Resources/AppIcon.icns"
    if [[ -f "$icns" ]]; then
        volicon=(--volicon "$icns")
    else
        warn "no AppIcon.icns in the app bundle — the volume will use the generic icon"
    fi

    rm -f "$DMG"
    # No --codesign and no --notarize on purpose: create-dmg signs with a bare
    # `codesign -s` (no --timestamp, which notarization requires) and never checks
    # the notarization status. Both are done properly in notarize-dmg.
    run_logged "$(logs_dir "$VERSION")/dmg.log" 'created:|Disk image done|error|Resource busy' \
        create-dmg \
            --volname "Applite" \
            ${volicon[@]+"${volicon[@]}"} \
            --background "$bg/background.tiff" \
            --window-pos 200 120 \
            --window-size 560 400 \
            --icon-size 128 \
            --text-size 12 \
            --icon "Applite.app" 150 185 \
            --hide-extension "Applite.app" \
            --app-drop-link 410 185 \
            --format ULFO \
            --no-internet-enable \
            --hdiutil-retries 8 \
            "$DMG" "$BUILD/dmgroot"
    [[ -f "$DMG" ]] || die "create-dmg reported success but produced nothing"

    # The ticket has to have survived being copied into the image.
    if (( ! SKIP_NOTARIZE )); then
        local mnt; mnt="$(mktemp -d)"
        hdiutil attach -nobrowse -readonly -mountpoint "$mnt" "$DMG" >/dev/null
        if ! xcrun stapler validate "$mnt/Applite.app" >/dev/null 2>&1; then
            hdiutil detach "$mnt" >/dev/null || true
            die "the app inside the DMG is not stapled"
        fi
        if ! spctl -a -vvv -t exec "$mnt/Applite.app" 2>&1 | grep -q accepted; then
            hdiutil detach "$mnt" >/dev/null || true
            die "Gatekeeper rejects the app inside the DMG"
        fi
        hdiutil detach "$mnt" >/dev/null
        ok "app inside the DMG is stapled and accepted"
    fi

    # Anything downstream was computed from the previous DMG bytes.
    local s
    for s in sign-update appcast github-release; do clear_step "$VERSION" "$s"; done
    ok "built $DMG ($(du -h "$DMG" | cut -f1))"
}

# =========================================================== step: notarize-dmg
step_notarize_dmg() {
    if (( SKIP_NOTARIZE )); then
        warn "skipping notarization of the DMG (--skip-notarize)"
        return
    fi
    codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$DMG"
    codesign --verify --verbose=2 "$DMG" 2>&1 | tail -1
    submit_and_wait "$DMG" "$(logs_dir "$VERSION")/notarize-dmg"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    ok "DMG signed, notarized and stapled"
}

# ============================================================= step: sign-update
step_sign_update() {
    local bin line sig len stat_len
    bin="$(sparkle_bin "$VERSION")"
    [[ -x "$bin/sign_update" ]] || die "sign_update not found at $bin"

    # Take length and signature from one read of the final file, then cross-check.
    line="$("$bin/sign_update" "$DMG")"
    sig="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$line")"
    len="$(sed -n 's/.*length="\([0-9]*\)".*/\1/p' <<<"$line")"
    stat_len="$(stat -f%z "$DMG")"

    [[ -n "$sig" ]] || die "sign_update produced no signature: $line"
    [[ "$len" == "$stat_len" ]] || die "length mismatch: sign_update=$len stat=$stat_len"
    "$bin/sign_update" --verify "$DMG" "$sig" >/dev/null \
        || die "the signature does not verify against the DMG"

    var_set sig "$sig"; var_set len "$len"
    ok "signed for Sparkle ($len bytes)"
    warn "nothing may modify $DMG from here on — the appcast is bound to these bytes"
}

# =========================================================== step: notes-website
step_notes_website() {
    local notes out date
    local flags=()
    notes="$(notes_dir "$VERSION")"
    out="$notes/AppliteReleaseModel.swift.txt"
    date="$(LC_ALL=C date '+%Y.%m.%d.')"
    (( CRITICAL )) && flags=(--critical)

    # website-notes.md, not release-notes.md: the Sparkle panel is a small window a
    # user skims mid-update, so it gets the short filtered set. The full notes stay
    # on the GitHub release.
    python3 "$HERE/notes_to_swift.py" "$notes/website-notes.md" \
        --version "$VERSION" --date "$date" \
        ${flags[@]+"${flags[@]}"} > "$out"
    ok "website snippet → $out"
}

# ========================================================== step: github-release
step_github_release() {
    local sha url
    # Last line of defence before anything leaves this machine: ask the artifact
    # itself, not the bookkeeping. A DMG left over from a --skip-notarize
    # rehearsal has no ticket, and Gatekeeper would refuse it on every user's Mac.
    if (( ! DRY_RUN )); then
        xcrun stapler validate "$DMG" >/dev/null 2>&1 \
            || die "$DMG is not notarized/stapled — rebuild with --from export before publishing"
    fi

    run_pub git -C "$REPO_ROOT" push origin main
    sha="$(git -C "$REPO_ROOT" rev-parse HEAD)"
    url="https://github.com/$GH_REPO/releases/download/v$VERSION/Applite.dmg"

    # The asset name is pinned: the appcast enclosure URL depends on it.
    run_pub gh release create "v$VERSION" "$DMG#Applite.dmg" \
        --repo "$GH_REPO" \
        --target "$sha" \
        --title "$VERSION" \
        --notes-file "$(notes_dir "$VERSION")/release-notes.md"

    var_set enclosure "$url"
    if (( DRY_RUN )); then
        note "would publish $url"
    else
        curl -fsIL -o /dev/null "$url" || die "the enclosure URL does not resolve: $url"
        ok "released → $url"
    fi
}

# ================================================================= step: appcast
step_appcast() {
    local pubdate args=()
    # LC_ALL=C matters: the system locale is Hungarian and would emit
    # "sze, 05 aug. 2026", which is not RFC 822 and Sparkle cannot parse it.
    pubdate="$(LC_ALL=C date '+%a, %d %b %Y %H:%M:%S %z')"

    args=(
        "$APPCAST"
        --short     "$VERSION"
        --build     "$(var_req build bump)"
        --minos     "$(var_req minos verify-app)"
        --notes-url "$NOTES_URL_BASE/$VERSION.html"
        --url       "$(var_req enclosure github-release)"
        --length    "$(var_req len sign-update)"
        --sig       "$(var_req sig sign-update)"
        --pubdate   "$pubdate"
        # step_dmg clears this step's marker whenever the DMG is rebuilt, so the
        # step has to be re-runnable. Rewriting our own item in place is the
        # surgical way to do that — reverting the file with git would also throw
        # away any other uncommitted appcast edit.
        --replace-existing
    )
    (( CRITICAL )) && args+=(--critical)

    if (( DRY_RUN )); then
        python3 "$HERE/appcast_insert.py" "${args[@]}" > "$BUILD/appcast-preview.xml"
        log "appcast preview (not written):"
        diff -u "$APPCAST" "$BUILD/appcast-preview.xml" || true
    else
        python3 "$HERE/appcast_insert.py" "${args[@]}" --in-place
        xmllint --noout "$APPCAST" || die "appcast.xml is no longer well-formed"
        log "appcast diff:"
        git -C "$REPO_ROOT" --no-pager diff -- appcast.xml
    fi
    ok "appcast item prepared"
}

# =============================================================== step: site-gate
step_site_gate() {
    local url="$NOTES_URL_BASE/$VERSION.html"
    if (( DRY_RUN )); then
        warn "dry run — not waiting for $url"
        return
    fi
    # The Vapor route 404s on a missing dictionary key, so a 200 proves the entry
    # is live on the deployed instance, not merely that the site is up.
    if curl -fsS -o /dev/null "$url"; then
        ok "release notes are live at $url"
        return
    fi
    cat <<EOF

  The release notes page is not live yet.

    1. Paste  $(notes_dir "$VERSION")/AppliteReleaseModel.swift.txt
       into   ~/GitHub/aerolite/Sources/App/PageModels/AppliteReleases/AppliteReleases.swift
    2. Commit and push aerolite
    3. Deploy it (ssh to the VPS, git pull, docker compose up -d --build)
    4. Run the same command again:
         Scripts/Release/release.sh run $VERSION

  Waiting on: $url

EOF
    exit 0
}

# ========================================================= step: publish-appcast
step_publish_appcast() {
    run_pub git -C "$REPO_ROOT" add appcast.xml
    run_pub git -C "$REPO_ROOT" commit -m "Appcast: $VERSION (build $(var_get build))"
    run_pub git -C "$REPO_ROOT" push origin main

    if (( DRY_RUN )); then
        note "would publish the appcast to $PAGES_APPCAST"
        return
    fi
    log "waiting for GitHub Pages to serve the new feed"
    local i
    for i in $(seq 1 30); do
        if curl -fsS -H 'Cache-Control: no-cache' "$PAGES_APPCAST" 2>/dev/null \
            | grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>"; then
            ok "appcast is live — $VERSION is now being offered to users"
            return
        fi
        sleep 10
    done
    warn "the feed still doesn't show $VERSION after 5 minutes"
    warn "check https://github.com/$GH_REPO/actions (Pages build) before worrying"
}

# ======================================================= step: archive-artifacts
step_archive_artifacts() {
    local dest="$ARCHIVE_ROOT/v$VERSION"
    # This directory is the reference copy of every shipped release — it is what
    # you sign against to prove a Sparkle key is the right one. A rehearsal must
    # never overwrite it with un-notarized builds.
    run_pub mkdir -p "$dest"
    run_pub ditto "$APP" "$dest/Applite.app"
    run_pub ditto "$DMG" "$dest/Applite.dmg"
    # dSYMs are not currently kept, which is why old crash reports can't be
    # symbolicated. Keep them alongside the build they belong to.
    if [[ -d "$BUILD/Applite.xcarchive/dSYMs" ]]; then
        run_pub ditto "$BUILD/Applite.xcarchive/dSYMs" "$dest/dSYMs"
    fi
    if (( DRY_RUN )); then
        cat <<EOF

  ${C_YELLOW}Rehearsal complete — nothing was published.${C_RESET}

    DMG        $(du -h "$DMG" | cut -f1) at $DMG
    Appcast    previewed at $BUILD/appcast-preview.xml
$( git -C "$REPO_ROOT" diff --quiet -- "$PBXPROJ" || printf '\n  project.pbxproj still carries the version bump — revert it:\n    git checkout Applite.xcodeproj/project.pbxproj\n' )
EOF
        return
    fi
    ok "archived artifacts to $dest"

    cat <<EOF

  ${C_GREEN}Applite $VERSION (build $(var_get build)) is out.${C_RESET}

    DMG        $(du -h "$DMG" | cut -f1)  →  $(var_get enclosure)
    Appcast    $PAGES_APPCAST
    Notes      $NOTES_URL_BASE/$VERSION.html
    Archive    $dest

  Smoke test: install the previous release, launch it, and let Sparkle find this one.

EOF
}

# ===================================================== one-time key management --
# Importing the Sparkle key is rare, risky and easy to get wrong by hand, so it
# gets a command rather than a paragraph of instructions.
cmd_import_key() {
    local keyfile="${1:-}" bin want got ref_version ref_dmg expected got_sig
    [[ -n "$keyfile" ]] || die "usage: $0 import-key <private-key-file>"
    [[ -f "$keyfile" ]] || die "no such file: $keyfile"

    bin="$(ensure_sparkle_bin)"
    [[ -x "$bin/generate_keys" ]] || die "Sparkle tools not found at $bin"

    want="$(plist_get "$INFO_PLIST" SUPublicEDKey)"
    [[ -n "$want" ]] || die "SUPublicEDKey missing from $INFO_PLIST"

    got="$("$bin/generate_keys" -p 2>/dev/null || true)"
    got="${got//[$'\n\r']/}"
    if [[ "$got" == "$want" ]]; then
        ok "a matching key is already in the keychain — nothing to do"
        return
    fi
    [[ -z "$got" || "$got" == ERROR* ]] \
        || die "a DIFFERENT key is already in the keychain ($got) — refusing to overwrite it"

    # Strongest possible check, and it needs no trust in the file's provenance:
    # Ed25519 is deterministic, so the real key reproduces a signature that is
    # already published in the feed, for a DMG we still have on disk.
    for ref_version in $(python3 "$HERE/appcast_insert.py" "$APPCAST" --list-versions); do
        ref_dmg="$ARCHIVE_ROOT/v$ref_version/Applite.dmg"
        [[ -f "$ref_dmg" ]] && break
        ref_dmg=""
    done

    if [[ -n "$ref_dmg" ]]; then
        expected="$(python3 "$HERE/appcast_insert.py" "$APPCAST" --signature-of "$ref_version" | cut -d' ' -f1)"
        # `|| true`: an unreadable or malformed key makes sign_update exit
        # non-zero, and we want the mismatch reported below rather than a bare
        # set -e abort with nothing printed.
        got_sig="$("$bin/sign_update" --ed-key-file "$keyfile" "$ref_dmg" 2>/dev/null \
                   | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' || true)"
        if [[ "$got_sig" != "$expected" ]]; then
            no "This is NOT the Applite signing key."
            note "signing $ref_version reproduced: ${got_sig:-<nothing>}"
            note "the published feed says:        $expected"
            die "refusing to import — shipping a different key would permanently break auto-update for every existing install"
        fi
        ok "verified against the published $ref_version signature (deterministic match)"
    else
        warn "no archived DMG found under $ARCHIVE_ROOT to verify against"
        warn "falling back to the public-key check after import"
    fi

    "$bin/generate_keys" -f "$keyfile"

    got="$("$bin/generate_keys" -p 2>/dev/null || true)"
    got="${got//[$'\n\r']/}"
    [[ "$got" == "$want" ]] || die "imported key's public half is $got, expected $want — remove it from the keychain"
    ok "Sparkle key imported and matches SUPublicEDKey"
    note "keep your 1Password copy as the backup; never run bare 'generate_keys' again"
}

# ================================================================== the runner --
known_step() {
    local s
    for s in "${STEPS[@]}"; do [[ "$s" == "$1" ]] && return 0; done
    return 1
}

run_pipeline() {
    mkdir -p "$(state_dir "$VERSION")" "$(logs_dir "$VERSION")" "$(notes_dir "$VERSION")"

    # A typo'd step name would otherwise skip everything and report success.
    [[ -z "$ONLY_STEP" ]] || known_step "$ONLY_STEP" || die "unknown step '$ONLY_STEP'"

    if [[ -n "$FROM_STEP" ]]; then
        local seen=0 s
        for s in "${STEPS[@]}"; do
            [[ "$s" == "$FROM_STEP" ]] && seen=1
            (( seen )) && clear_step "$VERSION" "$s"
        done
        (( seen )) || die "unknown step '$FROM_STEP'"
    fi

    local s fn
    for s in "${STEPS[@]}"; do
        if [[ -n "$ONLY_STEP" && "$s" != "$ONLY_STEP" ]]; then continue; fi
        if [[ -z "$ONLY_STEP" ]] && (( ! FORCE )) && step_done "$VERSION" "$s"; then
            printf '%s --  %-18s done %s%s\n' "$C_DIM" "$s" \
                "$(cat "$(state_dir "$VERSION")/$s.done")" "$C_RESET"
            continue
        fi
        printf '\n'
        log "$s"
        fn="step_${s//-/_}"
        "$fn"
        mark_done "$VERSION" "$s"
    done
    [[ -n "$ONLY_STEP" ]] && ok "step '$ONLY_STEP' complete"
    return 0
}

cmd_status() {
    local build; build="$(var_get build)"
    printf '\n  %s (build %s)\n\n' "$VERSION" "${build:-not yet decided}"
    local s
    for s in "${STEPS[@]}"; do
        if step_done "$VERSION" "$s"; then
            printf '  %s✓%s %-18s %s\n' "$C_GREEN" "$C_RESET" "$s" \
                "$(cat "$(state_dir "$VERSION")/$s.done")"
        else
            printf '  %s·%s %-18s\n' "$C_DIM" "$C_RESET" "$s"
        fi
    done
    printf '\n'
}

main() {
    local cmd="${1:-}"; shift || true
    case "$cmd" in
        preflight)
            VERSION="${1:-}"; set_paths
            preflight_all "$VERSION"
            return ;;
        sparkle-bin)
            ensure_sparkle_bin; printf '\n'
            return ;;
        import-key)
            cmd_import_key "${1:-}"
            return ;;
        run|status|notes|clean) ;;
        -h|--help|"") usage; return ;;
        *) usage; die "unknown command '$cmd'" ;;
    esac

    VERSION="${1:-}"; shift || true
    [[ -n "$VERSION" ]] || { usage; die "a version is required, e.g. 1.4.0"; }
    [[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || die "version must look like 1.4.0, got '$VERSION'"

    # A flag whose value is missing would otherwise leave the variable empty and
    # then fall off the end of the loop, exiting 1 with nothing printed.
    needs_value() { [[ -n "${2:-}" && "${2:-}" != --* ]] || die "$1 needs a value"; }

    while (( $# )); do
        case "$1" in
            --dry-run)       DRY_RUN=1 ;;
            --skip-notarize) SKIP_NOTARIZE=1; DRY_RUN=1 ;;
            --critical)      CRITICAL=1 ;;
            --force)         FORCE=1 ;;
            --build)         needs_value "$@"; BUILD_OVERRIDE="$2"; shift ;;
            --from)          needs_value "$@"; FROM_STEP="$2"; shift ;;
            --only)          needs_value "$@"; ONLY_STEP="$2"; shift ;;
            *) usage; die "unknown flag '$1'" ;;
        esac
        shift
    done

    # Rehearsal markers must never be mistaken for a real release's progress.
    (( DRY_RUN )) && STATE_SUBDIR="state-rehearsal"

    set_paths

    case "$cmd" in
        status) cmd_status ;;
        clean)  rm -rf "$BUILD"; ok "removed $BUILD" ;;
        notes)  mkdir -p "$(state_dir "$VERSION")"; step_notes_draft ;;
        run)
            (( DRY_RUN )) && warn "dry run — building for real, publishing nothing"
            (( SKIP_NOTARIZE )) && warn "skipping notarization — the DMG will NOT be distributable"
            run_pipeline ;;
    esac
}

main "$@"

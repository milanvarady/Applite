# Release tooling

Everything mechanical about shipping a release, in one command:

    Scripts/Release/release.sh run 1.4.0

It builds, signs, notarizes, packages, publishes the GitHub release, and updates the Sparkle
appcast. It stops twice — once for you to write the release notes, once for you to deploy them to
aerolite.dev — and both stops are *conditions*, not prompts: do the thing, run the same command
again, and it carries on from where it stopped.

| Command | What it does |
|---|---|
| `release.sh preflight [version]` | Check this machine can cut a release. Safe to run any time |
| `release.sh run <version>` | Run, or resume, the pipeline |
| `release.sh status <version>` | Which steps have completed |
| `release.sh notes <version>` | Regenerate the release-note drafts |
| `release.sh clean <version>` | Delete `build/release/v<version>/` |

Flags for `run`: `--dry-run`, `--skip-notarize`, `--critical`, `--build <n>`, `--from <step>`,
`--only <step>`, `--force`.

## One-time setup

Three credentials live in the login keychain and never in the repo. `preflight` checks all three
and prints the fix for whichever is missing.

### 1. Developer ID Application certificate

Notarization requires it; *Apple Development* and *Apple Distribution* will not do.

Xcode ▸ Settings ▸ Accounts ▸ team `9CLTNBW4Z3` ▸ Manage Certificates… ▸ **+** ▸
**Developer ID Application**. Only the Account Holder can create one, and a team is capped at five.

    security find-identity -v -p codesigning        # verify

### 2. notarytool keychain profile

Create an app-specific password at appleid.apple.com ▸ Sign-In and Security, then:

    xcrun notarytool store-credentials "applite-notary" \
        --apple-id <your-apple-id> --team-id 9CLTNBW4Z3

    xcrun notarytool history --keychain-profile applite-notary    # verify

Omit `--password` and let it prompt, so the app-specific password stays out of your shell history.

Override the profile name with `APPLITE_NOTARY_PROFILE` if you ever rename it.

### 3. Sparkle EdDSA signing key

To restore the key on a new machine, from your 1Password backup:

    Scripts/Release/release.sh import-key ~/path/to/sparkle-key.txt

That refuses to import anything that isn't the real key. Before touching the keychain it signs an
already-published DMG from `~/Documents/Applite/versions/` and requires a byte-identical match
against the signature in `appcast.xml` — Ed25519 is deterministic, so only the genuine key can
reproduce it. Afterwards it re-derives the public half and checks it against `SUPublicEDKey`. It
also refuses to overwrite a *different* key that is already present.

Delete your copy of the key file afterwards; 1Password is the backup.

The underlying tools, if you need them directly (`Scripts/Release/release.sh sparkle-bin` prints
the path — the Xcode DerivedData hash is unstable, so never hardcode it):

    generate_keys                       # creates a NEW key — never run this for Applite
    generate_keys -x sparkle-key.txt    # export for backup
    generate_keys -p                    # print the public half

`generate_keys -p` **exits 0 even when no key exists**, printing an error to stdout, so compare its
output rather than trusting the exit code — `preflight` and `import-key` both do.

### If the Sparkle key is ever lost

Read this before doing anything else.

Every installed copy of Applite has `SUPublicEDKey` baked into its `Info.plist` and **rejects any
update not signed by the matching private key**. Sparkle has no key-rotation mechanism. Publishing a
new keypair means every existing install silently stops updating, forever, and each of those users
has to be told to download the app again by hand.

So before concluding it's gone: check 1Password and any other password manager, Time Machine copies
of `~/Library/Keychains/login.keychain-db`, iCloud Keychain on another device, and any other Mac
that has ever built Applite.

If you find a candidate, `release.sh import-key <file>` performs the conclusive test for you — the
right key reproduces a *byte-identical* signature for an already-published DMG, because Ed25519
signing is deterministic. By hand that is:

    "$(Scripts/Release/release.sh sparkle-bin)/sign_update" \
        --ed-key-file <key> ~/Documents/Applite/versions/v1.3.1/Applite.dmg
    # must print the same edSignature as the 1.3.1 item in appcast.xml

## Running a release

    Scripts/Release/preflight.sh                        # optional, but do it first
    Scripts/Release/release.sh run 1.4.0 --skip-notarize --dry-run   # ~2 min rehearsal
    Scripts/Release/release.sh run 1.4.0 --dry-run                   # full rehearsal
    Scripts/Release/release.sh run 1.4.0                             # the real thing

| Step | Notes |
|---|---|
| `preflight` | Credentials, toolchain, clean tree, appcast validity |
| `bump` | `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION`, committed locally, not pushed |
| `notes-draft` | Writes `changelog-raw.md` plus seeded `release-notes.md` and `website-notes.md` |
| **`notes-gate`** | Stops until you delete the draft sentinel from both notes files |
| `archive` | Clean release build, a few minutes |
| `export` | Re-signs to Developer ID via `ExportOptions.plist` |
| `verify-app` | Signature, hardened runtime, timestamp, universal, versions read back |
| `notarize-app` | Apple round trip, then staples the `.app` |
| `dmg` | Draws the background, runs `create-dmg`, re-checks the ticket inside the image |
| `notarize-dmg` | Signs the DMG with a secure timestamp, notarizes, staples |
| `sign-update` | Sparkle signature + byte length |
| `notes-website` | Converts `website-notes.md` into the aerolite Swift snippet |
| `github-release` | Pushes `main`, creates the release, uploads `Applite.dmg` |
| `appcast` | Inserts one `<item>` and shows you the diff |
| **`site-gate`** | Stops until the notes page is live on aerolite.dev |
| `publish-appcast` | Commits and pushes `appcast.xml`, then waits for Pages |
| `archive-artifacts` | Copies app, DMG and dSYMs to `~/Documents/Applite/versions/` |

### The two gates

**`notes-gate`.** Skim `changelog-raw.md`, then write **two** files. The gate holds until the
`APPLITE-RELEASE-NOTES-DRAFT` comment is gone from both.

| File | Goes to | Shape |
|---|---|---|
| `release-notes.md` | The GitHub release body, verbatim | Everything that changed, in full |
| `website-notes.md` | The Sparkle update panel and aerolite.dev | ~5 one-line bullets, no jargon |

They are separate on purpose. The Sparkle panel is a small window someone skims mid-update — it
needs a glance at the headline changes, not a changelog. GitHub is where the detail belongs, and
nobody reading it minds length.

Both use the same headings (`### New Features` / `### Improvements` / `### Fixes` /
`### Known Issues`) because both are parsed the same way; keep them. Delete any section you don't
need — empty ones are dropped, and the model's initialiser defaults them to `[]`.

**`site-gate`.** Paste `notes/AppliteReleaseModel.swift.txt` into aerolite's
`Sources/App/PageModels/AppliteReleases/AppliteReleases.swift`, push, and deploy (ssh to the VPS,
`git pull`, `docker compose up -d --build`). The gate polls the real URL, and the Vapor route 404s
on a missing dictionary key — so a 200 proves the entry is live on the deployed instance, not just
that the site is up.

### Resuming

Re-run the identical command. Steps that finished are skipped; the gates re-check their condition.

    release.sh run 1.4.0 --from export     # redo export and everything after it
    release.sh run 1.4.0 --only dmg --force  # iterate on the DMG window alone
    release.sh status 1.4.0

- **Build failed after the bump commit** → `git reset --hard HEAD~1`. Nothing was pushed.
- **Ctrl-C during notarization** → the submission id is on disk before anything can fail:
  `xcrun notarytool wait "$(cat build/release/v1.4.0/logs/notarize-app.submission-id)" --keychain-profile applite-notary`
- **Notarization rejected** → resume `--from export`, not `--from notarize-app`. The binary has to
  be rebuilt; resubmitting the same bytes cannot help.

### Dry runs

`--dry-run` still **builds for real** — archive, export, notarize, staple, DMG. A rehearsal that
doesn't produce a signed, notarized DMG isn't a rehearsal. Only publishing is stubbed: no commits,
no pushes, no GitHub release, the appcast is diffed rather than written, and
`~/Documents/Applite/versions/` is left alone. It does apply the version bump to `project.pbxproj`
(the built app has to carry the right version), so afterwards:

    git checkout Applite.xcodeproj/project.pbxproj

The rehearsal reminds you of this at the end. If you forget, the next real run's preflight stops on
a dirty working tree rather than doing anything strange.

Rehearsals record their progress in `state-rehearsal/`, not `state/`. That separation matters: with
a shared directory a `--dry-run` would mark every step done — including the ones it had stubbed —
and the real release afterwards would skip everything, exit 0 and publish nothing.

`--skip-notarize` additionally skips Apple's servers for a ~2-minute cosmetic pass, and implies
`--dry-run`. The DMG it produces is **not** distributable, and `github-release` runs
`stapler validate` on the artifact itself before publishing, so a leftover rehearsal DMG can't be
uploaded by mistake.

## Where things go

    build/release/v1.4.0/          gitignored
      state/                       step markers and values carried between steps
      logs/                        xcodebuild, notarytool, create-dmg
      DerivedData/                 also where the Sparkle CLI tools resolve to
      export/Applite.app           the signed, stapled app
      dmgbg/                       generated background, 1x + 2x + combined TIFF
      Applite.dmg                  the artifact
      notes/                       changelog draft, release notes, aerolite snippet

    ~/Documents/Applite/versions/v1.4.0/    app, DMG and dSYMs, kept after the release

dSYMs were not kept before, which is why crash reports from older versions can't be symbolicated.

## Version numbers

`MARKETING_VERSION` is the user-facing `1.4.0`; `CURRENT_PROJECT_VERSION` is the build number
Sparkle actually compares. The build number is chosen as

    max(CURRENT_PROJECT_VERSION, highest sparkle:version in appcast.xml + 1)

and asserted to be greater than everything published. That `max` exists because the scheme used to
bump the build number after every archive, so the project could sit one ahead of what shipped —
1.3.1 shipped as build 18 while the project said 19. That archive post-action has been removed;
`release.sh` owns the bump now.

**`agvtool` is not used, and must not be.** `agvtool what-marketing-version` reports finding
`CFBundleShortVersionString` of `""` in `Applite/Applite-Info.plist` — a key that isn't in that
file — because it misreads the `GENERATE_INFOPLIST_FILE = YES` setup. `agvtool new-marketing-version`
would then *write* that key into the plist, permanently shadowing `MARKETING_VERSION` and
desynchronising the version from the build settings in a way nobody would notice for months.
`release.sh` edits `project.pbxproj` with `sed` and verifies the result through
`xcodebuild -showBuildSettings` for both configurations — a grep can't prove a setting resolves.

## The appcast

`appcast.xml` at the repo root **is** the live feed: GitHub Pages serves `main`'s root at
`https://milanvarady.github.io/Applite/appcast.xml`, which is the `SUFeedURL` in every shipped
build. Pushing it publishes it. There is no other copy — if you find one, it's stale.

**`generate_appcast` is deliberately not used.** It rewrites the whole file, so every release would
produce an unreviewable diff; it prunes old items; it points enclosures at a `--download-url-prefix`
rather than the per-tag GitHub release URL; and it drops `<sparkle:releaseNotesLink>` entirely. All
four were visible in the stale `~/Documents/Applite/updates/appcast.xml` it had left behind.
`appcast_insert.py` instead splices one templated `<item>` in as text and validates the feed as XML
before *and* after — one item added, everything else byte-identical.

Fields worth knowing about:

- **`pubDate`** is generated with `LC_ALL=C`. Without it, the Hungarian system locale emits
  `sze, 05 aug. 2026`, which is not RFC 822 and Sparkle cannot parse. The script also regex-checks it.
- **`minimumSystemVersion`** is read from the built app's `LSMinimumSystemVersion`, never hardcoded.
  Hardcoding is exactly how every item up to 1.3.1 ended up claiming 13.0 after the deployment
  target moved to 14.0 — which would offer the update to macOS 13 users who then can't launch it.
- **`length`** must be the byte count of the final, stapled DMG. Sparkle rejects a download whose
  size doesn't match exactly. Nothing may touch the DMG after `sign-update`.
- **Critical updates**: `--critical` sets both `<sparkle:criticalUpdate>` in the feed and
  `isCritical: true` in the website snippet, so the two can't disagree.

Rebuilding the DMG clears the `appcast` marker, so the step has to be re-runnable. It passes
`--replace-existing`, which rewrites the item for that version in place. Doing it that way rather
than reverting the file with git matters — a `git checkout appcast.xml` would also discard any other
uncommitted edit to the feed.

## The DMG

The background is **generated** by `make_dmg_background.swift` at build time — no image asset in the
repo, nothing to reopen in Affinity. Edit the constants at the top of that file to move things.

`create-dmg` cannot draw an arrow: its whole visual surface is `template.applescript`, which sets
window bounds, icon size, icon positions and `background picture` — nothing else. Every DMG arrow
you've ever seen is pixels in the background image, which is why the background exists at all.

Two things about that file worth not undoing:

- The wash is drawn at 140×100 and scaled up. Core Graphics dithers gradients, and that per-pixel
  noise is incompressible — drawing it at full size made the background 709 KB and the DMG 17%
  bigger than 1.3.1, for the smoothest part of the image. At 1/4 scale it's 317 KB and looks
  identical. The arrow and caption are drawn afterwards at full resolution.
- The 1x and 2x renders are combined with `tiffutil -cathidpicheck`, which marks both as measuring
  560×400 *points*. That marking is what makes Finder render it sharply on Retina. Round-tripping
  the PNGs through JPEG breaks it — the 2x rep comes back claiming 1120×800 points.

`--codesign` and `--notarize` are deliberately **not** passed to `create-dmg`: it signs with a bare
`codesign -s` and no `--timestamp` (which notarization requires), and its `--notarize` never inspects
the submission status, so a rejection surfaces as a confusing stapler error. `release.sh` does both
itself and parses the result.

Iterate on the window with `release.sh run <version> --only dmg --force`.

## Signing and stapling order

**Sign → notarize → staple. Never `codesign` after stapling.** The ticket is stored inside the
bundle; re-signing invalidates it.

Both the `.app` and the DMG are notarized and stapled, in that order. The DMG alone isn't enough:
Sparkle copies `Applite.app` *out* of the disk image, and the DMG's ticket doesn't travel with the
extracted app — so an auto-updated app first launching offline, or behind a proxy that blocks
Apple's notary endpoints, would be rejected by Gatekeeper. 1.3.1 was stapled at both levels; this
keeps that.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `hdiutil: Resource busy` | Already retried 8×; close any Finder window showing a mounted Applite volume |
| Notarization `Invalid` | `build/release/v<v>/logs/notarize-*.log.json` has the per-file reason |
| Export: "No profiles found" | Set `signingStyle` to `automatic` in `ExportOptions.plist` and add `-allowProvisioningUpdates` to the export step |
| Sparkle: "update is improperly signed" | `length` or `edSignature` doesn't match the served bytes — the DMG changed after `sign-update` |
| Appcast pushed but no update offered | Pages caches; `curl -H 'Cache-Control: no-cache'` the feed, and check the build number is higher than the installed one |
| `generate_keys -p` prints nothing | The key isn't in the keychain. See *If the Sparkle key is ever lost* |

# Applite test harness

## Non-destructive external-install regression tests

Creating a missing custom app directory must not change its captured Homebrew configuration.

Hidden-self fixtures ensure an external Applite bundle contributes neither a row
nor a badge. A paused reconciliation also verifies the real operation remains busy
in the status summary until post-install ownership refresh completes.

Review-race fixtures also cover an Install before initial detection, configuration
changes before confirmation/queued execution, retained stdout/stderr after a failed
reconciliation, and a paused scan completing after detection is disabled/re-enabled.
Upstream-review fixtures additionally cover bulk external exclusion and mixed batches,
disabled/re-enabled consent, stale receipt snapshots, busy reconciliation, debounced
path edits, and cancellation of superseded scan work. Receipt refresh tolerates
replacement-scan cancellation but propagates parent cancellation, a changed
Homebrew configuration, and unexpected scan cancellation.
Batch fixtures also switch Homebrew during streamed output and during the final
receipt query, asserting that neither stale result changes installed state.
Additional cases cover single-install profile changes, retained stale-batch output,
blocked imports with stale receipt flags, outdated-state clearing, and empty scans
without materializing unrelated catalog records.
Legacy records with missing artifact names query the selected Homebrew before single
and bulk installs; tests cover renamed external bundles, missing live artifacts, and
an install with verified non-conflicting targets.

These tests use the real app's Debug module, isolated databases, temporary app
directories, and a temporary fake `brew`. They verify artifact decoding (including
renamed targets), v1 database migration/FTS preservation, managed/external/missing
state precedence, full-token identity, external filter membership/counts, command
confirmation/quoting, the default-enabled detection setting and immediate disable
guards (including pending confirmations), and queued adoption success/failure with stderr capture.
The separate management-offer setting defaults to off; tests verify explicit opt-in,
preserved management choices across detection changes, and guards that block new
and already-open management confirmations without clearing external detection.
They do not launch Applite, run real Homebrew, modify installed apps, show notification
permission prompts, or use your Applite preferences/database.

```sh
xcodebuild -quiet -project Applite.xcodeproj -scheme Applite -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/applite-build \
  CODE_SIGNING_ALLOWED=NO build
bash Testing/run-external-install-tests.sh /tmp/applite-build
```

For a visual/end-to-end check in a disposable VM, place a known cask's expected
bundle in `/Applications` without installing its cask in the selected Homebrew.
Refresh Applite and check its **Installed externally** card, sidebar badge, and
search filter. Cancel adoption once to verify no change; confirm it and check the
displayed command, then verify the app becomes **Installed** and leaves the external
list. Trigger a failed adoption and use the card's terminal button to inspect stderr;
the external status and count must remain unchanged. Also check a managed app and
an absent app still offer Open and Install respectively.

In **Settings > Brew > App Sources**, verify **Detect externally installed apps**
starts enabled. Disable it while viewing the external list or using its search
filter: the filters should disappear, navigation should leave the hidden external
list, and external status/counts should clear immediately without changing managed
apps. Re-enable it and check that local external apps are rediscovered without a
catalog download.

With no saved management preference, **Offer Manage with Homebrew** should start
off. Verify it is indented beneath detection, greyed out and disabled when detection
is off, and displays **Requires external app detection.** Re-enabling detection must
restore the saved management choice, not enable it automatically.

Enable **Offer Manage with Homebrew**, then disable it separately: external status,
filters, and counts should remain, while external cards show **Open** instead of
**Manage with Homebrew**. Re-enable it to restore the management offer.

## Non-destructive single-instance regression tests

Run `bash Testing/run-single-instance-tests.sh` to exercise the production lock
without launching Applite or touching its preferences, database, or Homebrew.
Tests cover concurrent processes, ownership release, abrupt process exit, stale
lock files, explicit I/O failures, and selecting Uninstall before opening Settings,
including repeat requests when Uninstall is already selected.
They also verify that the Updates pane is selected and Settings is opened or focused
before exactly one update-check callback runs per request, including repeated requests.
Status-summary cases cover simultaneous refresh/tasks, queued or running work,
retained failures, measured download fractions, installed-state loading, unavailable
update checks, and completed tasks returning to Ready without a stuck spinner.
Standalone update-check retries are verified while paused in the fake brew:
busy lifetime and refresh gating must remain active until completion.
App-info fixtures verify friendly names, description/version metadata, and
compatibility with older saved info values that lack those optional fields.

For a manual UI check, launch Applite, then attempt to launch another copy with the
same bundle identifier. The existing main window should come forward without an
"already running" dialog or another persistent process. Repeat with the main
window minimized or closed while Settings remains open; it should be restored or
reopened. Quit and launch again to verify normal startup. Older copies that were
already running before this fix must be quit once; the new version does not
terminate another copy's in-progress Homebrew work.

Also open **Settings > Uninstall**, then choose **Uninstall Applite...** from the app
menu repeatedly and, with the [diagnostic self-card](#optional-applite-self-card)
enabled, use its trash action. Each entry point should
select and focus the same Settings window, retaining the current uninstall options.
Repeat from another Settings tab and with Settings closed or minimized. Merely
opening the pane must not start an uninstall; do not confirm an actual uninstall
on a shared machine.

Choose **Check for Updates...** from the app menu with Settings closed, on another
tab, and already on Updates. Each request should select and focus **Settings > Updates**
and start the existing Sparkle check once. While checking, the menu item should be
disabled. Cancel or dismiss the result; do not install an update during this check.

Choose **Refresh App Catalog** from the app menu. The main window should show a
spinner and **Refreshing app catalog...** status throughout the existing refresh,
without replacing the catalog or blocking browsing. The spinner and refresh label
should clear when the operation finishes, returning to current activity or Ready;
failures must still use the existing error alert. Also verify the status appears
when a refresh is started from the Brew settings refresh prompt.

In Updates, verify the self-updating-app checkbox and its info popover are absent
from the toolbar, while Refresh and search remain. The self-updating-app preference
must remain available in Settings and still control the next outdated-app check.

Verify the bottom bar remains visible while idle and its refresh icon starts the
same manual catalog refresh. It must disable during refresh, installed-state
loading, startup/setup, or Homebrew maintenance, and re-enable afterward. Click the
Tasks shortcut with running/queued tasks or retained failures and verify it opens
Active Tasks, clearing any active search. In a disposable test environment, check
install/update/uninstall labels, real download percentages, bulk completed counts,
and failures that show a warning rather than an endless spinner. Opening Tasks or
refreshing the catalog must not cancel an ongoing operation.

Click an app's name in Discover, search, Installed, and Updates. It must keep its
friendly name, show a loading indicator during the request, and open the same
Get Info destination as the ellipsis/right-click menu. Other cards' names must not
change. Verify the info window's friendly title, description, available version,
and existing installation/source details; repeat the action and confirm the same
unchanged info value focuses its existing window. Cmd-click must open only the
homepage, not details. With an unavailable brew, the request must surface an error
and re-enable the title/menu action for retry.

## Optional Applite self-card

There is no Advanced Debug settings pane. The internal preference
`Preferences.showAppliteInInstalledList` defaults to **false**, including in Debug
builds, so normal Installed lists do not contain Applite itself. The ordinary
catalog entry stays excluded from app grids regardless of this preference; opting
in restores only the dedicated diagnostic self-card in Installed.

Quit Applite before changing the preference, then reopen it afterward. To enable:

```sh
defaults write dev.aerolite.Applite showAppliteInInstalledList -bool true
```

To disable again:

```sh
defaults write dev.aerolite.Applite showAppliteInInstalledList -bool false
```

Use your build's bundle identifier instead if it differs. These commands affect
only self-card visibility, not installed-app detection, Homebrew receipts, or
update/uninstall availability in the app menu and Settings. Verify a fresh
preference domain hides the card, opting in shows exactly one self-card only in
Installed, and opting out hides it again without changing the other app cards.

## Non-destructive favicon tests

Proxy fixtures cover a cached failure and a paused old request after route changes.
Redirected error/non-HTML responses and exact-cutoff unclosed script/style/comment
prefixes verify the fallback origin and ignored-region boundaries.

Review fixtures cover head-like text inside scripts/styles/comments, target-only
base elements, numeric/named character references and decoded scheme rejection.
The module harness also verifies downloader reuse and replacement after an
effective proxy change without making an image network request.

```sh
bash Testing/run-favicon-tests.sh
bash Testing/run-favicon-tests.sh --live
```

The default run compiles the production resolver and uses an isolated URLProtocol
fixture session. It checks declared icon and touch-icon links, redirects, HTML
base URLs, relative/protocol-relative paths, entity escaping, duplicates, URL
scheme/credential rejection, candidate limits, concurrent/cached discovery,
offline/HTTP/non-HTML failures, and the exact 128 KiB HTML cutoff.

`--live` additionally checks the real Copilot CLI primary icon URL, resolves its
metadata homepage, downloads the selected website icon, and decodes its pixels.
This performs public HTTP requests only: no GUI launch, Homebrew operations,
application changes, or access to the user's database/preferences.

For a manual UI check, verify a working primary icon stays unchanged and makes no
homepage request. Search for GitHub Copilot CLI and verify its missing primary
icon falls back to the GitHub Docs favicon. Check the same behavior in migration
selection rows. When offline or when all candidate images fail, the letter tile
must remain visible without an endless spinner. Check that the fallback image
cache cannot replace a primary icon and that scrolling repeated rows shares
discovery requests. Missing favicons are logged, not presented as blocking alerts.

## Guided end-to-end harness

`applite_test.py` is a **guided** end-to-end test harness. It doesn't automate the
UI — *you* perform each action in the real Applite window, and after each step the
script independently verifies the real result via the Homebrew CLI + filesystem
(`brew info --json=v2`, the Caskroom, `/Applications`) and prints **PASS / FAIL**.
Purely-visual outcomes (a green tick clearing, a dialog appearing) are guided `y/N`
confirmations. The "no Command Line Tools dialog" rule is stated **once** at the start
of the annex round as an invariant — if that dialog ever appears, you abort and report
it, rather than being asked about it every step.

It exists because Applite's real risk lives in the Homebrew integration — the
CLT-free "annex" flow, FFI quarantine/trash, pty-streamed installs, the annex
refresh (tarball overlay + `brew cleanup --prune=all` cache reclaim) — which is
impractical to unit-test and needs a real (fresh, CLT-free) machine to exercise.

Run it on a **throwaway VM**, not your dev machine — it hides/deletes Homebrew and
wipes Applite's data.

## Requirements

- A macOS VM, Apple Silicon assumed (`/opt/homebrew`). Note: Apple-Silicon VMs have no
  native snapshots — see "No snapshots" below for the baseline strategy.
- **A standalone Python 3** — python.org's installer (gives `/usr/local/bin/python3`)
  or `uv python install`. Do **not** use `/usr/bin/python3`: it's a Command Line
  Tools stub that pops the very install dialog we simulate away, and it stops working
  once CLT is hidden. The script refuses to run under it. Stdlib only — nothing to
  `pip install`.

Invoke it with the standalone interpreter explicitly, e.g. `/usr/local/bin/python3 applite_test.py …`.

**Forgot the commands?** Run it with no arguments — `applite_test.py` prints the full
pass in order, the partial-run flags, and every phase id per round.

## How it works: rounds + hide/unhide

Applite behaves differently depending on which brew it drives, so we test both:

- **Round A — annex brew, CLT-free.** Applite installs its own bundled Homebrew and
  runs it without the Command Line Tools. This is the risky path.
- **Round B — external `/opt/homebrew`.** The user's own full Homebrew (real git,
  Swift quarantine, none of the annex env). A shorter core-lifecycle re-run.

Plus two rounds that stand apart from the A→B sequence:

- **Round U — upgrade from v1.3.1.** Its own pass, from its own `reset`, because it
  starts from an *old install* rather than a clean machine. Every existing user arrives
  this way and this release moved their storage underneath them (JSON cache → GRDB,
  onboarding removed, annex `Applite/homebrew` → `Applite/Homebrew` — a case-only
  rename, so the same directory on a default APFS volume and a different one on a
  case-sensitive volume). Run it once per release.
- **Round `finalize` — self-uninstall.** Always last; it removes Applite.

Installing brew + CLT takes ~10 min, so we don't do it every run. Instead:

1. `provision` **once** installs Homebrew + CLT (if missing) and then **hides** them
   (renames `/opt/homebrew` and `/Library/Developer/CommandLineTools` aside, and
   `xcode-select --reset`). Hidden ⇒ the machine genuinely reads as CLT-free with no
   system brew, which is exactly Round A's starting condition.
2. `reset` returns to a fresh baseline: it (a) `brew uninstall`s whatever is still
   linked, then (b) removes the known test casks **by name from the catalog** — their
   `.app` bundles, uninstall/zap paths, and pkg receipts — independent of brew's
   receipts, then wipes Applite's data and hides the prereqs. The name-based step is
   essential because the Reinstall Homebrew phase unlinks previously-installed apps,
   so `brew uninstall` alone can no longer see them.
3. Round B's first phase **unhides** them and `brew update`s.

### No snapshots on Apple-Silicon UTM

macOS guests on Apple Silicon use Apple's Virtualization framework, which has **no
snapshot support** — so `reset` is what returns you to a clean state (it uninstalls
all casks rather than assuming a snapshot rollback). If you'd rather roll back the
whole disk, the only option is to **duplicate the `.utm` bundle** in UTM before a run
(a full copy) and restore from that. `reset --keep-apps` skips the uninstall sweep if
you're managing app state yourself.

## Full pass

```sh
PY=/usr/local/bin/python3            # your standalone interpreter

$PY applite_test.py provision        # once per VM  → then save a baseline (duplicate the .utm bundle; see below)
$PY applite_test.py reset            # hide prereqs + wipe Applite
# → launch Applite, then:
$PY applite_test.py run --round annex
$PY applite_test.py run --round external
$PY applite_test.py run --round finalize   # self-uninstall (LAST)
$PY applite_test.py teardown         # re-hide prereqs, keep them cached
```

Once per release, as a **separate pass** from its own reset:

```sh
$PY applite_test.py reset
$PY applite_test.py run --round upgrade    # install v1.3.1 first, then the new build over it
```

Each `run` prints a PASS/FAIL/SKIP summary and appends to `Testing/applite-test.log`.

### Running part of a round

```sh
$PY applite_test.py run --round annex --only 6      # just the update phase
$PY applite_test.py run --round annex --from 9      # phase 9 (catalog) onward
$PY applite_test.py run --round external --only B3
```

Phase ids per round are listed by running the script with no arguments.

### Other subcommands

| Command | What it does |
|---|---|
| `reset [--keep-apps]` | Fresh state: uninstall all casks + wipe Applite + hide prereqs. `--keep-apps` skips the uninstall sweep. |
| `preflight [--round ...]` | Validate the configured test casks against the live catalog. Run before a pass. |
| `verify [--round ...]` | Print current brew health, installed/outdated casks, and the hide/unhide state. |
| `fake-outdated <token> [--round ...]` | Rename a cask's installed version to `0.0.1` so `brew outdated` reports it (used by the update phases). |
| `teardown [--full]` | Default: uninstall all casks, wipe Applite, re-hide prereqs. `--full`: also delete `/opt/homebrew`, CLT, and caches for a pristine image. |

## Test casks

Set at the top of `applite_test.py` (one per installer type); `preflight` re-checks each:

| Var | Default | Role |
|---|---|---|
| `DMG_CASK` | `rectangle` | `.app` DMG |
| `PKG_CASK` | `zoom` | `.pkg` installer |
| `ZAP_CASK` | `stats` | has a `zap trash:` stanza |
| `UPDATE_CASK` | `font-hack` | versioned, **`auto_updates: false`** — required so non-greedy `brew outdated` will report the faked-old version |
| `WARN_CASK` | `aegisub` | **deprecated** → triggers the download warning dialog (and checks a deprecated cask still installs — deprecation stays a warning, not a hard error) |
| `CANCEL_CASK` | `libreoffice` | large download so there's time to hit Stop mid-download (the harness clears its cache first); reused for the quit-mid-install phase |
| `FAIL_CASK` | `blackhole-2ch` | small **pkg** cask that always needs admin — cancelling its password dialog is a deterministic, offline-safe way to force a *failed* install. Must be used by no other phase, or it'd already be installed |
| `BULK_INSTALL_CASKS` | `hiddenbar`, `mos`, `font-fira-code` | set imported in one batch (`installAll`) — proves reliable bulk install + per-cask rings + one summary (just one font: fonts are barely used, and the harness cleans their files so a fresh install works) |
| `BULK_UPDATE_CASKS` | `hiddenbar`, `mos` | subset of the above (apps, not fonts), fake-outdated then "Update All" — need `auto_updates:false` **and a concrete version** (not `:latest`) |
| `BULK_STOP_CASKS` | `libreoffice`, `inkscape` | two big downloads so the batch is still running when you exercise the batch Stop |

Cask metadata drifts. If `preflight` flags one (wrong artifact type, `auto_updates`
became true, no zap/caveat), swap that variable for a cask that fits the role — the
table it prints tells you what it detected.

## The tap fixture (phase 16)

Phase 16 needs a third-party tap containing (a) a token that exists nowhere else and
(b) a token that **collides with a core cask**. Rather than depend on someone's real
tap, the harness writes one itself into `<brew prefix>/Library/Taps/applite-harness/
homebrew-fixtures/`: no git, no network, no `brew tap`. Brew enumerates tap directories
directly, and Applite's `brew-tap-cask-info.rb` loads them through `FromPathLoader`
(which it un-trusts), so a plain directory of `.rb` files is enough — which also keeps
the phase runnable on the CLT-free annex, where there is no real git.

Both fixture casks point at an unreachable URL: they exist to be *listed*, never
installed. `reset` and `teardown` remove the fixture from both prefixes; a clean annex
reinstall (phase 20) wipes it too.

It guards two regressions worth naming:

- **Tap casks vanishing.** `Shell`'s stream reader used to drop the tail of a command's
  output; `brew ruby`'s tap listing was the only thing big enough to hit it, so custom
  taps silently disappeared from the catalog.
- **Token collisions (P2-29).** Casks were once keyed by the bare token, so a tap's
  `rectangle` and core `rectangle` collapsed into one row. Identity is `fullToken` now,
  and `brew list --cask --full-name` is matched *exactly* — a bare-token match let a tap
  cask inherit the core cask's installed state.

## Safety

- The harness only ever **renames** (`sudo mv`, reversible) a system brew/CLT to
  hide/restore them. It **deletes** `/opt/homebrew` + CLT only under the explicit
  `teardown --full`.
- Outright deletes are a fixed allowlist of Applite's own data + the annex + brew
  caches + the specific test-cask apps + the harness's own tap fixture — never
  `/opt/homebrew`, `/usr/local`, `/Library/Developer`, or anything `$HOME`-wide. The
  fixture cleanup removes only `Library/Taps/applite-harness/`, never a real tap.
- Hiding/unhiding needs `sudo` (you'll be prompted) and Applite to be quit.

## Caveats

- **Assumes CLT-only** (no full Xcode) on the VM. If Xcode.app is installed, the
  machine won't read as CLT-free after hiding — also remove/rename Xcode or point
  `xcode-select` away first. `reset` warns if it detects this.
- The assertions deliberately avoid invoking `/usr/bin/git|swift|xcrun` (that would
  itself pop the dialog); "CLT-free" is checked via `xcode-select -p` pointing at a
  missing dir.
- A few things are guided visual checks, not hard assertions: cancel-mid-download
  timing, proxy/mirror, the get-info/terminal windows. Sparkle's *toggle plumbing* is
  checked (phase 17) but an actual self-update is not — that needs a signed build and a
  real appcast.
- The upgrade round needs you to fetch v1.3.1 from the GitHub releases page by hand; it
  restores the CLT first, since an upgrader's machine has them.
- Not a CI tool — it's an interactive pre-release checklist meant to be run by hand.

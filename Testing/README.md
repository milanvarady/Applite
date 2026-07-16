# Applite test harness

`applite_test.py` is a **guided** end-to-end test harness. It doesn't automate the
UI — *you* perform each action in the real Applite window, and after each step the
script independently verifies the real result via the Homebrew CLI + filesystem
(`brew info --json=v2`, the Caskroom, `/Applications`) and prints **PASS / FAIL**.
Purely-visual outcomes (green tick cleared, no CLT popup, a dialog appeared) are
guided `y/N` confirmations.

It exists because Applite's real risk lives in the Homebrew integration — the
CLT-free "annex" flow, FFI quarantine/trash, pty-streamed installs — which is
impractical to unit-test and needs a real (fresh, CLT-free) machine to exercise.

Run it on a **throwaway VM**, not your dev machine — it hides/deletes Homebrew and
wipes Applite's data.

## Requirements

- A macOS VM you can snapshot. Apple Silicon assumed (`/opt/homebrew`).
- **A standalone Python 3** — python.org's installer (gives `/usr/local/bin/python3`)
  or `uv python install`. Do **not** use `/usr/bin/python3`: it's a Command Line
  Tools stub that pops the very install dialog we simulate away, and it stops working
  once CLT is hidden. The script refuses to run under it. Stdlib only — nothing to
  `pip install`.

Invoke it with the standalone interpreter explicitly, e.g. `/usr/local/bin/python3 applite_test.py …`.

## How it works: two rounds + hide/unhide

Applite behaves differently depending on which brew it drives, so we test both:

- **Round A — annex brew, CLT-free.** Applite installs its own bundled Homebrew and
  runs it without the Command Line Tools. This is the risky path.
- **Round B — external `/opt/homebrew`.** The user's own full Homebrew (real git,
  Swift quarantine, none of the annex env). A shorter core-lifecycle re-run.

Installing brew + CLT takes ~10 min, so we don't do it every run. Instead:

1. `provision` **once** installs Homebrew + CLT (if missing) and then **hides** them
   (renames `/opt/homebrew` and `/Library/Developer/CommandLineTools` aside, and
   `xcode-select --reset`). Hidden ⇒ the machine genuinely reads as CLT-free with no
   system brew, which is exactly Round A's starting condition.
2. `reset` (fast) re-hides the prereqs and wipes Applite's data — the fresh baseline.
3. Round B's first phase **unhides** them and `brew update`s.

**Snapshot the VM right after `provision`** — then every run is just `reset` (seconds)
instead of a reinstall.

## Full pass

```sh
PY=/usr/local/bin/python3            # your standalone interpreter

$PY applite_test.py provision        # once per VM  → then snapshot the VM
$PY applite_test.py reset            # hide prereqs + wipe Applite
# → launch Applite, then:
$PY applite_test.py run --round annex
$PY applite_test.py run --round external
$PY applite_test.py run --round finalize   # self-uninstall (LAST)
$PY applite_test.py teardown         # re-hide prereqs, keep them cached
```

Each `run` prints a PASS/FAIL/SKIP summary and appends to `Testing/applite-test.log`.

### Running part of a round

```sh
$PY applite_test.py run --round annex --only 7      # just the update phase
$PY applite_test.py run --round annex --from 8      # phase 8 onward
$PY applite_test.py run --round external --only B3
```

### Other subcommands

| Command | What it does |
|---|---|
| `preflight [--round ...]` | Validate the configured test casks against the live catalog. Run before a pass. |
| `verify [--round ...]` | Print current brew health, installed/outdated casks, and the hide/unhide state. |
| `fake-outdated <token> [--round ...]` | Rename a cask's installed version to `0.0.1` so `brew outdated` reports it (used by the update phases). |
| `teardown [--full]` | Default: re-hide prereqs + wipe Applite (fast, reusable). `--full`: delete `/opt/homebrew`, CLT, and caches for a pristine image. |

## Test casks

Set at the top of `applite_test.py` (one per installer type); `preflight` re-checks each:

| Var | Default | Role |
|---|---|---|
| `DMG_CASK` | `rectangle` | `.app` DMG |
| `PKG_CASK` | `zoom` | `.pkg` installer (exercises the appdir path) |
| `ZAP_CASK` | `stats` | has a `zap trash:` stanza |
| `UPDATE_CASK` | `font-hack` | versioned, **`auto_updates: false`** — required so non-greedy `brew outdated` will report the faked-old version |
| `WARN_CASK` | `aegisub` | **deprecated** → triggers the download warning dialog (and probes the HOMEBREW_DEVELOPER deprecation risk) |
| `CANCEL_CASK` | `libreoffice` | large download so there's time to hit Stop mid-download (the harness clears its cache first) |
| `IMPORT_CASKS` | `hiddenbar`, `mos` | small casks not installed elsewhere, so the import phase proves it actually installs |

Cask metadata drifts. If `preflight` flags one (wrong artifact type, `auto_updates`
became true, no zap/caveat), swap that variable for a cask that fits the role — the
table it prints tells you what it detected.

## Safety

- The harness only ever **renames** (`sudo mv`, reversible) a system brew/CLT to
  hide/restore them. It **deletes** `/opt/homebrew` + CLT only under the explicit
  `teardown --full`.
- Outright deletes are a fixed allowlist of Applite's own data + the annex + brew
  caches + the specific test-cask apps — never `/opt/homebrew`, `/usr/local`,
  `/Library/Developer`, or anything `$HOME`-wide.
- Hiding/unhiding needs `sudo` (you'll be prompted) and Applite to be quit.

## Caveats

- **Assumes CLT-only** (no full Xcode) on the VM. If Xcode.app is installed, the
  machine won't read as CLT-free after hiding — also remove/rename Xcode or point
  `xcode-select` away first. `reset` warns if it detects this.
- The assertions deliberately avoid invoking `/usr/bin/git|swift|xcrun` (that would
  itself pop the dialog); "CLT-free" is checked via `xcode-select -p` pointing at a
  missing dir.
- A few things are guided visual checks, not hard assertions: cancel-mid-download
  timing, proxy/mirror, Sparkle self-update, the get-info/terminal windows.
- Not a CI tool — it's an interactive pre-release checklist meant to be run by hand.

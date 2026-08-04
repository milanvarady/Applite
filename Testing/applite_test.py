#!/usr/bin/env python3
"""
applite_test.py — guided end-to-end test harness for Applite.

Applite is a SwiftUI GUI over Homebrew. Its real risk lives in the brew
integration (CLT-free annex flow, FFI quarantine/trash, pty-streamed installs),
which is impractical to unit-test. This harness instead drives a repeatable
manual pass: YOU perform each action in the real Applite UI, and after each step
the script independently verifies the real side effect via the brew CLI +
filesystem (`brew info --json=v2`, the Caskroom, /Applications), printing
PASS / FAIL. Purely-visual outcomes (green tick cleared, no CLT popup, a dialog
appeared) are guided y/N confirmations.

Run it with NO arguments to print the full pass in order plus every phase id — that
cheat sheet is the answer to "what were the commands again?". See Testing/README.md for
the reasoning behind each round. Short version:

    # once per VM (installs brew + CLT if missing, then hides them):
    /usr/local/bin/python3 applite_test.py provision
    # (snapshot the VM here)

    /usr/local/bin/python3 applite_test.py reset            # fast fresh state
    /usr/local/bin/python3 applite_test.py run --round annex
    /usr/local/bin/python3 applite_test.py run --round external
    /usr/local/bin/python3 applite_test.py run --round finalize
    /usr/local/bin/python3 applite_test.py teardown

    # once per release, as its own pass from its own reset:
    /usr/local/bin/python3 applite_test.py run --round upgrade

IMPORTANT: run this under a STANDALONE python3 (python.org or `uv`), never
`/usr/bin/python3` — that one is a Command Line Tools stub that pops the very
install dialog we simulate away (and stops working once CLT is hidden).
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

# --------------------------------------------------------------------------- #
# Config
# --------------------------------------------------------------------------- #

BUNDLE_ID = "dev.aerolite.Applite"
APPLITE_SUPPORT = Path.home() / "Library/Application Support/Applite"
ANNEX_BREW = APPLITE_SUPPORT / "Homebrew/bin/brew"
OPT_PREFIX = Path("/opt/homebrew")
OPT_BREW = OPT_PREFIX / "bin/brew"
CLT_PATH = Path("/Library/Developer/CommandLineTools")
HOMEBREW_CACHE = Path.home() / "Library/Caches/Homebrew"  # brew's default (Applite sets no HOMEBREW_CACHE)
HIDDEN_SUFFIX = ".applite-hidden"
LOG_FILE = Path(__file__).resolve().parent / "applite-test.log"

# Representative test casks (one per installer type). `preflight` re-validates
# each against the live catalog, so if a pick drifts you'll be told to swap it.
DMG_CASK = "rectangle"          # small .app-artifact DMG
PKG_CASK = "zoom"               # .pkg installer (exercises the pkg install path)
ZAP_CASK = "stats"              # distinct app with a `zap trash:` stanza
UPDATE_CASK = "font-hack"       # versioned, auto_updates:false (fonts never self-update)
WARN_CASK = "aegisub"           # deprecated → triggers the download warning dialog
#                                 (also checks a deprecated cask still installs, not hard-errors)
CANCEL_CASK = "libreoffice"     # big download so there's time to hit Stop; cache cleared first
FAIL_CASK = "blackhole-2ch"     # small pkg cask that REQUIRES admin — cancelling its password
#                                 dialog is a deterministic, offline-safe way to force a failed
#                                 install (phase 15). Must not be used by any other phase, or it
#                                 would already be installed and offer no Install button.
# Bulk (batch) test sets. Install-all runs via import; update-all via the Updates "Update All".
BULK_INSTALL_CASKS = ["hiddenbar", "mos", "font-fira-code"]  # 2 apps + 1 font (fonts barely used)
# Update-all targets: the two apps (versioned + auto_updates:false, so fake-outdatable) — NOT the
# font. Fonts persist on disk and a plain reinstall errors ("already exists"); the harness cleans
# the font's files (see _purge_known_casks) so a fresh install works, but keep them out of update.
BULK_UPDATE_CASKS = ["hiddenbar", "mos"]
BULK_STOP_CASKS = ["libreoffice", "inkscape"]  # two big downloads → time to hit the batch Stop

# --- Third-party tap fixture (phase 16) --------------------------------------
# A hand-made tap under <prefix>/Library/Taps. No git, no network, no `brew tap` — brew enumerates
# tap directories directly, and Applite's brew-tap-cask-info.rb loads them via FromPathLoader (it
# no-ops Brew 6's trust check), so a plain directory of .rb files is enough. Verified against a live
# brew. This keeps the phase runnable on the CLT-free annex, where there is no real git.
TAP_FIXTURE = "applite-harness/fixtures"        # <user>/<repo> → Taps/<user>/homebrew-<repo>
TAP_UNIQUE_CASK = "applite-harness-cask"        # a token that exists ONLY in the tap
TAP_COLLIDING_CASK = DMG_CASK                   # same bare token as a CORE cask (the P2-29 test)

# Both fixture casks point at an unreachable URL: they exist to be *listed*, never installed.
_TAP_CASK_TEMPLATE = '''cask "{token}" do
  version "{version}"
  sha256 :no_check
  url "https://example.invalid/applite-harness.zip"
  name "{name}"
  desc "Applite test-harness fixture — not installable by design"
  homepage "https://example.invalid/"
  app "{app}.app"
end
'''

# Paths the harness is allowed to delete outright (never a system brew/CLT).
def _wipe_paths() -> list[Path]:
    home = Path.home()
    return [
        APPLITE_SUPPORT,
        home / "Library/Caches/Homebrew",
        home / "Library/Caches/Applite",
        home / f"Library/Caches/{BUNDLE_ID}",
        home / f"Library/Containers/{BUNDLE_ID}",
        home / f"Library/Saved Application State/{BUNDLE_ID}.savedState",
        home / f"Library/WebKit/{BUNDLE_ID}",
        home / f"Library/HTTPStorages/{BUNDLE_ID}",
    ]


def _wipe_globs() -> list[str]:
    home = Path.home()
    return [
        str(home / f"Library/Preferences/*{BUNDLE_ID}*.plist"),
        str(home / f"Library/SyncedPreferences/*{BUNDLE_ID}*.plist"),
    ]


# The active brew executable — switched per round by `set_round`.
BREW = ANNEX_BREW

# --------------------------------------------------------------------------- #
# Output / results
# --------------------------------------------------------------------------- #

_TTY = sys.stdout.isatty()


def _c(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if _TTY else text


def _log(line: str) -> None:
    try:
        with LOG_FILE.open("a", encoding="utf-8") as fh:
            fh.write(line + "\n")
    except OSError:
        pass


def info(msg: str) -> None:
    print(_c("36", "ℹ  " + msg)); _log("INFO " + msg)


def warn(msg: str) -> None:
    print(_c("33", "⚠  " + msg)); _log("WARN " + msg)


def ok(msg: str) -> None:
    print(_c("32", "✔  " + msg)); _log("OK   " + msg)


def bad(msg: str) -> None:
    print(_c("31", "✘  " + msg)); _log("FAIL " + msg)


def heading(msg: str) -> None:
    print("\n" + _c("1;35", "━━ " + msg + " ━━")); _log("\n=== " + msg + " ===")


class Results:
    def __init__(self) -> None:
        self.passed = 0
        self.failed = 0
        self.skipped = 0
        self.failures: list[str] = []

    def add(self, passed: bool, desc: str) -> None:
        if passed:
            self.passed += 1
            ok(desc)
        else:
            self.failed += 1
            self.failures.append(desc)
            bad(desc)

    def skip(self, desc: str) -> None:
        self.skipped += 1
        warn("SKIP " + desc)

    def summary(self) -> int:
        heading("Summary")
        print(f"  {_c('32', str(self.passed) + ' passed')}, "
              f"{_c('31', str(self.failed) + ' failed')}, "
              f"{_c('33', str(self.skipped) + ' skipped')}")
        for f in self.failures:
            print("   " + _c("31", "· " + f))
        _log(f"SUMMARY passed={self.passed} failed={self.failed} skipped={self.skipped}")
        return 1 if self.failed else 0


RESULTS = Results()

# --------------------------------------------------------------------------- #
# subprocess helpers
# --------------------------------------------------------------------------- #


def run(args: list[str], *, check: bool = False, capture: bool = True,
        env: dict | None = None, timeout: float | None = None) -> subprocess.CompletedProcess:
    """Run a command. Captures output by default; pass capture=False for
    interactive commands (sudo password prompts, installers). `timeout` (seconds) guards
    against a command that blocks forever — it returns a failed result rather than wedging."""
    _log("RUN  " + " ".join(args))
    try:
        return subprocess.run(
            args,
            check=check,
            text=True,
            capture_output=capture,
            env={**os.environ, **(env or {})} if env else None,
            timeout=timeout,
        )
    except FileNotFoundError:
        # The executable isn't present — e.g. the annex brew before Applite installs
        # it, or a hidden /opt brew. Degrade to a failed command so callers (brew_healthy,
        # brew_json, …) handle it as "not available" instead of crashing with a traceback.
        return subprocess.CompletedProcess(args, returncode=127, stdout="", stderr="")
    except subprocess.TimeoutExpired as e:
        # Don't let one stuck brew call hang the whole guided run — surface it and move on.
        warn(f"command timed out after {timeout}s: {' '.join(args)}")
        return subprocess.CompletedProcess(args, returncode=124,
                                           stdout=e.stdout or "", stderr=e.stderr or "")


def sudo(args: list[str]) -> bool:
    """Run a privileged command, letting the password prompt reach the terminal."""
    cp = run(["sudo", *args], capture=False)
    return cp.returncode == 0


def _brew_env() -> dict:
    """Invoke brew the same non-interactive way Applite does (see Shell.swift) so the harness
    reproduces its behavior — and, crucially, never blocks on a Brew 6 ask-mode confirmation
    prompt. Brew 6 enables confirmation prompts by default; because we capture output, such a
    prompt would wait on stdin invisibly and the run would just "hang". `HOMEBREW_NO_ASK` (plus
    no-auto-update, which keeps git off the CLT-free annex) is what Applite sets to avoid this."""
    env = {
        "HOMEBREW_NO_ASK": "1",
        "HOMEBREW_NO_ENV_HINTS": "1",
        "HOMEBREW_NO_AUTO_UPDATE": "1",
    }
    if BREW == ANNEX_BREW:
        # The annex tracks master; its bootsnap load-path cache can go stale → LoadError. Applite
        # disables bootsnap for the annex, so the harness must too when driving it directly.
        env["HOMEBREW_NO_BOOTSNAP"] = "1"
    return env


def brew(*args: str, capture: bool = True,
         timeout: float | None = None) -> subprocess.CompletedProcess:
    return run([str(BREW), *args], capture=capture, env=_brew_env(), timeout=timeout)


def brew_json(token: str) -> dict | None:
    cp = brew("info", "--json=v2", "--cask", token)
    if cp.returncode != 0 or not cp.stdout.strip():
        return None
    try:
        casks = json.loads(cp.stdout).get("casks", [])
        return casks[0] if casks else None
    except (json.JSONDecodeError, IndexError):
        return None


def clear_cask_cache(token: str) -> None:
    """Remove a cask's cached download so the next install re-downloads (needed for
    the cancel test — a cached download completes instantly, leaving nothing to stop)."""
    # Timeout-guarded: `brew --cache` can stall on a first-of-session API refresh, and must never
    # wedge the guided run. On a stall we warn (via run's timeout path) and skip the clear.
    path = brew("--cache", "--cask", token, timeout=120).stdout.strip()
    if not path:
        return
    for p in (path, path + ".incomplete"):
        try:
            os.remove(p)
            info(f"cleared cache: {p}")
        except OSError:
            pass


def cache_download_count() -> int:
    """Number of cached download artifacts in the Homebrew cache. `brew cleanup --prune=all`
    (which the annex refresh now runs — see AnnexBrewManager.pruneAnnexCache) should drive
    this to 0. Only the `downloads/` subdir is counted, not brew's `api/` metadata cache."""
    downloads = HOMEBREW_CACHE / "downloads"
    if not downloads.is_dir():
        return 0
    return sum(1 for p in downloads.iterdir() if not p.name.startswith("."))


def seed_download_cache(token: str) -> bool:
    """`brew fetch` a cask — downloads its artifact into the cache WITHOUT installing it — so
    the prune check has something to remove. fetch never installs, so it stays CLT-free (no
    quarantine/trash). Best-effort: needs network. Returns whether the cache is now non-empty."""
    cp = run([str(BREW), "fetch", "--cask", token],
             env={"HOMEBREW_NO_AUTO_UPDATE": "1"})  # no auto-update → no git → no CLT dialog
    if cp.returncode != 0:
        warn(f"brew fetch {token} failed — can't seed the download cache (offline?)")
    return cache_download_count() > 0


# --------------------------------------------------------------------------- #
# Cask introspection (JSON-backed)
# --------------------------------------------------------------------------- #


def artifact_kind(cask: dict) -> str:
    """'app', 'pkg', or 'other' — from the cask's artifacts list."""
    for art in cask.get("artifacts", []):
        if isinstance(art, dict):
            if "pkg" in art or "installer" in art:
                return "pkg"
            if "app" in art:
                return "app"
    return "other"


def app_names(cask: dict) -> list[str]:
    """The .app bundle names a cask installs (string entries of `app` artifacts)."""
    names: list[str] = []
    for art in cask.get("artifacts", []):
        if isinstance(art, dict) and "app" in art:
            for entry in art["app"]:
                if isinstance(entry, str):
                    names.append(entry)
    return names


def font_names(cask: dict) -> list[str]:
    """The font filenames a `font` cask installs (into ~/Library/Fonts)."""
    names: list[str] = []
    for art in cask.get("artifacts", []):
        if isinstance(art, dict) and "font" in art:
            names += [e for e in art["font"] if isinstance(e, str)]
    return names


def zap_paths(cask: dict) -> list[str]:
    """Raw trash/delete paths declared in the cask's `zap` stanza (~ not expanded)."""
    paths: list[str] = []
    for art in cask.get("artifacts", []):
        if not (isinstance(art, dict) and "zap" in art):
            continue
        for directive in art["zap"]:
            if not isinstance(directive, dict):
                continue
            for key in ("trash", "delete", "rmdir"):
                val = directive.get(key)
                if isinstance(val, str):
                    paths.append(val)
                elif isinstance(val, list):
                    paths.extend(p for p in val if isinstance(p, str))
    return paths


def _expand(path: str) -> list[Path]:
    """Expand ~ and any glob into concrete existing/candidate paths."""
    expanded = os.path.expanduser(path)
    if any(ch in expanded for ch in "*?["):
        return [Path(p) for p in glob.glob(expanded)]
    return [Path(expanded)]


def _cask_json_any(token: str) -> dict | None:
    """Resolve a cask's metadata from ANY available source — a live annex or /opt brew,
    else the online Homebrew API via system curl. Used for cleanup by name, which must
    work even when no brew currently tracks the cask (e.g. after a clean annex reinstall
    unlinks installed apps)."""
    for exe in (ANNEX_BREW, OPT_BREW):
        if exe.exists():
            cp = run([str(exe), "info", "--json=v2", "--cask", token])
            if cp.returncode == 0 and cp.stdout.strip():
                try:
                    return json.loads(cp.stdout)["casks"][0]
                except (json.JSONDecodeError, IndexError, KeyError):
                    pass
    # Online fallback (system curl — no python TLS/cert dependency).
    cp = run(["/usr/bin/curl", "-fsSL",
              f"https://formulae.brew.sh/api/cask/{token}.json"])
    if cp.returncode == 0 and cp.stdout.strip():
        try:
            return json.loads(cp.stdout)
        except json.JSONDecodeError:
            pass
    return None


def removable_paths(cask: dict) -> list[str]:
    """delete/trash/rmdir paths from BOTH the `uninstall` and `zap` stanzas (raw; ~ and
    globs unexpanded). Covers pkg casks, whose app lives in `uninstall delete:` rather
    than an `app` artifact."""
    out: list[str] = []
    for art in cask.get("artifacts", []):
        if not isinstance(art, dict):
            continue
        for stanza in ("uninstall", "zap"):
            for directive in art.get(stanza, []) or []:
                if not isinstance(directive, dict):
                    continue
                for key in ("trash", "delete", "rmdir"):
                    val = directive.get(key)
                    if isinstance(val, str):
                        out.append(val)
                    elif isinstance(val, list):
                        out.extend(p for p in val if isinstance(p, str))
    return out


def pkgutil_ids(cask: dict) -> list[str]:
    """pkgutil receipt ids/regexes from the `uninstall`/`zap` stanzas."""
    out: list[str] = []
    for art in cask.get("artifacts", []):
        if not isinstance(art, dict):
            continue
        for stanza in ("uninstall", "zap"):
            for directive in art.get(stanza, []) or []:
                if isinstance(directive, dict):
                    val = directive.get("pkgutil")
                    if isinstance(val, str):
                        out.append(val)
                    elif isinstance(val, list):
                        out.extend(x for x in val if isinstance(x, str))
    return out


# --------------------------------------------------------------------------- #
# Verifiers
# --------------------------------------------------------------------------- #


def caskroom_dir() -> Path:
    return Path(BREW).parent.parent / "Caskroom"


def installed_tokens() -> list[str]:
    cp = brew("list", "--cask", "--full-name")
    return cp.stdout.split() if cp.returncode == 0 else []


def cask_installed(token: str) -> bool:
    toks = installed_tokens()
    return token in toks or any(t.endswith("/" + token) for t in toks)


def cask_absent(token: str) -> bool:
    return not cask_installed(token)


def installed_version(token: str) -> str | None:
    cask = brew_json(token)
    if cask and cask.get("installed"):
        return cask["installed"]
    # Fall back to the Caskroom directory name.
    cdir = caskroom_dir() / token
    if cdir.is_dir():
        vers = [p.name for p in cdir.iterdir() if p.name != ".metadata"]
        return vers[0] if vers else None
    return None


def outdated_lists(token: str) -> bool:
    cp = brew("outdated", "--cask", "-q")
    toks = cp.stdout.split() if cp.returncode == 0 else []
    return token in toks or any(t.endswith("/" + token) for t in toks)


def appdir() -> Path:
    """Applite's configured install dir for pkg casks (default /Applications)."""
    on = run(["defaults", "read", BUNDLE_ID, "appdirOn"]).stdout.strip()
    if on == "1":
        p = run(["defaults", "read", BUNDLE_ID, "appdirPath"]).stdout.strip()
        if p:
            return Path(os.path.expanduser(p))
    return Path("/Applications")


def app_present(name: str) -> bool:
    if not name.endswith(".app"):
        name += ".app"
    for base in ("/Applications", str(appdir()), str(caskroom_dir())):
        if (Path(base) / name).exists():
            return True
    # Caskroom nests under <token>/<version>/<App>.app — do a shallow search.
    return bool(glob.glob(str(caskroom_dir() / "**" / name), recursive=True))


def seed_zap_file(zap: list[str]) -> Path | None:
    """Create a file at a real (non-glob) zap path so `--zap` has app-data to remove.
    Without this the zap paths don't exist (the app was never launched), so the removal
    check passes vacuously and zap is indistinguishable from a plain uninstall. Returns
    the seeded path, or None if the cask declares no concrete (non-glob) zap path."""
    for raw in zap:
        if any(c in raw for c in "*?["):
            continue  # can't materialize a glob
        p = Path(os.path.expanduser(raw))
        try:
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("applite-test zap seed\n")
            return p
        except OSError:
            continue
    return None


def brew_healthy() -> bool:
    cp = brew("--version")
    return cp.returncode == 0 and "Homebrew" in cp.stdout


def brew_processes() -> list[str]:
    """`ps` lines for brew-owned processes still running — brew itself, its portable ruby, and the
    curl it spawns for downloads. Matched by path so an unrelated user `curl` isn't counted.

    Used by the quit-mid-install phase: SIGTERM alone left these behind (P3-10), so quitting Applite
    during a download used to keep downloading in the background."""
    # Deliberately narrow. Matching "anything under the brew prefix" would flag every
    # Homebrew-installed daemon on the machine (atuin, python, …) and turn this into a
    # false-failure generator, so match how brew actually runs instead:
    #   · `/bin/bash <prefix>/bin/brew …`        → the wrapper
    #   · `<prefix>/Library/Homebrew/…ruby … brew.rb` → brew proper + its portable ruby
    #   · `/usr/bin/curl … <cache>/downloads/…`  → the download it spawns
    # Match on the EXECUTABLE (argv[0]), not the whole command line — a shell whose arguments merely
    # mention brew would otherwise count. brew's ruby argv is ~8 KB of -I paths, so truncate.
    prefixes = (str(Path(BREW).parent.parent), str(APPLITE_SUPPORT / "Homebrew"), str(OPT_PREFIX))
    cache = str(HOMEBREW_CACHE)
    hits = []
    for line in run(["ps", "-Ao", "pid=,command="]).stdout.splitlines():
        parts = line.strip().split()
        if len(parts) < 2:
            continue
        pid, exe, rest = parts[0], parts[1], parts[2:]
        # `/bin/bash <prefix>/bin/brew …` (wrapper) or `<prefix>/Library/Homebrew/…/ruby …` (brew proper)
        is_brew = ("/Library/Homebrew/" in exe and any(p in exe for p in prefixes)) or (
            rest and rest[0].endswith("/bin/brew") and any(p in rest[0] for p in prefixes))
        is_download = os.path.basename(exe) == "curl" and any(cache in a for a in rest)
        if is_brew or is_download:
            hits.append(f"{pid} {' '.join([exe, *rest])[:120]}")
    return hits


# --------------------------------------------------------------------------- #
# Third-party tap fixture
# --------------------------------------------------------------------------- #


def taps_dir(prefix: Path | None = None) -> Path:
    base = prefix or Path(BREW).parent.parent
    return base / "Library/Taps"


def tap_fixture_dir(prefix: Path | None = None) -> Path:
    user, repo = TAP_FIXTURE.split("/")
    return taps_dir(prefix) / user / f"homebrew-{repo}"


def install_tap_fixture() -> bool:
    """Write the fixture tap into the ACTIVE brew's prefix and confirm brew can resolve both casks.
    Returns False (with a warning) if brew can't see them, so the phase skips rather than reporting
    a bogus failure."""
    casks = tap_fixture_dir() / "Casks"
    try:
        casks.mkdir(parents=True, exist_ok=True)
        (casks / f"{TAP_UNIQUE_CASK}.rb").write_text(_TAP_CASK_TEMPLATE.format(
            token=TAP_UNIQUE_CASK, version="1.0.0",
            name="Applite Harness Cask", app="AppliteHarnessCask"))
        (casks / f"{TAP_COLLIDING_CASK}.rb").write_text(_TAP_CASK_TEMPLATE.format(
            token=TAP_COLLIDING_CASK, version="0.0.0-harness",
            name=f"Applite Harness {TAP_COLLIDING_CASK.title()}",
            app=f"AppliteHarness{TAP_COLLIDING_CASK.title()}"))
    except OSError as e:
        warn(f"could not write the tap fixture: {e}")
        return False
    info(f"tap fixture written to {tap_fixture_dir()}")
    for token in (TAP_UNIQUE_CASK, TAP_COLLIDING_CASK):
        if brew_json(f"{TAP_FIXTURE}/{token}") is None:
            warn(f"brew can't resolve {TAP_FIXTURE}/{token} — skipping the tap phase")
            return False
    return True


def remove_tap_fixture() -> None:
    """Remove the fixture from BOTH prefixes — reset/teardown must not leave a fake tap behind."""
    for prefix in (APPLITE_SUPPORT / "Homebrew", OPT_PREFIX):
        repo_dir = tap_fixture_dir(prefix)
        if not repo_dir.exists():
            continue
        _rm(repo_dir)
        user_dir = repo_dir.parent
        try:  # drop the now-empty <user> dir, but never a shared one
            if user_dir.is_dir() and not any(user_dir.iterdir()):
                user_dir.rmdir()
        except OSError:
            pass


# --------------------------------------------------------------------------- #
# fake_outdated
# --------------------------------------------------------------------------- #


def fake_outdated(token: str, fake: str = "0.0.1") -> bool:
    """Rename the installed version dirs down to `fake` so `brew outdated` reports
    the cask. Requires auto_updates:false (else non-greedy outdated hides it)."""
    cdir = caskroom_dir() / token
    if not cdir.is_dir():
        bad(f"fake_outdated: {token} not in Caskroom ({cdir})")
        return False
    versions = [p.name for p in cdir.iterdir() if p.name != ".metadata"]
    if not versions:
        bad(f"fake_outdated: no version dir under {cdir}")
        return False
    real = versions[0]
    if real == fake:
        return True
    try:
        shutil.move(str(cdir / real), str(cdir / fake))
        meta = cdir / ".metadata" / real
        if meta.is_dir():
            shutil.move(str(meta), str(cdir / ".metadata" / fake))
        info(f"faked {token} {real} → {fake}")
        return True
    except OSError as e:
        bad(f"fake_outdated failed: {e}")
        return False


# --------------------------------------------------------------------------- #
# Interaction
# --------------------------------------------------------------------------- #


def step(num: str, title: str) -> None:
    heading(f"Phase {num}: {title}")


def do_in_app(instruction: str) -> None:
    print(_c("1;36", "  → " + instruction))
    try:
        input(_c("2", "    (press Enter when done) "))
    except (EOFError, KeyboardInterrupt):
        raise SystemExit("\nAborted.")


def confirm(question: str) -> bool:
    try:
        ans = input(_c("1;36", "  ? " + question + " [y/N] ")).strip().lower()
    except (EOFError, KeyboardInterrupt):
        raise SystemExit("\nAborted.")
    passed = ans in ("y", "yes")
    RESULTS.add(passed, "VISUAL: " + question)
    return passed


def check(desc: str, fn) -> bool:
    """Run a verifier; record PASS/FAIL from its truthy return (exceptions = FAIL)."""
    try:
        passed = bool(fn())
    except Exception as e:  # noqa: BLE001 - a failing check must not abort the run
        passed = False
        desc = f"{desc} (error: {e})"
    RESULTS.add(passed, desc)
    return passed


def ask_continue() -> None:
    try:
        input(_c("2", "  (Enter to continue) "))
    except (EOFError, KeyboardInterrupt):
        raise SystemExit("\nAborted.")


# --------------------------------------------------------------------------- #
# Prerequisite provisioning (hide/unhide)
# --------------------------------------------------------------------------- #


def _hidden(path: Path) -> Path:
    return path.with_name(path.name + HIDDEN_SUFFIX)


def applite_running() -> bool:
    return run(["pgrep", "-x", "Applite"]).returncode == 0


def require_applite_quit() -> None:
    if applite_running():
        warn("Applite is running.")
        do_in_app("Quit Applite completely (⌘Q), then continue")
    if applite_running():
        raise SystemExit("Applite is still running — quit it and re-run.")


def clt_free() -> bool:
    """True if the toolchain reads as 'not installed' WITHOUT invoking a stub."""
    cp = run(["xcode-select", "-p"])
    path = cp.stdout.strip()
    clt_absent = cp.returncode != 0 or not path or not Path(path).exists()
    return clt_absent and not OPT_BREW.exists()


def prereqs_live() -> bool:
    cp = run(["xcode-select", "-p"])
    path = cp.stdout.strip()
    return bool(path) and Path(path).exists() and OPT_BREW.exists()


def ensure_provisioned() -> None:
    """Ensure brew + CLT exist somewhere (live or hidden); install if wholly absent."""
    # CLT
    if not CLT_PATH.exists() and not _hidden(CLT_PATH).exists():
        warn("Command Line Tools not found.")
        info("Triggering the CLT installer (a system dialog will appear).")
        run(["xcode-select", "--install"])
        do_in_app("Finish the Command Line Tools installation, then continue")
        if not CLT_PATH.exists():
            raise SystemExit("CLT still not present at " + str(CLT_PATH))
    # Homebrew
    if not OPT_PREFIX.exists() and not _hidden(OPT_PREFIX).exists():
        # If CLT is currently hidden, unhide so the installer's git works.
        restored = False
        if _hidden(CLT_PATH).exists() and not CLT_PATH.exists():
            unhide_prereqs(); restored = True
        warn("Homebrew not found at /opt/homebrew — installing (one-time, ~a few min).")
        installer = ('/bin/bash -c "$(curl -fsSL '
                     'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"')
        run(["/bin/bash", "-c", installer], capture=False, env={"NONINTERACTIVE": "1"})
        if not OPT_BREW.exists():
            raise SystemExit("Homebrew install did not produce " + str(OPT_BREW))
        if restored:
            info("(re-hiding CLT to restore the fresh baseline)")
    ok("Prerequisites present (installed or hidden).")


def hide_prereqs() -> None:
    require_applite_quit()
    for path in (OPT_PREFIX, CLT_PATH):
        hidden = _hidden(path)
        if path.exists() and not hidden.exists():
            info(f"hiding {path}")
            if not sudo(["mv", str(path), str(hidden)]):
                raise SystemExit("Failed to hide " + str(path))
        elif hidden.exists():
            info(f"{path} already hidden")
    sudo(["xcode-select", "--reset"])
    if not clt_free():
        warn("Machine does not read as CLT-free — a full Xcode may be active. "
             "See README (hide Xcode / point xcode-select away).")


def unhide_prereqs() -> None:
    require_applite_quit()
    for path in (OPT_PREFIX, CLT_PATH):
        hidden = _hidden(path)
        if hidden.exists() and not path.exists():
            info(f"restoring {path}")
            if not sudo(["mv", str(hidden), str(path)]):
                raise SystemExit("Failed to restore " + str(path))
    sudo(["xcode-select", "--reset"])


# --------------------------------------------------------------------------- #
# reset / teardown
# --------------------------------------------------------------------------- #

TEST_CASKS = [DMG_CASK, PKG_CASK, ZAP_CASK, UPDATE_CASK, WARN_CASK, CANCEL_CASK, FAIL_CASK,
              *BULK_INSTALL_CASKS, *BULK_STOP_CASKS]


def _uninstall_all_casks(brew_exe: Path) -> None:
    """`brew uninstall --zap --force` every installed cask on this brew — removes the
    .app, pkg-installed files, and zap paths (prefs/caches/launch agents/fonts) via
    brew's own logic. Best-effort. Call with CLT live so the trash step doesn't pop
    the dialog. No-op if the brew executable isn't present (e.g. hidden)."""
    if not brew_exe.exists():
        return
    no_update = {"HOMEBREW_NO_AUTO_UPDATE": "1"}
    cp = run([str(brew_exe), "list", "--cask", "--full-name"], env=no_update)
    tokens = cp.stdout.split() if cp.returncode == 0 else []
    if not tokens:
        return
    info(f"uninstalling {len(tokens)} cask(s) from {brew_exe.parent.parent}: "
         + " ".join(tokens))
    for tok in tokens:
        run([str(brew_exe), "uninstall", "--cask", "--zap", "--force", tok],
            env=no_update, capture=False)


# Paths we refuse to delete outright — a cask zap/delete directive should never
# resolve to one of these, but guard anyway (defense against a bad/broad stanza).
_GUARDED = {
    Path("/"), Path("/Applications"), Path("/Library"), Path("/System"), Path("/usr"),
    Path("/bin"), Path("/opt"), Path("/opt/homebrew"),
    Path.home(), Path.home() / "Library", Path.home() / "Applications",
    Path.home() / "Documents", Path.home() / "Desktop", Path.home() / "Downloads",
}


def _safe_to_delete(p: Path) -> bool:
    return Path(os.path.abspath(os.path.expanduser(str(p)))) not in _GUARDED


def _rm(p: Path) -> None:
    if not (p.exists() or p.is_symlink()):
        return
    if not _safe_to_delete(p):
        warn(f"refusing to delete guarded path: {p}")
        return
    info(f"removing {p}")
    if p.is_dir() and not p.is_symlink():
        shutil.rmtree(p, ignore_errors=True)
    else:
        try:
            p.unlink()
        except OSError:
            pass


def _purge_known_casks() -> None:
    """Remove the known test casks BY NAME, from the catalog — independent of brew's
    install receipts. This is the workhorse: a clean annex reinstall (phase 20) unlinks
    every previously-installed app, so `brew uninstall` can no longer see them; resolving
    each cask's .app bundles + uninstall/zap delete paths + pkg receipts from metadata
    removes them regardless. Best-effort."""
    for token in dict.fromkeys(TEST_CASKS):  # dedupe, keep order
        cask = _cask_json_any(token)
        if not cask:
            warn(f"could not resolve '{token}' metadata — skipping its name-based purge")
            continue
        for name in app_names(cask):
            for base in ("/Applications", str(Path.home() / "Applications"), str(appdir())):
                _rm(Path(base) / name)
        # Font casks install .ttf/.otf into ~/Library/Fonts; brew's own uninstall handles them,
        # but a wiped/reinstalled annex orphans them. Remove them here so the machine returns to a
        # truly clean state and `cask_absent` is accurate (Applite force-installs anyway, so an
        # orphan wouldn't error, but leaving font files around is untidy).
        for name in font_names(cask):
            _rm(Path.home() / "Library/Fonts" / name)
        for raw in removable_paths(cask):
            for path in _expand(raw):
                _rm(path)
        for pid in pkgutil_ids(cask):
            for real in run(["pkgutil", f"--pkgs={pid}"]).stdout.split():
                sudo(["pkgutil", "--forget", real])


def _wipe_applite_data() -> None:
    run(["defaults", "delete", BUNDLE_ID])
    for path in _wipe_paths():
        if path.exists():
            info(f"rm {path}")
            shutil.rmtree(path, ignore_errors=True)
    for pattern in _wipe_globs():
        for match in glob.glob(pattern):
            info(f"rm {match}")
            try:
                os.remove(match)
            except OSError:
                pass


def cmd_reset(args) -> int:
    heading("RESET → fresh first-run state")
    warn("This UNINSTALLS every installed cask (annex + /opt), deletes Applite's data,")
    warn("and HIDES /opt/homebrew + CLT. Intended for a throwaway test VM.")
    if input("Type 'reset' to continue: ").strip() != "reset":
        raise SystemExit("Cancelled.")
    require_applite_quit()
    ensure_provisioned()
    if not args.keep_apps:
        # Snapshots aren't available on Apple-Silicon UTM VMs, so this sweep IS the fresh
        # state. Unhide first so CLT is live (trash step won't pop the dialog); re-hide below.
        unhide_prereqs()
        # 1) brew uninstall whatever is still LINKED — full brew logic (launchctl, scripts…).
        _uninstall_all_casks(ANNEX_BREW)
        _uninstall_all_casks(OPT_BREW)
        # 2) name-based purge of the known casks — catches everything the annex reinstall
        #    (phase 20) unlinked, which brew can no longer see.
        _purge_known_casks()
    remove_tap_fixture()
    hide_prereqs()
    _wipe_applite_data()
    RESULTS.add(clt_free(), "machine reads CLT-free with no system brew")
    ok("Reset complete. Launch Applite to begin Round A.")
    return RESULTS.summary()


def cmd_teardown(args) -> int:
    heading("TEARDOWN")
    if applite_running():
        raise SystemExit("Quit Applite first (verify self-uninstall removed it).")
    RESULTS.add(not _applite_app_present(), "Applite.app is gone (self-uninstall worked)")
    if args.full:
        warn("--full: uninstalling all casks, then deleting Homebrew + CLT entirely.")
        _uninstall_all_casks(OPT_BREW)  # linked casks: full brew removal before nuking brew
        _purge_known_casks()            # name-based: unlinked/orphaned apps + pkg/zap
        remove_tap_fixture()
        _wipe_applite_data()
        for path in (OPT_PREFIX, _hidden(OPT_PREFIX), CLT_PATH, _hidden(CLT_PATH)):
            if path.exists():
                sudo(["rm", "-rf", str(path)])
        shutil.rmtree(Path.home() / "Library/Caches/Homebrew", ignore_errors=True)
        shutil.rmtree(Path.home() / "Library/Logs/Homebrew", ignore_errors=True)
        ok("Full teardown complete — pristine image.")
    else:
        # Uninstall everything (CLT live so trash works), then re-hide the prereqs.
        unhide_prereqs()
        _uninstall_all_casks(OPT_BREW)
        _uninstall_all_casks(ANNEX_BREW)
        _purge_known_casks()
        remove_tap_fixture()
        _wipe_applite_data()
        hide_prereqs()
        ok("Teardown complete — brew + CLT kept hidden for the next run.")
    return RESULTS.summary()


def _applite_app_present() -> bool:
    for base in ("/Applications", str(Path.home() / "Applications")):
        if (Path(base) / "Applite.app").exists():
            return True
    return False


def _applite_leftovers() -> list[str]:
    """Applite support/cache/pref paths that self-uninstall SHOULD have removed — mirrors
    the rm list in UninstallSelf.swift. Excludes ~/Library/Caches/Homebrew, which the app
    only removes when the operator opts in. Returns any that still exist."""
    home = Path.home()
    fixed = [
        APPLITE_SUPPORT,  # ~/Library/Application Support/Applite (includes the annex)
        home / "Library/Application Support" / BUNDLE_ID,
        home / "Library/Containers" / BUNDLE_ID,
        home / "Library/Caches/Applite",
        home / "Library/Caches" / BUNDLE_ID,
        home / "Library/Applite",
        home / "Library/Saved Application State" / f"{BUNDLE_ID}.savedState",
        home / "Library/WebKit" / BUNDLE_ID,
        home / "Library/HTTPStorages" / BUNDLE_ID,
    ]
    left = [str(p) for p in fixed if p.exists()]
    left += glob.glob(str(home / f"Library/Preferences/*{BUNDLE_ID}*.plist"))
    left += glob.glob(str(home / f"Library/SyncedPreferences/{BUNDLE_ID}*.plist"))
    return left


def cmd_provision(_args) -> int:
    heading("PROVISION (one-time per VM)")
    ensure_provisioned()
    hide_prereqs()
    ok("Provisioned. Snapshot the VM now for a cheap, repeatable baseline.")
    return 0


# --------------------------------------------------------------------------- #
# preflight
# --------------------------------------------------------------------------- #


def cmd_preflight(_args) -> int:
    heading("PREFLIGHT — validating test casks")
    if not brew_healthy():
        bad(f"brew not healthy at {BREW}. Launch Applite (annex) or run --round external.")
        return 1

    roles = [
        (DMG_CASK, "app", None),
        (PKG_CASK, "pkg", None),
        (ZAP_CASK, "app", "zap"),
        (UPDATE_CASK, None, "no_auto_update"),
        (WARN_CASK, None, "warn"),
        (CANCEL_CASK, "app", None),
        (FAIL_CASK, "pkg", None),
        *[(t, None, None) for t in BULK_INSTALL_CASKS if t not in BULK_UPDATE_CASKS],
        *[(t, None, "no_auto_update") for t in BULK_UPDATE_CASKS],
        *[(t, "app", None) for t in BULK_STOP_CASKS],
    ]
    print(f"  {'token':22} {'kind':6} {'auto_upd':9} {'version':12} role")
    all_ok = True
    for token, want_kind, extra in roles:
        cask = brew_json(token)
        if not cask:
            RESULTS.add(False, f"{token}: not found in catalog — swap this var")
            all_ok = False
            continue
        kind = artifact_kind(cask)
        auto = cask.get("auto_updates")
        ver = cask.get("version")
        print(f"  {token:22} {kind:6} {str(auto):9} {str(ver):12} {extra or want_kind}")

        role_ok = True
        if want_kind and kind != want_kind:
            role_ok = False
            warn(f"  {token}: expected {want_kind} artifact, got {kind}")
        if extra == "zap" and not zap_paths(cask):
            role_ok = False
            warn(f"  {token}: no zap paths — pick a cask with a zap stanza")
        if extra == "no_auto_update":
            if auto:
                role_ok = False
                warn(f"  {token}: auto_updates is truthy — non-greedy outdated will hide it")
            if not ver or ver == "latest":
                role_ok = False
                warn(f"  {token}: version must be concrete (not :latest)")
        if extra == "warn" and not (cask.get("caveats") or cask.get("deprecated")
                                    or cask.get("disabled")):
            role_ok = False
            warn(f"  {token}: no caveats/deprecation — the warning dialog won't show")
        RESULTS.add(role_ok, f"{token} fits its role")
        all_ok = all_ok and role_ok

    return RESULTS.summary() if all_ok else 1


# --------------------------------------------------------------------------- #
# Round A phases (annex, CLT-free)
# --------------------------------------------------------------------------- #


def phase_a0(_state) -> None:
    step("0", "preflight + environment")
    check("not running as root", lambda: os.geteuid() != 0)
    check("annex brew executable exists", lambda: ANNEX_BREW.exists())
    cmd_preflight(None)


def phase_a1(_state) -> None:
    step("1", "fresh bootstrap (first run)")
    # No confirms: reaching this point means Applite already installed the annex and
    # showed the catalog (you couldn't get here otherwise). The auto-checks below prove
    # brew is actually usable.
    info("Applite has installed the annex and shown the catalog + 'Get Started'.")
    check("brew_healthy (annex, no LoadError)", brew_healthy)
    check("annex brew executable exists", lambda: ANNEX_BREW.exists())


def phase_a2(state) -> None:
    step("2", f"install DMG cask ({DMG_CASK})")
    do_in_app(f"In Applite, search for and install '{DMG_CASK}'")
    check(f"{DMG_CASK} in brew list", lambda: cask_installed(DMG_CASK))
    cask = brew_json(DMG_CASK) or {}
    for name in app_names(cask):
        check(f"{name} present on disk", lambda n=name: app_present(n))
    confirm("Did the green tick clear and the app show as Installed?")


def phase_a3(_state) -> None:
    step("3", f"install PKG cask ({PKG_CASK})")
    do_in_app(f"Install '{PKG_CASK}' (a .pkg installer). Enter your password if asked")
    check(f"{PKG_CASK} in brew list", lambda: cask_installed(PKG_CASK))
    cask = brew_json(PKG_CASK) or {}
    for name in app_names(cask):
        check(f"{name} present (appdir {appdir()})", lambda n=name: app_present(n))
    confirm("Did the password prompt appear and the install finish?")


def phase_a4(_state) -> None:
    step("4", f"warning-cask dialog ({WARN_CASK}, deprecated)")
    do_in_app(f"Start installing '{WARN_CASK}' — a warning dialog (deprecated) should appear")
    confirm("Did the warning dialog appear?")
    do_in_app("Choose 'Download Anyway' and let it finish")
    # If this FAILS with a deprecation error, brew is treating deprecation as a hard error
    # (it must stay a warning — Applite installs deprecated casks after the download warning).
    check(f"{WARN_CASK} installed (deprecation stays a warning, not a hard error)",
          lambda: cask_installed(WARN_CASK))


def phase_a6(_state) -> None:
    step("5", f"cancel mid-download ({CANCEL_CASK})")
    info(f"Clearing {CANCEL_CASK}'s cached download so it re-downloads (a cached "
         "download finishes instantly — nothing to cancel)…")
    clear_cask_cache(CANCEL_CASK)
    do_in_app(f"Install '{CANCEL_CASK}' (large) and hit the STOP button while it downloads")
    check(f"{CANCEL_CASK} NOT installed after cancel", lambda: cask_absent(CANCEL_CASK))
    confirm("Did the progress reset to idle (no stuck spinner)?")


def phase_a7(state) -> None:
    step("6", f"fake-outdated + update ({UPDATE_CASK})")
    do_in_app(f"Install '{UPDATE_CASK}' if not already installed")
    if not check(f"{UPDATE_CASK} installed", lambda: cask_installed(UPDATE_CASK)):
        RESULTS.skip("update phase (cask not installed)")
        return
    check("faked an older installed version", lambda: fake_outdated(UPDATE_CASK))
    check(f"brew reports {UPDATE_CASK} outdated", lambda: outdated_lists(UPDATE_CASK))
    do_in_app("In Applite: refresh Updates (⌘R or Updates tab), then Update the app")
    check(f"{UPDATE_CASK} no longer outdated", lambda: not outdated_lists(UPDATE_CASK))
    check(f"{UPDATE_CASK} version restored (not 0.0.1)",
          lambda: installed_version(UPDATE_CASK) not in (None, "0.0.1"))


def phase_a8(_state) -> None:
    step("7", f"uninstall plain ({DMG_CASK})")
    do_in_app(f"Uninstall '{DMG_CASK}' (plain, no zap)")
    check(f"{DMG_CASK} absent from brew list", lambda: cask_absent(DMG_CASK))
    cask = brew_json(DMG_CASK) or {}
    for name in app_names(cask):
        check(f"{name} removed from disk", lambda n=name: not app_present(n))


def phase_a9(state) -> None:
    step("8", f"uninstall + zap ({ZAP_CASK})")
    do_in_app(f"Install '{ZAP_CASK}' if needed — but do NOT uninstall it yet")
    cask = brew_json(ZAP_CASK) or {}
    # Seed app-data at a real zap path so zap has something to remove (the app was never
    # launched, so its prefs/caches don't exist — otherwise this would test nothing).
    seeded = seed_zap_file(zap_paths(cask))
    if seeded:
        info(f"seeded app-data at a zap path: {seeded}")
    else:
        warn("no concrete zap path to seed — can't distinguish zap from plain uninstall")
    do_in_app(f"Now Uninstall '{ZAP_CASK}' with 'delete app data (--zap)'")
    check(f"{ZAP_CASK} absent from brew list", lambda: cask_absent(ZAP_CASK))
    for name in app_names(cask):
        check(f"{name} removed from disk", lambda n=name: not app_present(n))
    if seeded:
        check("zap removed the seeded app-data file", lambda: not seeded.exists())
    else:
        RESULTS.skip("zap seed check (no concrete zap path)")


def phase_a10(_state) -> None:
    step("19", "Refresh Homebrew Components (annex overlay)")

    # The annex refresh now also prunes the download cache (brew cleanup --prune=all): annex
    # users install only casks and never reuse a cached download, so the refresh reclaims it.
    # Seed the cache first so the prune has an artifact to remove, then verify it's emptied.
    seedable = seed_download_cache(DMG_CASK)
    before = cache_download_count()
    info(f"annex download cache before refresh: {before} file(s)")

    do_in_app("Settings → Manage Homebrew → Refresh Homebrew Components; wait for it")
    check("brew still healthy after overlay (no LoadError)", brew_healthy)
    check(f"{UPDATE_CASK} still installed (Caskroom survived)",
          lambda: cask_installed(UPDATE_CASK))

    after = cache_download_count()
    info(f"annex download cache after refresh: {after} file(s)")
    if seedable or before > 0:
        check("refresh pruned the download cache to empty (brew cleanup --prune=all)",
              lambda: after == 0)
    else:
        RESULTS.skip("cache-prune check (cache was empty and couldn't be seeded — offline?)")
    confirm("Did the refresh finish and re-enable the UI?")


def phase_a11(_state) -> None:
    step("20", "Reinstall Homebrew (clean annex)")
    do_in_app("Settings → Manage Homebrew → Reinstall Homebrew; confirm and wait")
    check("annex brew healthy after reinstall", brew_healthy)
    check("brew list is empty (apps unlinked)", lambda: installed_tokens() == [])
    # P3-2: reinstall now downloads+verifies into Homebrew.staging, then swaps via Homebrew.old,
    # removing both on success (so a failed download can't destroy the working install). A clean
    # reinstall must leave neither temp dir behind.
    check("no leftover staging/backup dirs after reinstall",
          lambda: not (APPLITE_SUPPORT / "Homebrew.staging").exists()
              and not (APPLITE_SUPPORT / "Homebrew.old").exists())
    confirm("Are the app bundles still on disk (unlinked, not deleted)?")


def phase_a12(_state) -> None:
    step("9", "catalog refresh + browse (read-only UI smoke test)")
    info("Purpose: the read-only catalog/browse surfaces render and return data — "
         "catalog re-sync, FTS search, sort/filter, categories, taps.")
    do_in_app("Press ⌘R (Refresh App Catalog); wait for it to finish")
    confirm("Did the catalog refresh finish with no error alert?")
    do_in_app("Type a query in the search field")
    confirm("Did search return matching results?")
    do_in_app("Open a category from the sidebar")
    confirm("Did the Category view render its apps?")
    # Sidebar/search interplay: typing stashes the selection, a sidebar tap interrupts the search,
    # and Esc restores what you were looking at. Cheap to check, easy to regress.
    do_in_app("With the search still active, click a sidebar item, then press Esc in the field")
    confirm("Did the sidebar tap clear the search, and Esc restore the previous selection?")


def phase_a13(_state) -> None:
    step("10", "settings: missing-brew error, recovery UI + per-window alerts")

    # 10a — a selected NON-annex brew that's missing must surface the setup overlay, and must NOT
    # silently switch to / reinstall the annex (which would orphan the user's own installed apps).
    # A bogus *custom* path is a non-annex selection, so it hits exactly this branch
    # (BrewPaths.selectedBrewOption != .annex).
    info("A bogus custom (non-annex) brew path must show the setup overlay — Applite must NOT "
         "silently switch to or reinstall the annex.")
    do_in_app("Settings → Brew Executable Path → Custom → a bogus path (e.g. /nope/brew)")
    # P3-7: the invalid-path message in Settings now carries its own 'Try Again', because the only
    # other way out was a menu item a non-technical user never finds. It must NOT be disabled while
    # the path is invalid — that disabled the fix on exactly the fault it fixes.
    confirm("Did Settings show 'Currently selected brew path is invalid' in red, with an ENABLED "
            "'Try Again' button next to it?")
    confirm("Did the bottom 'Refresh the app catalog to apply your changes' banner appear, with an "
            "ENABLED 'Refresh Catalog' button?")
    # F5/P3-5 + Finding 5: Settings owns its OWN alert surface. An error raised from here used to be
    # queued against the main window — presenting behind Settings, or against nothing when the main
    # window is closed. It must appear over Settings itself.
    do_in_app("Press 'Try Again' in Settings (leave the bogus path selected)")
    confirm("Did the failure alert appear over the SETTINGS window (not behind it, not lost)?")
    do_in_app("Dismiss the alert, bring the MAIN window forward, and press ⌘R there")
    opt = run(["defaults", "read", BUNDLE_ID, "brewPathOption"]).stdout.strip()
    info(f"brewPathOption now = '{opt}'  (should stay 3 = custom, NOT 0 = annex; "
         "may lag until Applite flushes prefs)")
    confirm("Did the setup overlay appear in the MAIN window, naming the bogus path (/nope/brew)?")
    confirm("Did Applite NOT switch to the annex (no catalog reappearing, no install spinner)?")
    # The same overlay must be reachable from an install attempt, not only from ⌘R.
    do_in_app("Dismiss/ignore the overlay if possible and try to Install any app")
    confirm("Did the install attempt also land on the setup overlay (not a silent no-op)?")
    do_in_app("Recover: Settings → Brew Executable Path → 'Applite's installation', "
              "then press 'Refresh Catalog' in the Settings banner")
    check("annex brew still healthy (never touched by the bad selection)", brew_healthy)
    confirm("Did the red invalid-path message clear AND the refresh banner disappear "
            "(it must only clear on a refresh that actually succeeded)?")
    confirm("Did the main window's overlay dismiss and the catalog reload?")

    # 10b — the genuinely-broken failure UI. Brew must be UNRECOVERABLE for it to show,
    # so the annex is hidden AND the network taken offline (otherwise Applite just
    # reinstalls the annex and recovers). Both are restored afterward.
    info("Now the failure path: brew must be unrecoverable, so we hide the annex and you "
         "take the VM offline (else Applite reinstalls the annex and recovers).")
    do_in_app("Turn OFF the VM's network (Wi-Fi / Ethernet)")
    annex = APPLITE_SUPPORT / "Homebrew"
    stash = annex.with_name("Homebrew.brokentest")
    moved = False
    try:
        if annex.exists():
            shutil.move(str(annex), str(stash))
            moved = True
            info("annex temporarily hidden")
        do_in_app("In Applite press ⌘R (annex gone + no network → brew is unrecoverable)")
        # E1: `bootstrap.phase` is now the single owner of "is brew usable" (the parallel
        # hasBrokenInstall flag and BrokenInstallView were deleted), so a broken brew must produce
        # exactly ONE surface — no second overlay and no alert stacked on top of it.
        confirm("Did EXACTLY ONE error surface appear — the setup-failed overlay with "
                "message + Retry + 'use your own Homebrew' — and NOTHING stacked with it "
                "(no duplicate alert, no second overlay)?")
    finally:
        if moved and stash.exists():
            # Applite's failed reinstall attempt recreates an empty `Homebrew` dir while
            # the real one is stashed. Remove it first, else shutil.move nests the real
            # annex INSIDE it — leaving an invalid annex, so Applite reinstalls clean on
            # Retry and wipes every cask link (empty export, later "still installed" fails).
            if annex.exists():
                shutil.rmtree(annex, ignore_errors=True)
            shutil.move(str(stash), str(annex))
            info("annex restored (removed any empty dir from the failed reinstall)")
    do_in_app("Turn the network back ON, then press Retry in Applite")
    confirm("Did Retry recover with your installed apps intact (catalog loads again)?")


def phase_a14(_state) -> None:
    step("11", "export (selectable Brewfile) + BULK install (one batch process)")
    # Migration v2: Export and Import each open a CHECKLIST SHEET first (pick which apps).
    # Export then writes a Brewfile (`cask "<token>"` lines, plus `tap "…"` for non-default taps)
    # via the save panel, default name Applite-export-<date>.txt. Import resolves tokens against
    # the DB (installs casks never browsed) and force-installs, so an already-present cask
    # reinstalls instead of failing the batch. Import runs installAll → a single
    # `brew install --cask <all>` process (the original dropped-casks repro plus the batch UI).
    desktop = Path.home() / "Desktop"
    # Clear stale exports so the glob below matches only this run's file.
    for old in glob.glob(str(desktop / "Applite-export-*.txt")):
        try:
            os.remove(old)
        except OSError:
            pass

    do_in_app("App Migration → Export Apps to File (a selection sheet should open)")
    confirm("Did a selection sheet list your installed apps, each PRE-CHECKED and showing an "
            "icon, with Applite itself NOT in the list (excluded — you're already running it)?")
    confirm("Do 'Select All' / 'Deselect All' flip every checkbox and the \"N selected\" count "
            "update live?")
    do_in_app("Make sure all are checked, press Export, and SAVE to the Desktop "
              "(accept the default name Applite-export-<date>.txt)")

    exports = sorted(glob.glob(str(desktop / "Applite-export-*.txt")))
    check("a dated export appeared on the Desktop (Applite-export-*.txt)",
          lambda: bool(exports))
    if exports:
        text = Path(exports[-1]).read_text()
        check("export is Brewfile syntax (has cask \"…\" lines)",
              lambda t=text: 'cask "' in t)

    # Import a controlled set. A plain-text token list also exercises the legacy-format import
    # path (readCaskFile falls back to newline-separated tokens when there's no `cask "` line).
    import_path = desktop / "applite_import.txt"
    import_path.write_text("\n".join(BULK_INSTALL_CASKS) + "\n")
    info(f"import file: {', '.join(BULK_INSTALL_CASKS)}")

    do_in_app(f"App Migration → Import → pick {import_path}")
    confirm(f"Did the import selection sheet show ALL {len(BULK_INSTALL_CASKS)} apps on the "
            "FIRST attempt? (regression: it used to list 0 the first time.)")
    do_in_app("Leave every app checked, press Install")
    # Import now navigates straight to Active Tasks (P3-4): the old migration screen faked a green
    # "Installing N apps…" before anything ran and couldn't surface batch failures. It now sends you
    # to where each app's real progress and per-app failures actually show.
    confirm("Did Applite switch to the Active Tasks tab automatically after pressing Install?")
    do_in_app("Watch the batch run to completion on the Active Tasks tab")
    confirm(f"Did each of the {len(BULK_INSTALL_CASKS)} cards show its OWN download ring "
            "(not just a spinner) during the download phase?")
    confirm("Did the Active Tasks header count up (\"Installing X of N…\")?")
    confirm("Did you get exactly ONE summary notification at the end (not one per app)?")
    for tok in BULK_INSTALL_CASKS:
        check(f"{tok} installed via bulk import", lambda t=tok: cask_installed(t))


def phase_bulk_update(state) -> None:
    step("12", "BULK update (Update All, one batch process)")
    # Reuse the fonts installed by the bulk-install phase; fake them outdated, then Update All.
    targets = [t for t in BULK_UPDATE_CASKS if cask_installed(t)]
    if len(targets) < 2:
        do_in_app(f"Install {BULK_UPDATE_CASKS} first if missing (App Migration → Import → "
                  "select all → Install)")
        targets = [t for t in BULK_UPDATE_CASKS if cask_installed(t)]
    if len(targets) < 2:
        RESULTS.skip("bulk update (need ≥2 installed update targets)")
        return

    for tok in targets:
        check(f"faked {tok} outdated", lambda t=tok: fake_outdated(t))
    do_in_app("Open the Updates tab (⌘R there if needed) — all faked casks should be listed")
    check("brew reports all targets outdated",
          lambda: all(outdated_lists(t) for t in targets))
    do_in_app("Press 'Update All'")
    confirm("Did 'Update All' become disabled + spin while the batch ran?")
    # Regression guard: the disabled/spinning state is driven by the observable batch state, so it
    # must survive leaving and returning to the tab (local @State alone was reset on a view switch).
    do_in_app("While it's still updating, switch to another sidebar tab and back to Updates")
    confirm("Was 'Update All' still disabled + spinning after returning to the tab?")
    confirm("Did the Active Tasks header show \"Updating X of N…\"?")
    for tok in targets:
        check(f"{tok} no longer outdated", lambda t=tok: not outdated_lists(t))
        check(f"{tok} version restored (not 0.0.1)",
              lambda t=tok: installed_version(t) not in (None, "0.0.1"))
    # After all updates succeed no casks remain outdated, so the list empties and the 'Update All'
    # button (shown only when ≥2 apps need updating) disappears — it does not "re-enable".
    confirm("Did the Update list empty out and 'Update All' disappear once the batch finished?")


def phase_batch_stop(state) -> None:
    step("13", "batch STOP + per-card redirect")
    # Big downloads so the batch is still running when you go to stop it. They must NOT be
    # installed (else import skips them → nothing downloads → nothing to stop). Clear caches so
    # they re-download. (Uninstall via Applite, not the harness — a CLT-free harness uninstall of
    # an app cask would hit Swift-trash and pop the CLT dialog.)
    for tok in BULK_STOP_CASKS:
        clear_cask_cache(tok)
    if any(cask_installed(t) for t in BULK_STOP_CASKS):
        do_in_app(f"In Applite, uninstall any of {BULK_STOP_CASKS} that are installed "
                  "(they must re-download for this test)")
    stop_path = Path.home() / "Desktop/applite_bulkstop.txt"
    stop_path.write_text("\n".join(BULK_STOP_CASKS) + "\n")
    do_in_app(f"App Migration → Import → pick {stop_path} ({', '.join(BULK_STOP_CASKS)}); in the "
              "selection sheet leave both checked and press Install — big downloads, keep it running")
    # Import lands on Active Tasks automatically now (P3-4), so the cards are already in front of you.
    confirm("Did Applite switch to the Active Tasks tab automatically after pressing Install?")

    do_in_app("On the Active Tasks tab, while it downloads, click the STOP button on ONE app card")
    confirm("Did an alert appear (\"…is part of a bulk operation\") with a 'See Active Tasks' "
            "button — instead of silently cancelling everything?")
    do_in_app("Dismiss the alert (you're already on the Active Tasks tab)")
    do_in_app("Press the 'Stop' button in the Active Tasks header, then confirm")
    check("brew still healthy after batch stop (no orphaned process)", brew_healthy)
    confirm("Did the cards reset (no stuck spinners) after stopping?")


def phase_a15(_state) -> None:
    step("14", "launch installed app")
    do_in_app("Installed tab → Open on an installed app")
    confirm("Did the app launch?")


def phase_failed_install(_state) -> None:
    step("15", f"failed install reports in place, not in a dialog ({FAIL_CASK})")
    # The alert audit moved brew-op failures OFF alerts: a failed install now reports on the card
    # itself (a red row) and stays reachable in Active Tasks until dismissed. A dialog here is a
    # regression. Cancelling the sudo prompt is a deterministic, offline-safe way to force it —
    # FAIL_CASK is a pkg cask that always needs admin, and is used by no other phase.
    if cask_installed(FAIL_CASK):
        do_in_app(f"Uninstall '{FAIL_CASK}' first (this phase needs it NOT installed)")
    do_in_app(f"Install '{FAIL_CASK}', and press CANCEL on the password dialog when it appears")
    confirm("Did the app card show a RED failure row inline (error text on the card itself)?")
    confirm("Did NO error dialog/alert appear?")
    do_in_app("Open the Active Tasks tab")
    confirm(f"Is the failed '{FAIL_CASK}' still listed there with its error?")
    check(f"{FAIL_CASK} is genuinely not installed", lambda: cask_absent(FAIL_CASK))
    do_in_app("Dismiss the failed task from Active Tasks")
    confirm("Did dismissing clear both the Active Tasks entry and the card's red row?")
    # Retrying must reuse the one card rather than leaving two for the same cask.
    do_in_app(f"Install '{FAIL_CASK}' again, this time entering your password")
    check(f"{FAIL_CASK} installed on retry", lambda: cask_installed(FAIL_CASK))
    confirm("Did the retry produce exactly ONE card (no leftover duplicate from the failure)?")


def phase_taps(_state) -> None:
    step("16", "third-party taps + token collision (fullToken identity)")
    # Two regressions live here:
    #  · Shell stream truncation silently swallowed the tail of `brew ruby`'s output, which dropped
    #    tap casks from the catalog entirely (they were the only thing large enough to hit it).
    #  · P2-29: casks used to be keyed by the BARE token, so a tap's `rectangle` and core
    #    `rectangle` collapsed into one DB row / one view model. Identity is `fullToken` now, and
    #    `brew list --cask --full-name` is matched EXACTLY — a bare-token match let a tap cask
    #    inherit the core cask's installed state (shown in Installed/Updates, uninstall running
    #    against a cask that isn't installed).
    if not install_tap_fixture():
        RESULTS.skip("tap phase (fixture not visible to brew)")
        return
    info(f"fixture tap '{TAP_FIXTURE}' provides: {TAP_UNIQUE_CASK} (unique) and "
         f"{TAP_COLLIDING_CASK} (same bare token as the CORE cask)")

    do_in_app("Settings → App Sources → make sure 'Include Third-Party Taps' is ON, then press "
              "'Refresh Catalog' in the banner (or ⌘R in the main window)")
    do_in_app(f"Search for '{TAP_UNIQUE_CASK}'")
    confirm(f"Did '{TAP_UNIQUE_CASK}' appear, attributed to the tap '{TAP_FIXTURE}'? "
            "(if the whole tap is missing, the tap fetch was truncated — a regression)")
    do_in_app("Open the tap's entry in the sidebar")
    confirm(f"Does the sidebar list the tap '{TAP_FIXTURE}' and render its 2 apps?")

    # The collision test. The CORE cask must be installed and the TAP cask must not be.
    if not cask_installed(TAP_COLLIDING_CASK):
        do_in_app(f"Install the CORE '{TAP_COLLIDING_CASK}' (the one NOT attributed to a tap)")
    check(f"core {TAP_COLLIDING_CASK} is installed",
          lambda: cask_installed(TAP_COLLIDING_CASK))
    do_in_app(f"Search for '{TAP_COLLIDING_CASK}' — you should see TWO results "
              f"(core, and the '{TAP_FIXTURE}' one)")
    confirm("Do BOTH results show — i.e. the tap cask didn't evict the core one (or vice versa)?")
    confirm(f"Does ONLY the core '{TAP_COLLIDING_CASK}' show as Installed, while the tap's copy "
            "still offers Install?")
    do_in_app("Open the Installed tab")
    confirm(f"Does the Installed list contain exactly ONE '{TAP_COLLIDING_CASK}' (the core one)?")

    do_in_app("Settings → App Sources → turn 'Include Third-Party Taps' OFF, then 'Refresh Catalog'")
    do_in_app(f"Search for '{TAP_UNIQUE_CASK}' again")
    confirm("Is the tap cask now gone from the catalog (the toggle actually prunes)?")
    confirm(f"Is the CORE '{TAP_COLLIDING_CASK}' still present and still marked Installed "
            "(pruning taps must not touch core casks)?")
    do_in_app("Turn 'Include Third-Party Taps' back ON and refresh once more")


def phase_sparkle(_state) -> None:
    step("17", "Sparkle updater is observed, not snapshotted")
    # P3-18/P3-19: the toggles were @State copies taken in init, so they drifted whenever anything
    # else moved them; and nothing observed canCheckForUpdates, so 'Check for Updates' stayed live
    # during a check and repeat clicks stacked up. Both are now KVO-bridged into @Observable.
    do_in_app("Settings → Updates → note both toggles, then flip 'Automatically check for updates'")
    confirm("Did 'Automatically download updates' become enabled/disabled to match, immediately?")
    do_in_app("Close the Settings window, reopen it, and go back to Updates")
    confirm("Do both toggles still show the values you left them at (no snapshot drift)?")
    # Sparkle persists these in the app's own defaults domain — verify independently of the UI.
    auto = run(["defaults", "read", BUNDLE_ID, "SUEnableAutomaticChecks"]).stdout.strip()
    info(f"SUEnableAutomaticChecks = '{auto or '(unset)'}' — should match the toggle you left set")
    do_in_app("Restore the toggle to its original value, then press 'Check for Updates...'")
    confirm("Did 'Check for Updates...' go DISABLED while the check ran, then re-enable?")


def phase_quit_mid_install(_state) -> None:
    step("18", "quit mid-install leaves no brew running")
    # P3-10: quitting only sent SIGTERM, and brew/curl ignored it — the download kept going after
    # Applite was gone. Quitting now escalates to SIGKILL after a deadline.
    clear_cask_cache(CANCEL_CASK)
    if cask_installed(CANCEL_CASK):
        do_in_app(f"Uninstall '{CANCEL_CASK}' first (it must re-download for this test)")
    do_in_app(f"Install '{CANCEL_CASK}' (large) and, WHILE IT DOWNLOADS, quit Applite with ⌘Q")
    check("Applite actually quit", lambda: not applite_running())
    # Give the SIGTERM→SIGKILL escalation its deadline before snapshotting, so a process still
    # unwinding isn't reported as an orphan.
    leftovers = brew_processes()
    for _ in range(10):
        if not leftovers:
            break
        time.sleep(1)
        leftovers = brew_processes()
    if leftovers:
        for line in leftovers:
            warn("  still running: " + line)
    check("no brew/curl process left running after quit", lambda: not leftovers)
    check(f"{CANCEL_CASK} not left half-installed", lambda: cask_absent(CANCEL_CASK))
    do_in_app("Relaunch Applite (the remaining phases need it running)")
    confirm("Did Applite relaunch cleanly, with no stuck spinner on that app?")


# --------------------------------------------------------------------------- #
# Round B phases (external /opt/homebrew)
# --------------------------------------------------------------------------- #


def phase_b0(_state) -> None:
    step("B0", "unhide prereqs + update + select /opt/homebrew")
    unhide_prereqs()
    check("prereqs are live (brew + CLT restored)", prereqs_live)
    info("Running `brew update` on the restored /opt/homebrew…")
    check("brew update succeeds (real git path)",
          lambda: run([str(OPT_BREW), "update"], capture=False).returncode == 0)
    check("/opt/homebrew brew healthy", brew_healthy)
    do_in_app("In Applite: Settings → Brew Executable Path → 'Apple Silicon' "
              "(/opt/homebrew); wait for the catalog to reload")
    # E1 deleted BrokenInstallView: a healthy selected brew must show no overlay at all.
    confirm("Did Applite switch to /opt/homebrew with NO setup overlay and no error?")


def phase_b1(_state) -> None:
    step("B1", f"install DMG on external brew ({DMG_CASK})")
    do_in_app(f"Install '{DMG_CASK}'")
    check(f"{DMG_CASK} installed (external brew)", lambda: cask_installed(DMG_CASK))
    confirm("Did the tick clear and the app show Installed?")


def phase_b2(_state) -> None:
    step("B2", f"install PKG on external brew ({PKG_CASK})")
    do_in_app(f"Install '{PKG_CASK}'")
    check(f"{PKG_CASK} installed (external brew)", lambda: cask_installed(PKG_CASK))


def phase_b3(state) -> None:
    step("B3", f"fake-outdated + update on external brew ({UPDATE_CASK})")
    do_in_app(f"Install '{UPDATE_CASK}' if needed")
    if not check(f"{UPDATE_CASK} installed", lambda: cask_installed(UPDATE_CASK)):
        RESULTS.skip("external update phase (cask not installed)")
        return
    check("faked older version", lambda: fake_outdated(UPDATE_CASK))
    check(f"{UPDATE_CASK} reported outdated", lambda: outdated_lists(UPDATE_CASK))
    do_in_app("Refresh Updates, then Update the app in Applite")
    check(f"{UPDATE_CASK} no longer outdated", lambda: not outdated_lists(UPDATE_CASK))


def phase_b4(state) -> None:
    step("B4", f"uninstall + zap on external brew ({ZAP_CASK})")
    do_in_app(f"Install '{ZAP_CASK}' if needed — do NOT uninstall yet")
    cask = brew_json(ZAP_CASK) or {}
    seeded = seed_zap_file(zap_paths(cask))
    if seeded:
        info(f"seeded app-data at a zap path: {seeded}")
    do_in_app(f"Now Uninstall '{ZAP_CASK}' with --zap")
    check(f"{ZAP_CASK} absent (external brew)", lambda: cask_absent(ZAP_CASK))
    if seeded:
        check("zap removed the seeded app-data file", lambda: not seeded.exists())
    else:
        RESULTS.skip("zap seed check (no concrete zap path)")


# --------------------------------------------------------------------------- #
# Upgrade round (v1.3.1 → this release)
# --------------------------------------------------------------------------- #
#
# The single biggest untested path for a release: every existing user arrives this way, and this
# release changed the storage underneath them — a JSON cache became a GRDB database, onboarding was
# removed, and the annex moved from `Applite/homebrew` (v1.3.1) to `Applite/Homebrew`. Those two
# differ only in case, so they are the SAME directory on a default (case-insensitive) APFS volume
# and DIFFERENT directories on a case-sensitive one. Neither outcome has been exercised.
#
# Run this on its own pass, from a `reset`, BEFORE the annex round — it deliberately starts from an
# old install rather than a clean machine.

OLD_RELEASE_URL = "https://github.com/milanvarady/Applite/releases/tag/v1.3.1"
_OLD_ANNEX_DIR = APPLITE_SUPPORT / "homebrew"   # v1.3.1's lowercase spelling


def _case_sensitive_home() -> bool:
    """Whether $HOME's volume distinguishes `homebrew` from `Homebrew` — decides whether an
    upgrader's old annex is inherited or orphaned."""
    probe = APPLITE_SUPPORT.parent / ".applite-case-probe"
    try:
        probe.mkdir(exist_ok=True)
        sensitive = not (probe.parent / ".APPLITE-CASE-PROBE").exists()
        probe.rmdir()
        return sensitive
    except OSError:
        return False


def phase_u0(_state) -> None:
    step("U0", "install the OLD release (v1.3.1) and use it")
    info(f"Download v1.3.1 from: {OLD_RELEASE_URL}")
    warn("Round A's `reset` has hidden /opt/homebrew + CLT. v1.3.1 needs the Command Line Tools, "
         "so this round restores them first — an upgrader's machine has them.")
    unhide_prereqs()
    check("prereqs live for the old release", prereqs_live)
    do_in_app("Install and launch Applite v1.3.1; complete its onboarding, choosing "
              "\"Applite's installation\" (let it install its own Homebrew)")
    do_in_app(f"In v1.3.1, install '{DMG_CASK}' and let it finish")
    check("v1.3.1 created its own brew tree",
          lambda: _OLD_ANNEX_DIR.exists() or (APPLITE_SUPPORT / "Homebrew").exists())
    check(f"{DMG_CASK} installed by the old release", lambda: cask_installed(DMG_CASK))
    do_in_app("Quit Applite v1.3.1 and REPLACE it with the new build in /Applications")


def phase_u1(_state) -> None:
    step("U1", "first launch of the NEW release over the old install")
    sensitive = _case_sensitive_home()
    info(f"$HOME volume is case-{'SENSITIVE' if sensitive else 'insensitive'} → the old "
         f"`Applite/homebrew` and the new `Applite/Homebrew` are "
         f"{'DIFFERENT directories (expect a fresh annex install)' if sensitive else 'the SAME directory (the old brew is inherited)'}")
    before = run(["defaults", "read", BUNDLE_ID, "brewPathOption"]).stdout.strip()
    info(f"brewPathOption carried over from v1.3.1 = '{before or '(unset)'}'")

    do_in_app("Launch the NEW Applite")
    # No onboarding exists any more; an upgrader must land straight in the catalog.
    confirm("Did it go straight to the app catalog — NO onboarding/setup wizard?")
    confirm("Did it avoid re-installing Homebrew from scratch (no long components install), "
            "or, on a case-sensitive volume, install the annex once and then settle?")
    check("the new database was created",
          lambda: (APPLITE_SUPPORT / "casks.sqlite").exists())
    after = run(["defaults", "read", BUNDLE_ID, "brewPathOption"]).stdout.strip()
    check(f"brewPathOption preserved across the upgrade ('{before}' → '{after}')",
          lambda: after == before or not before)
    do_in_app("Open the Installed tab")
    confirm(f"Is '{DMG_CASK}' — installed by v1.3.1 — still listed as Installed?")
    check(f"{DMG_CASK} genuinely still installed on the selected brew",
          lambda: cask_installed(DMG_CASK))
    if _OLD_ANNEX_DIR.exists() and sensitive:
        warn(f"the old v1.3.1 brew is orphaned at {_OLD_ANNEX_DIR} — its casks are now "
             "invisible to Applite. Worth a release note if this is expected.")
    do_in_app(f"Uninstall '{DMG_CASK}' from the new Applite")
    check("the new release can uninstall a cask the OLD one installed",
          lambda: cask_absent(DMG_CASK))
    do_in_app("Press ⌘R (Refresh App Catalog)")
    confirm("Did the catalog refresh cleanly with no error alert?")


# --------------------------------------------------------------------------- #
# Finalize
# --------------------------------------------------------------------------- #


def phase_f1(_state) -> None:
    step("F1", "self-uninstall (LAST)")
    warn("This removes Applite. Do NOT tick 'also uninstall Homebrew' — the harness "
         "manages brew so it can keep the cached prereqs.")
    do_in_app("Settings → Uninstall → Uninstall Applite; confirm")
    check("Applite.app is gone", lambda: not _applite_app_present())

    def no_leftovers() -> bool:
        left = _applite_leftovers()
        if left:
            warn("  still present: " + ", ".join(left))
        return not left
    check("Applite support/cache/prefs folders removed", no_leftovers)
    info("Run `teardown` next to re-hide the prereqs (or `teardown --full`).")


# --------------------------------------------------------------------------- #
# run
# --------------------------------------------------------------------------- #

# Execution order (the numeric id is what --only/--from take; function names are
# historical and don't track the id). Homebrew management runs LAST — refresh preserves
# installed apps, then reinstall wipes them all — so it can't disturb earlier phases.
ROUND_A = [
    ("0", "preflight", phase_a0), ("1", "bootstrap", phase_a1),
    ("2", "install DMG", phase_a2), ("3", "install PKG", phase_a3),
    ("4", "warning cask", phase_a4),
    ("5", "cancel", phase_a6), ("6", "update", phase_a7),
    ("7", "uninstall", phase_a8), ("8", "uninstall+zap", phase_a9),
    ("9", "catalog/search", phase_a12), ("10", "settings", phase_a13),
    ("11", "bulk install", phase_a14), ("12", "bulk update", phase_bulk_update),
    ("13", "batch stop", phase_batch_stop), ("14", "launch", phase_a15),
    ("15", "failed install", phase_failed_install), ("16", "taps", phase_taps),
    ("17", "sparkle", phase_sparkle), ("18", "quit mid-install", phase_quit_mid_install),
    ("19", "refresh brew", phase_a10), ("20", "reinstall brew", phase_a11),
]

ROUND_B = [
    ("B0", "unhide+update+select", phase_b0), ("B1", "install DMG", phase_b1),
    ("B2", "install PKG", phase_b2), ("B3", "update", phase_b3),
    ("B4", "uninstall+zap", phase_b4),
]

ROUND_U = [("U0", "install v1.3.1", phase_u0), ("U1", "upgrade to new build", phase_u1)]

FINALIZE = [("F1", "self-uninstall", phase_f1)]

ROUNDS = ["annex", "external", "upgrade", "finalize"]


def set_round(name: str) -> list[tuple]:
    global BREW
    if name == "annex":
        BREW = ANNEX_BREW
        return ROUND_A
    if name == "external":
        BREW = OPT_BREW
        return ROUND_B
    if name == "upgrade":
        # v1.3.1's brew and this release's annex are the same Application Support tree (modulo the
        # `homebrew`/`Homebrew` case change the round exists to probe).
        BREW = ANNEX_BREW
        return ROUND_U
    if name == "finalize":
        BREW = OPT_BREW
        return FINALIZE
    raise SystemExit("unknown round: " + name)


def cmd_run(args) -> int:
    phases = set_round(args.round)
    ids = [p[0] for p in phases]

    selected = phases
    if args.only:
        selected = [p for p in phases if p[0] == args.only]
        if not selected:
            raise SystemExit(f"--only {args.only}: not in round {args.round} ({', '.join(ids)})")
    elif getattr(args, "from_", None):
        if args.from_ not in ids:
            raise SystemExit(f"--from {args.from_}: not in round {args.round} ({', '.join(ids)})")
        start = ids.index(args.from_)
        selected = phases[start:]

    heading(f"RUN round={args.round}  BREW={BREW}")
    if args.round == "annex" and not ANNEX_BREW.exists():
        bad("The annex Homebrew isn't installed yet — nothing to test against.")
        info("Open Applite and let it install the annex (wait for the catalog to load "
             "and the 'Get Started' button), then re-run:")
        info("    applite_test.py run --round annex")
        return 1
    if not brew_healthy() and args.round != "external":
        warn("brew not responding yet — is Applite still installing the annex? "
             "Wait for 'Get Started', then re-run.")
    if args.round == "annex":
        warn("Invariant for this round: NO 'Install Command Line Tools' dialog should "
             "appear at any step. If one ever does, that's a failure — abort (Ctrl-C) "
             "and report which step. (So the phases no longer ask about it each time.)")
    state: dict = {}
    for pid, title, fn in selected:
        try:
            fn(state)
        except SystemExit:
            raise
        except Exception as e:  # noqa: BLE001
            RESULTS.add(False, f"phase {pid} ({title}) crashed: {e}")
        print()
    return RESULTS.summary()


def cmd_fake_outdated(args) -> int:
    set_round(args.round)
    return 0 if fake_outdated(args.token) else 1


def cmd_verify(args) -> int:
    set_round(args.round)
    heading(f"STATE (BREW={BREW})")
    info("brew healthy: " + str(brew_healthy()))
    info("installed casks: " + (", ".join(installed_tokens()) or "(none)"))
    cp = brew("outdated", "--cask", "-q")
    info("outdated: " + (cp.stdout.strip() or "(none)"))
    info("clt_free: " + str(clt_free()) + " | prereqs_live: " + str(prereqs_live()))
    return 0


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #


def _guard_interpreter() -> None:
    exe = os.path.realpath(sys.executable)
    if exe == "/usr/bin/python3" or "/Developer/" in exe or "/Xcode" in exe:
        sys.exit(
            f"Refusing to run under {sys.executable}.\n"
            "That interpreter is a Command Line Tools stub — it pops the CLT install\n"
            "dialog and stops working once CLT is hidden. Install a standalone python\n"
            "(python.org or `uv python install`) and run e.g.:\n"
            "  /usr/local/bin/python3 applite_test.py ..."
        )
    if sys.version_info < (3, 8):
        sys.exit("Python 3.8+ required.")


def print_cheatsheet() -> None:
    """What a full pass looks like, in order. Printed when the script is run with no subcommand —
    the point is to not have to reread the README just to remember the argument order."""
    py = sys.executable  # whatever standalone python you invoked us with — paste-ready
    print("\n" + _c("1;35", "━━ Applite test harness — a full pass, in order ━━"))
    steps = [
        ("once per VM", f"{py} applite_test.py provision",
         "install brew+CLT if missing, then hide them  → duplicate the .utm bundle here"),
        ("1. reset", f"{py} applite_test.py reset",
         "uninstall all casks, wipe Applite, hide prereqs  → then LAUNCH Applite"),
        ("2. annex round", f"{py} applite_test.py run --round annex",
         f"{len(ROUND_A)} phases, CLT-free (the risky path)"),
        ("3. external round", f"{py} applite_test.py run --round external",
         f"{len(ROUND_B)} phases against your own /opt/homebrew (unhides it)"),
        ("4. finalize", f"{py} applite_test.py run --round finalize",
         "self-uninstall — must be LAST"),
        ("5. teardown", f"{py} applite_test.py teardown",
         "re-hide prereqs for the next run  (--full deletes them)"),
        ("once per release", f"{py} applite_test.py reset && "
                             f"{py} applite_test.py run --round upgrade",
         "v1.3.1 → new build. SEPARATE pass, from its own reset — it starts from an old install"),
    ]
    for label, cmd, why in steps:
        print(f"\n  {_c('1;36', label)}")
        print(f"    {cmd}")
        print(f"    {_c('2', why)}")

    print("\n" + _c("1;35", "  Partial runs"))
    print(f"    {py} applite_test.py run --round annex --only 16     # one phase")
    print(f"    {py} applite_test.py run --round annex --from 11     # this phase onward")

    print("\n" + _c("1;35", "  Handy"))
    for cmd, why in [
        ("preflight [--round …]", "check the test casks still fit their roles (run before a pass)"),
        ("verify [--round …]", "print brew health, installed/outdated, hide state"),
        ("fake-outdated <token>", "rename an installed version to 0.0.1 so brew reports it outdated"),
        ("reset --keep-apps", "fresh state without the uninstall sweep"),
        ("teardown --full", "also delete /opt/homebrew + CLT (pristine image)"),
    ]:
        print(f"    applite_test.py {cmd:26} {_c('2', why)}")

    print("\n" + _c("1;35", "  Phases"))
    for name, phases in (("annex", ROUND_A), ("external", ROUND_B),
                         ("upgrade", ROUND_U), ("finalize", FINALIZE)):
        print(f"    {name:9} " + ", ".join(f"{pid}={title}" for pid, title, _ in phases))

    print("\n" + _c("2", "  Run it on a throwaway VM, under a standalone python3 (not /usr/bin/python3)."))
    print(_c("2", "  Details: Testing/README.md") + "\n")


def main() -> int:
    _guard_interpreter()
    if len(sys.argv) == 1:
        print_cheatsheet()
        return 0
    parser = argparse.ArgumentParser(
        prog="applite_test.py", description="Guided E2E test harness for Applite.")
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("provision", help="one-time: install brew+CLT if missing, then hide")
    p_reset = sub.add_parser(
        "reset", help="fresh state: uninstall all casks, wipe Applite, hide prereqs")
    p_reset.add_argument("--keep-apps", action="store_true",
                         help="skip the brew-uninstall sweep (faster, leaves installed apps)")

    p_run = sub.add_parser("run", help="guided phased suite")
    p_run.add_argument("--round", choices=ROUNDS, default="annex")
    p_run.add_argument("--only", help="run a single phase id (e.g. 7 or B3)")
    p_run.add_argument("--from", dest="from_", help="start from this phase id")

    p_pf = sub.add_parser("preflight", help="validate the configured test casks")
    p_pf.add_argument("--round", choices=["annex", "external"], default="annex")

    p_fo = sub.add_parser("fake-outdated", help="rename a cask's installed version to 0.0.1")
    p_fo.add_argument("token")
    p_fo.add_argument("--round", choices=["annex", "external"], default="annex")

    p_v = sub.add_parser("verify", help="print current brew/prereq state")
    p_v.add_argument("--round", choices=["annex", "external"], default="annex")

    p_td = sub.add_parser("teardown", help="end of pass: re-hide (default) or --full delete")
    p_td.add_argument("--full", action="store_true", help="delete brew+CLT entirely")

    args = parser.parse_args()
    dispatch = {
        "provision": cmd_provision, "reset": cmd_reset, "run": cmd_run,
        "preflight": lambda a: (set_round(a.round), cmd_preflight(a))[1],
        "fake-outdated": cmd_fake_outdated, "verify": cmd_verify, "teardown": cmd_teardown,
    }
    return dispatch[args.cmd](args) or 0


if __name__ == "__main__":
    sys.exit(main())

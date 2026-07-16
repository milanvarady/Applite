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

See Testing/README.md for the full workflow. Short version:

    # once per VM (installs brew + CLT if missing, then hides them):
    /usr/local/bin/python3 applite_test.py provision
    # (snapshot the VM here)

    /usr/local/bin/python3 applite_test.py reset            # fast fresh state
    /usr/local/bin/python3 applite_test.py run --round annex
    /usr/local/bin/python3 applite_test.py run --round external
    /usr/local/bin/python3 applite_test.py teardown

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
HIDDEN_SUFFIX = ".applite-hidden"
LOG_FILE = Path(__file__).resolve().parent / "applite-test.log"

# Representative test casks (one per installer type). `preflight` re-validates
# each against the live catalog, so if a pick drifts you'll be told to swap it.
DMG_CASK = "rectangle"          # small .app-artifact DMG
PKG_CASK = "zoom"               # .pkg installer (exercises the appdir path)
ZAP_CASK = "stats"              # distinct app with a `zap trash:` stanza
UPDATE_CASK = "font-hack"       # versioned, auto_updates:false (fonts never self-update)
WARN_CASK = "aegisub"           # deprecated → triggers the download warning dialog
#                                 (also probes the HOMEBREW_DEVELOPER deprecation risk)
CANCEL_CASK = "libreoffice"     # big download so there's time to hit Stop; cache cleared first
IMPORT_CASKS = ["hiddenbar", "mos"]  # small, not-otherwise-installed casks for the import test

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
        env: dict | None = None) -> subprocess.CompletedProcess:
    """Run a command. Captures output by default; pass capture=False for
    interactive commands (sudo password prompts, installers)."""
    _log("RUN  " + " ".join(args))
    return subprocess.run(
        args,
        check=check,
        text=True,
        capture_output=capture,
        env={**os.environ, **(env or {})} if env else None,
    )


def sudo(args: list[str]) -> bool:
    """Run a privileged command, letting the password prompt reach the terminal."""
    cp = run(["sudo", *args], capture=False)
    return cp.returncode == 0


def brew(*args: str, capture: bool = True) -> subprocess.CompletedProcess:
    return run([str(BREW), *args], capture=capture)


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
    path = brew("--cache", "--cask", token).stdout.strip()
    if not path:
        return
    for p in (path, path + ".incomplete"):
        try:
            os.remove(p)
            info(f"cleared cache: {p}")
        except OSError:
            pass


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


def zap_paths_gone(token: str, saved: list[str]) -> tuple[bool, list[str]]:
    remaining = [str(p) for raw in saved for p in _expand(raw) if p.exists()]
    return (not remaining, remaining)


def brew_healthy() -> bool:
    cp = brew("--version")
    return cp.returncode == 0 and "Homebrew" in cp.stdout


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

TEST_CASKS = [DMG_CASK, PKG_CASK, ZAP_CASK, UPDATE_CASK, WARN_CASK, CANCEL_CASK, *IMPORT_CASKS]


def _uninstall_test_casks_from(brew_exe: Path) -> None:
    if not brew_exe.exists():
        return
    for tok in TEST_CASKS:
        run([str(brew_exe), "uninstall", "--cask", "--zap", "--force", tok])


def _delete_test_apps() -> None:
    for base in ("/Applications", str(Path.home() / "Applications")):
        for tok in TEST_CASKS:
            cask = None
            # Best effort: derive .app names from a live brew if possible.
            for exe in (ANNEX_BREW, OPT_BREW):
                if exe.exists():
                    cp = run([str(exe), "info", "--json=v2", "--cask", tok])
                    if cp.returncode == 0 and cp.stdout.strip():
                        try:
                            cask = json.loads(cp.stdout)["casks"][0]
                        except (json.JSONDecodeError, IndexError, KeyError):
                            cask = None
                    break
            for name in (app_names(cask) if cask else []):
                target = Path(base) / name
                if target.exists():
                    info(f"removing leftover {target}")
                    shutil.rmtree(target, ignore_errors=True)


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


def cmd_reset(_args) -> int:
    heading("RESET → fresh first-run state")
    warn("This deletes Applite's data + annex and HIDES /opt/homebrew + CLT.")
    if input("Type 'reset' to continue: ").strip() != "reset":
        raise SystemExit("Cancelled.")
    require_applite_quit()
    ensure_provisioned()
    # Clean any test casks from a live /opt brew before hiding it.
    _uninstall_test_casks_from(OPT_BREW)
    _delete_test_apps()
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
    _uninstall_test_casks_from(OPT_BREW)
    _delete_test_apps()
    _wipe_applite_data()
    if args.full:
        warn("--full: deleting Homebrew and CLT entirely.")
        for path in (OPT_PREFIX, _hidden(OPT_PREFIX), CLT_PATH, _hidden(CLT_PATH)):
            if path.exists():
                sudo(["rm", "-rf", str(path)])
        shutil.rmtree(Path.home() / "Library/Caches/Homebrew", ignore_errors=True)
        shutil.rmtree(Path.home() / "Library/Logs/Homebrew", ignore_errors=True)
        ok("Full teardown complete — pristine image.")
    else:
        hide_prereqs()
        ok("Teardown complete — brew + CLT kept hidden for the next run.")
    return RESULTS.summary()


def _applite_app_present() -> bool:
    for base in ("/Applications", str(Path.home() / "Applications")):
        if (Path(base) / "Applite.app").exists():
            return True
    return False


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
        *[(t, "app", None) for t in IMPORT_CASKS],
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
    do_in_app("Launch Applite. Watch the setup overlay install the annex brew")
    confirm("Did the annex install with NO 'Install Command Line Tools' popup?")
    confirm("Did the catalog load and 'Get Started' appear?")
    check("brew_healthy (annex, no LoadError)", brew_healthy)
    check("annex brew executable exists", lambda: ANNEX_BREW.exists())


def phase_a2(state) -> None:
    step("2", f"install DMG cask ({DMG_CASK})")
    do_in_app(f"In Applite, search for and install '{DMG_CASK}'")
    check(f"{DMG_CASK} in brew list", lambda: cask_installed(DMG_CASK))
    cask = brew_json(DMG_CASK) or {}
    for name in app_names(cask):
        check(f"{name} present on disk", lambda n=name: app_present(n))
    confirm("Did the green tick CLEAR and the app show as Installed (no popup)?")


def phase_a3(_state) -> None:
    step("3", f"install PKG cask ({PKG_CASK})")
    do_in_app(f"Install '{PKG_CASK}' (a .pkg installer). Enter your password if asked")
    check(f"{PKG_CASK} in brew list", lambda: cask_installed(PKG_CASK))
    cask = brew_json(PKG_CASK) or {}
    for name in app_names(cask):
        check(f"{name} present (appdir {appdir()})", lambda n=name: app_present(n))
    confirm("Did the sudo/password prompt work and the install finish (no CLT popup)?")


def phase_a4(_state) -> None:
    step("4", f"warning-cask dialog ({WARN_CASK}, deprecated)")
    do_in_app(f"Start installing '{WARN_CASK}' — a warning dialog (deprecated) should appear")
    confirm("Did the warning dialog appear?")
    do_in_app("Choose 'Download Anyway' and let it finish")
    # If this FAILS with a deprecation error, that's the HOMEBREW_DEVELOPER risk surfacing.
    check(f"{WARN_CASK} installed (no HOMEBREW_DEVELOPER deprecation error)",
          lambda: cask_installed(WARN_CASK))


def phase_a5(_state) -> None:
    step("5", f"force install ({DMG_CASK})")
    # Force Install only appears in the chevron menu when a cask is NOT installed
    # (installed casks show Reinstall instead — AppView.optionsMenuContent), so the
    # cask must be uninstalled first to reach it.
    do_in_app(f"If '{DMG_CASK}' shows Installed, uninstall it (plain). Then open its "
              "options (chevron) → Force Install")
    check(f"{DMG_CASK} installed after Force Install", lambda: cask_installed(DMG_CASK))
    confirm("Did Force Install complete with no error surfaced?")


def phase_a6(_state) -> None:
    step("6", f"cancel mid-download ({CANCEL_CASK})")
    info(f"Clearing {CANCEL_CASK}'s cached download so it re-downloads (a cached "
         "download finishes instantly — nothing to cancel)…")
    clear_cask_cache(CANCEL_CASK)
    do_in_app(f"Install '{CANCEL_CASK}' (large) and hit the STOP button while it downloads")
    check(f"{CANCEL_CASK} NOT installed after cancel", lambda: cask_absent(CANCEL_CASK))
    confirm("Did the progress reset to idle (no stuck spinner)?")


def phase_a7(state) -> None:
    step("7", f"fake-outdated + update ({UPDATE_CASK})")
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
    confirm("Did the update finish with no CLT popup?")


def phase_a8(_state) -> None:
    step("8", f"uninstall plain ({DMG_CASK})")
    do_in_app(f"Uninstall '{DMG_CASK}' (plain, no zap)")
    check(f"{DMG_CASK} absent from brew list", lambda: cask_absent(DMG_CASK))
    cask = brew_json(DMG_CASK) or {}
    for name in app_names(cask):
        check(f"{name} removed from disk", lambda n=name: not app_present(n))


def phase_a9(state) -> None:
    step("9", f"uninstall + zap ({ZAP_CASK})")
    do_in_app(f"Install '{ZAP_CASK}' if needed, then Uninstall with 'delete app data (--zap)'")
    saved = state.setdefault("zap_saved", {}).get(ZAP_CASK)
    if saved is None:
        cask = brew_json(ZAP_CASK) or {}
        saved = zap_paths(cask)
        state["zap_saved"][ZAP_CASK] = saved
    check(f"{ZAP_CASK} absent from brew list", lambda: cask_absent(ZAP_CASK))

    def zap_clean():
        gone, remaining = zap_paths_gone(ZAP_CASK, saved)
        if not gone:
            warn("  still present: " + ", ".join(remaining[:5]))
        return gone
    if saved:
        check("zap trash/delete paths removed", zap_clean)
    else:
        RESULTS.skip("zap path check (no zap paths captured)")
    confirm("Did the uninstall+zap finish with NO CLT popup (trash via FFI)?")


def phase_a10(_state) -> None:
    step("10", "Refresh Homebrew Components (annex overlay)")
    do_in_app("Settings → Manage Homebrew → Refresh Homebrew Components; wait for it")
    check("brew still healthy after overlay (no LoadError)", brew_healthy)
    check(f"{UPDATE_CASK} still installed (Caskroom survived)",
          lambda: cask_installed(UPDATE_CASK))
    confirm("Did the refresh finish and re-enable the UI?")


def phase_a11(_state) -> None:
    step("11", "Reinstall Homebrew (clean annex)")
    do_in_app("Settings → Manage Homebrew → Reinstall Homebrew; confirm and wait")
    check("annex brew healthy after reinstall", brew_healthy)
    check("brew list is empty (apps unlinked)", lambda: installed_tokens() == [])
    confirm("Are the app bundles still on disk (unlinked, not deleted)?")


def phase_a12(_state) -> None:
    step("12", "catalog refresh + browse (read-only UI smoke test)")
    info("Purpose: the read-only catalog/browse surfaces render and return data — "
         "catalog re-sync, FTS search, sort/filter, categories, taps, and the tabs.")
    do_in_app("Press ⌘R (Refresh App Catalog); wait for it to finish")
    confirm("Did the catalog refresh finish with no error alert?")
    do_in_app("Type a query in the search field")
    confirm("Did search return matching results?")
    do_in_app("Change the sort and toggle a filter in the search toolbar")
    confirm("Did the result order / visibility change accordingly?")
    do_in_app("Open a category from the sidebar, then a Tap (if taps are enabled)")
    confirm("Did the Category and Tap views render their apps?")
    do_in_app("Visit the Installed, Updates, and Active Tasks tabs")
    confirm("Did each tab render the expected content?")


def phase_a13(_state) -> None:
    step("13", "settings: appdir + broken-install recovery")
    do_in_app("Settings → Brew → enable a custom install directory (appdir); then "
              f"install '{PKG_CASK}'")
    cask = brew_json(PKG_CASK) or {}
    for name in app_names(cask):
        check(f"{name} landed in appdir ({appdir()})",
              lambda n=name: (appdir() / (n if n.endswith('.app') else n + '.app')).exists())
    do_in_app("Now set Brew path to a bogus custom path to force a broken install")
    confirm("Did BrokenInstallView appear, and does Retry recover after fixing the path?")


def phase_a14(_state) -> None:
    step("14", "export, then import fresh casks")
    export_path = Path.home() / "Desktop/applite_export.txt"
    do_in_app(f"App Migration → Export apps to {export_path}")
    check("export file exists and is non-empty",
          lambda: export_path.exists() and export_path.stat().st_size > 0)
    check("export lists at least one token",
          lambda: bool(export_path.exists() and export_path.read_text().split()))

    # Write an import file of casks NOT installed yet, so a successful import proves
    # it actually installs (not just "already there").
    import_path = Path.home() / "Desktop/applite_import.txt"
    import_path.write_text("\n".join(IMPORT_CASKS) + "\n")
    for tok in IMPORT_CASKS:
        check(f"{tok} not installed before import", lambda t=tok: cask_absent(t))
    do_in_app(f"App Migration → Import {import_path} "
              f"({', '.join(IMPORT_CASKS)}); let them install")
    for tok in IMPORT_CASKS:
        check(f"{tok} installed via import", lambda t=tok: cask_installed(t))


def phase_a15(_state) -> None:
    step("15", "launch installed app")
    do_in_app("Installed tab → Open on an installed app")
    confirm("Did the app launch?")


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
    confirm("Did Applite switch to /opt/homebrew with NO BrokenInstallView?")


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
    do_in_app(f"Install '{ZAP_CASK}' if needed, then Uninstall with --zap")
    cask = brew_json(ZAP_CASK) or {}
    saved = zap_paths(cask)
    check(f"{ZAP_CASK} absent (external brew)", lambda: cask_absent(ZAP_CASK))
    if saved:
        check("zap paths removed", lambda: zap_paths_gone(ZAP_CASK, saved)[0])
    else:
        RESULTS.skip("external zap path check (none captured)")


# --------------------------------------------------------------------------- #
# Finalize
# --------------------------------------------------------------------------- #


def phase_f1(_state) -> None:
    step("F1", "self-uninstall (LAST)")
    warn("This removes Applite. Do NOT tick 'also uninstall Homebrew' — the harness "
         "manages brew so it can keep the cached prereqs.")
    do_in_app("Settings → Uninstall → Uninstall Applite; confirm")
    check("Applite.app is gone", lambda: not _applite_app_present())
    info("Run `teardown` next to re-hide the prereqs (or `teardown --full`).")


# --------------------------------------------------------------------------- #
# run
# --------------------------------------------------------------------------- #

ROUND_A = [
    ("0", "preflight", phase_a0), ("1", "bootstrap", phase_a1),
    ("2", "install DMG", phase_a2), ("3", "install PKG", phase_a3),
    ("4", "warning cask", phase_a4), ("5", "force install", phase_a5),
    ("6", "cancel", phase_a6), ("7", "update", phase_a7),
    ("8", "uninstall", phase_a8), ("9", "uninstall+zap", phase_a9),
    ("10", "refresh brew", phase_a10), ("11", "reinstall brew", phase_a11),
    ("12", "catalog/search", phase_a12), ("13", "settings", phase_a13),
    ("14", "import/export", phase_a14), ("15", "launch", phase_a15),
]

ROUND_B = [
    ("B0", "unhide+update+select", phase_b0), ("B1", "install DMG", phase_b1),
    ("B2", "install PKG", phase_b2), ("B3", "update", phase_b3),
    ("B4", "uninstall+zap", phase_b4),
]

FINALIZE = [("F1", "self-uninstall", phase_f1)]


def set_round(name: str) -> list[tuple]:
    global BREW
    if name == "annex":
        BREW = ANNEX_BREW
        return ROUND_A
    if name == "external":
        BREW = OPT_BREW
        return ROUND_B
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
    if not brew_healthy() and args.round != "external":
        warn("brew not healthy yet — is Applite installing the annex? Launch it first.")
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


def main() -> int:
    _guard_interpreter()
    parser = argparse.ArgumentParser(
        prog="applite_test.py", description="Guided E2E test harness for Applite.")
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("provision", help="one-time: install brew+CLT if missing, then hide")
    sub.add_parser("reset", help="fast fresh state: hide prereqs + wipe Applite data")

    p_run = sub.add_parser("run", help="guided phased suite")
    p_run.add_argument("--round", choices=["annex", "external", "finalize"], default="annex")
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

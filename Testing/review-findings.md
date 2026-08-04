# Pre-Release Review — Findings

Accumulated findings across four passes over the `v1.3.1` baseline. `TRIAGE.md` ranks them and
carries the current status header; this file is the detail. (The plan/method doc that drove the
passes was deleted once the review finished — it had no content beyond the completed tracker.)

Severity legend: 🔴 gates release / 🟠 fix before release / 🟡 should fix / ⚪️ note / cleanup.

> **This is a snapshot, not a live bug list.** Most of it shipped — all of Tier 1 and nearly all
> of Tier 2. It is kept for the findings that did *not*, where the research is the expensive part
> and would have to be redone from scratch: **P2-8** records the shapes brew actually emits on a
> batch failure (verified against brew 6.0.15), and **P2-9** records that `install --cask A B C`
> wraps the whole loop in one outer rescue while `upgrade` uses per-cask `rescue…next` (verified
> against brew source). Both are still open. Check `git log` for a finding's id before acting on it.

---

# Pass 1 — Architecture & Seam Map

Baseline `v1.3.1`; four cluster readers (annex/brew, database/cask-engine, app-migration,
infrastructure/askpass). **No blocker found** — architecture is fundamentally sound (single-identity
registry, two-stage load contract honored, no main-actor blocking on DB/brew, correct `@Observable`
passthrough in views). The risk is concentrated at a handful of **seams**, mostly around *state that
is written or judged in more than one place with no single owner*.

## 1. Cluster map (one line each)

- **Annex / brew** — `BrewService` (`@Observable @MainActor`, owned by CaskManager) forwards install/uninstall/update through a single serial `queueTail` so only one `brew` runs at a time. Process I/O lives in `Shell` (detached). `HomebrewBootstrap` (`@Observable @MainActor`) owns the annex install/recovery state machine (`phase`). `AnnexBrewManager`/`GitShim`/`BrewPaths` are static utilities.
- **Database / cask-engine** — `AppDatabase.shared` (one `DatabasePool`, all async). `CaskDatabaseService` (async CRUD + FTS5). `CaskViewModelRegistry` is the single-identity VM store; `CaskDataLoader` orchestrates the two-stage load; `CaskManager` is the thin `@MainActor` coordinator. Clean.
- **App migration v2** — pure `AppMigration` enum (Brewfile serialize/parse) + three views. Export reads `installedViewModels`; import resolves tokens against the DB then fires one bulk `installAll`. No filesystem `.app` scanning.
- **Infrastructure / askpass** — `AlertManager` (`@MainActor @Observable`), `AppPaths`, stateless env helpers (`MirrorEnvironment`, `NetworkProxyManager`). Sudo askpass = bundled `askpass.js` (JXA `displayDialog`) wired via `SUDO_ASKPASS` in `Shell.createProcess`; icon staged to a fixed path by `AskpassIcon.write()` at launch.

## 2. Seam matrix (where clusters touch)

| Seam | Mechanism | Health |
|---|---|---|
| Bootstrap/annex → CaskManager load | `bootstrapAndLoad()` orchestrates catalog → `bootstrap.run()` → installed-state → `refreshAnnexIfStale()` | ⚠️ duplicated by `loadData(forceSync:)` with subtly different flag handling |
| Stage-2 (InstalledCaskService) → registry | `refreshInstalled/refreshOutdated` → `registry.markInstalled/markOutdated` | ✅ safe via single-identity |
| BrewService → VM state | writes `isInstalled/isOutdated/progressState` **directly** on the handed VM, never via registry | ⚠️ dual-writer with stage-2, no ordering guarantee |
| AppMigration → installs | `installAll` → `BrewService.runBatch` (`--force`) | ⚠️ success UI decoupled from outcome |
| Askpass → every brew call | `SUDO_ASKPASS` env in `Shell.createProcess` (single choke point) | ✅ uniform; ⚠️ icon path duplicated as string |
| BrewPaths validity → UI | `hasBrokenInstall` + `phase` + `showSetup`, reconciled by hand in ContentView | ⚠️ checked in 4+ places, 3 possible UX outcomes |

## 3. Cross-cutting structural findings (ranked)

### 🟠 F1 — No single source of truth for "brew is broken / path invalid"
`BrewPaths.isSelectedBrewPathValid()` is independently re-invoked and separately reacted to in ≥4
places: `BrewService.runTask`/`runBatch` (`BrewService.swift:356,417`), `CaskManager.loadData`
(`CaskManager.swift:202`), `HomebrewBootstrap.run` (`HomebrewBootstrap.swift:83,100`), and
`BrewPathSelectorView`/`BrewSettingsView`. Two overlapping "is-broken" state machines exist —
`HomebrewBootstrap.phase` (5-case) and `CaskManager.hasBrokenInstall` (Bool) — reconciled only by
hand-written boolean logic and comments in `ContentView.showSetup`/`mainNavigation`. **Consequence:**
the *same* underlying condition surfaces as a `BrewService.alert` toast, a `BrokenInstallView`, OR a
setup overlay depending on which path noticed first — three UX outcomes for one fault. A comment at
`CaskManager.swift:219` already admits a latent "currently unreachable" desync case.
*Recommendation:* one owned broken/valid state (ideally folded into `HomebrewBootstrap.phase`), read
everywhere; delete the parallel `Bool`.

### 🟠 F2 — Dual-writer on `isInstalled` / `isOutdated` (latent race)
`BrewService` writes these booleans optimistically and immediately on op success
(`BrewService.swift:138,218`), while stage-2 `CaskDataLoader.refreshInstalled/refreshOutdated`
reconciles the same fields via the registry. Two uncoordinated writers, no single owner, no ordering
guarantee. **Failure scenario:** a stage-2 refresh in flight when an install completes → last-write-
wins is implicit, so a freshly-installed cask could momentarily revert to "not installed" if
reconciliation lands second with a stale snapshot. Consistent *today* only because flows rarely
overlap. → **carry into Pass 2 (concurrency)** for a real interleaving analysis.

### 🟡 F3 — Duplicated load orchestration (`bootstrapAndLoad` vs `loadData(forceSync:)`)
Both do catalog → check/resolve brew → conditional installed-state → conditional alert, but with
materially different control flow (one sets `hasBrokenInstall`, the other never does; different
alert-deferral logic). This duplication is the direct cause of the F1 flag desync. *Recommendation:*
extract one orchestration path parameterized by entry point.

### 🟡 F4 — Import success indicator decoupled from actual outcome
`ImportAppsView` sets `importSuccessful`/`importedCount` **optimistically before the batch runs**
(`ImportAppsView.swift:79-82`), never awaiting `reconcileBatch`. Import 20, 5 fail → UI still turns
green; the real per-cask failures live only in `ActiveTasksView` on another screen. `reconcileBatch`
*does* correctly tally failures — they just never flow back to the migration UI. → also relevant to
**Pass 3 (failure handling)**.

### 🟡 F5 — `AlertManager` has three ownership patterns + two consumption protocols
Shared (`BrewService.alert` → `CaskManager.alert` passthrough), coordinator-owned parallel
(`CaskManager.loadAlert`), and view-local throwaways (Uninstall/Export/Import/Update). Worse,
`loadAlert` is consumed by a **hand-rolled `.alert()`** in `ContentView.swift:95-109` bypassing the
`.alertManager(_:)` modifier, so `AlertManager.primaryAction`/`primaryButtonTitle` are **dead fields**
for that instance — a future `loadAlert.show(primaryAction:)` would be silently ignored.

### 🟡 F6 — `Shell.createProcess` is a god-choke-point carrying annex business logic
Generic process spawning also branches on `BrewPaths.selectedBrewOption == .annex` to inject
bootsnap/git-shim env (`Shell.swift:330-341`), and reconstructs proxy + mirror env from scratch on
**every** brew invocation (`CFNetworkCopySystemProxySettings` + UserDefaults reads, uncached —
dozens of times per batch install). Annex-specific rules belong in `AnnexBrewManager`/`GitShim`;
env should be built once. Repeated-work smell + a "new brew flavor needs another `if` inside Shell".

### ⚪️ F7 — Askpass icon path duplicated as a string across Swift and JS
`AskpassIcon.iconURL` (`AskpassIcon.swift:20`) and the literal in `askpass.js:25` must stay
byte-identical by convention only — no shared constant, no test. Fails **soft** (system caution icon)
but silently if `AppPaths.applicationSupport` ever changes. Extract a single source or add a test.

## 4. Carry-forward to later passes

- **Pass 2 (concurrency):** F2 dual-writer interleaving; verify serial-stage-2 lock rationale
  (`CaskManager.swift:275`) still holds; stream teardown (`Shell.swift:257-273`) SIGTERM path;
  batch pty-parsing token routing (`applyBatchLine`) for ambiguous-token drops.
- **Pass 3 (failure/resource):** F4 import outcome; `AppDatabase.shared` uses `fatalError` on open
  failure (`AppDatabase.swift:28`) — the one error path that can't reach `loadAlert`/`hasBrokenInstall`;
  askpass user-cancel is indistinguishable from any brew failure (no dedicated branch); coarse
  `readCaskFile` parse error (empty vs malformed both throw `.EmptyFile`); `UninstallSelf` `rm -rf`
  routes through askpass-wired `Shell` unnecessarily.
- **Pass 4 (dead code/clarity):** `registry.busyViewModels` is dead (superseded by
  `activeTasks`); `AlertManager.primaryAction`/`primaryButtonTitle` dead for `loadAlert`;
  synchronous main-thread `readCaskFile` read+regex not offloaded (`ImportAppsView.swift:91`).

## 5. Verdict on the freeze
Structurally safe to proceed. Nothing here demands re-architecting before release. **F1 and F2 are
the two seams worth a decision** — F1 is a UX-consistency/robustness cleanup; F2 is the one item with
genuine correctness risk and should get a focused look in Pass 2 before sign-off.

---

# Pass 2 — Correctness & Concurrency

Method: 7 parallel finders (4 concurrency angles + 3 correctness angles) scoped to the ~40
concurrency/correctness-critical source files (all *new* since v1.3.1 — the GRDB-rewrite engine).
Cleanup/style/altitude deferred to Pass 4 as planned. **The release-gating clusters below were
verified by me reading the exact lines**; items marked *(finder)* rest on a finder's evidence
(several checked against installed Homebrew 6.0.15 Ruby source or executed the regex) and are marked
CONFIRMED / PLAUSIBLE accordingly. The formal Phase-3 gap-sweep was folded into manual verification
rather than a separate agent (see Coverage gaps at the end).

**Headline: this pass changes the Pass 1 verdict.** Pass 1 said "structurally safe to freeze." Pass 2
surfaces a **security cluster (shell injection)** and several **confirmed data-loss / silent-wrong-state
bugs** that, in my judgment, gate the release. Details below; the fix/no-fix decision still belongs to
Triage (findings-first rule) — but the security items are the one place that may justify acting early.

## 🔴 Tier 1 — Release-gating (CONFIRMED by direct read)

### P2-1 — Shell command injection via `/bin/sh -c` string interpolation *(security)*
`Shell.createProcess` runs every command as `/bin/sh -c <command>` (Shell.swift:369, and the pty path
:366), where `<command>` is built by string interpolation. Three untrusted inputs reach it unescaped:
- **Cask token** — `install()` splices `vm.token` **completely unquoted**: `arguments = [vm.token, "--force"]`
  → `... install --cask <token> --force` (BrewService.swift:83,86). Applite **deliberately loads
  untrusted third-party tap metadata** (trust check stubbed in `brew-tap-cask-info.rb`, per CLAUDE.md),
  and a cask's token derives from its Ruby filename → a tap cask named `foo$(curl x|sh).rb` executes
  arbitrary shell on install/update/uninstall.
- **Custom brew path** — `URL.quotedPath()` wraps in literal `"…"` with **zero escaping**
  (URL+QuotedPath.swift:12); the custom brew path is a user-editable free-text field and prefixes
  *every* brew command.
- **Appdir path** — `--appdir="\(appdirPath)"` (BrewService.swift:78), free-text field, unescaped.

Failure: a `"`, `;`, `$(…)`, or backtick in any of these breaks out of the intended command.
**Fix altitude:** pass arguments as an argv array to `Process` (no shell) or route all interpolation
through a real POSIX-quoting helper — the current per-call string building is the wrong depth.

### P2-2 — `install()` uses bare `vm.token` where every sibling uses `vm.fullToken`
BrewService.swift:83 builds the install command from `vm.token`; `uninstall` (:150), `update`,
`reinstall`, and the batch path all use `fullToken`. Failure: with "Include Casks from Taps" on and a
tapped token colliding with a core cask, `brew install --cask <bareToken>` resolves to the **wrong
(core) cask** silently, or raises `TapCaskAmbiguityError` and fails outright. *(finder, + confirmed by read)*

### P2-3 — F2 dual-writer stomps just-installed/updated state (the Pass 1 F2, now CONFIRMED)
`registry.markInstalled/markOutdated` do **full set-membership reconciliation** over every VM
(`if vm.isInstalled != match { vm.isInstalled = match }`, CaskViewModelRegistry.swift:55-72), fed by an
uncoordinated `brew list`/`brew outdated` snapshot (CaskDataLoader.swift:104-118). `BrewService`
writes `vm.isInstalled = true` / `vm.isOutdated = false` directly (BrewService.swift:138,218). Nothing
serializes the two. Failure: a stage-2 refresh whose snapshot predates a just-finished install applies
last and forces the cask **back to "not installed"** (button reverts, stays wrong until next manual
reload); symmetric case re-shows an "Update available" badge on a just-updated app.

### P2-4 — Bootstrap re-entrancy silently reverts the user's brew choice + can corrupt the annex
`bootstrap.run()` has **no single-flight guard** (HomebrewBootstrap.swift:78, unconditional
`phase = .checking`), and `loadData(forceSync:)` is a **second entry point** into it (Cmd+R / Settings
"Refresh Catalog") that never bumps `attempt`, so it doesn't cancel an in-flight `bootstrapAndLoad`.
Two confirmed consequences:
- **Choice reverted:** during first-run annex install, a user who switches to their own brew in
  Settings isn't cancelled (the `Task.checkCancellation()` guard at bootstrap:145 only covers `attempt`
  bumps, not the Settings/`loadData` path), so `installAnnex()` completes and sets
  `BrewPaths.selectedBrewOption = .annex` (:148), **silently discarding their choice** and re-popping
  the overlay. The code comment shows this was *meant* to be handled — the wiring is incomplete.
- **Annex corruption:** two concurrent `run()`→`installAnnex()` calls both invoke
  `prepareAnnexDirectory(clean: true)` (:138) — one wipes the tree the other is extracting into. *(finder)*

### P2-5 — Transient tap-fetch failure DELETES all custom-tap casks from the DB *(data loss)*
`syncFromAPI` deletes every DB token absent from its input `records`, unconditionally, no lower-bound
guard (CaskDatabaseService.swift:117-125). But `fetchTapDTOs()` is **non-throwing and returns `[]` on
any failure** (missing script, brew hiccup, tap repo unreadable, decode error) and its output is merged
into `records`. Failure: one transient failure → every custom-tap cask deleted from `casks` + FTS,
including ones the user has installed, until the next successful fetch. *(finder, + confirmed by read)*

### P2-6 — No offline fallback → returning user sees infinite shimmer all session
`loadCatalogData` syncs from the network **first** (CaskDataLoader.swift:44-49) and throws before
reading the DB rows that already exist. The deleted `CaskCacheService` used to fall back to cache;
`hasCasks()` exists but is never called. Failure: returning user, offline, catalog stale (default 3
days) → whole load throws → Discover/categories/taps shimmer forever though yesterday's full catalog is
in SQLite. Retry re-runs the same failing fetch. *(finder, + confirmed by read)*

## 🟠 Tier 2 — Fix before release

### P2-7 — `runProcessAsync` has no cancellation wiring → a hung brew wedges the whole serial queue
`Shell.runProcessAsync` (backing `runBrewCommand`/`runAsync`) uses a bare
`withCheckedThrowingContinuation` with no `withTaskCancellationHandler`/`isCancelled` and is always
called with `timeout: nil` (Shell.swift ~38-95). Cancelling the awaiting Task is a no-op; the child
runs on. Because every op chains through `queueTail` (`await previous?.value`), one wedged call
(stalled sudo/askpass, brew lock, network stall) **permanently blocks every later install/update**.
Also lets a "cancelled" stale bootstrap keep running past its cancel point. *(finder ×3, structural)*

### P2-8 — Homebrew batch-error parsing never matches real output → wrong/missing failure reasons
`applyBatchLine`'s `Error: (\S+?):` matcher (BrewService.swift:544) doesn't match brew's real batch
error shape (`Error: Problems with multiple casks:\n<token>: <reason>` for upgrade; `Cask '<t>' is
unavailable: …` for install — verified against brew 6.0.15). `perCaskError` stays empty →
`reconcileBatch` shows each failed card the **entire raw batch output** instead of its reason. *(finder)*

### P2-9 — Install batches abort on first failure; later casks mismarked as failed
Homebrew wraps the whole `brew install --cask A B C` loop in one outer rescue (verified vs source), so
if A fails, B and C are never attempted — yet Applite marks B and C **failed with A's error text**
though they were fine (update batches differ — brew uses per-cask `rescue…next` there). *(finder)*

### P2-10 — `activeTasks` evicted by `viewModel` identity, not task id
`runTask`/`runBatch` `defer` blocks remove entries via `$0.viewModel == vm` / token-set membership
(BrewService.swift:344-346, 407-409). A finishing op can delete a **different, still-queued** op's
tracking row for the same cask → it vanishes from `ActiveTasksView` and `cancel(vm)` silently no-ops
while its brew process runs. *(confirmed mechanism; trigger = two ops on one cask queued close together)*

### P2-11 — Failure notifications silently never fire on a fresh install
`SendNotification` reads raw `UserDefaults.standard.bool(forKey: "notificationFailure"/"Success")`
(lines 47-48), which returns `false` for an unwritten key, bypassing the type-safe `default: true`.
`!false → true → return`. Until the user toggles the setting (a real write), no success/failure
notifications appear. Should use `UserDefaults.value(for: Preferences.…)` like NetworkProxyManager. *(finder, + confirmed)*

### P2-12 — Uninstall wipes Applite's own data BEFORE the throwing Homebrew step
`uninstallSelf` deletes all app data (UninstallSelf.swift:49), then runs
`uninstallHomebrewCompletely()` (:58) which throws on permission-denied — flat `try await`, no
`do/catch`, so the throw skips the self-destruct block (:65-79). Failure: user checks "also uninstall
Homebrew" without admin rights → data irreversibly wiped, uninstall fails, app left installed +
running in a reset/broken state. *(finder, + confirmed)*

### P2-13 — Synchronous GRDB open on the main actor at launch
`AppDatabase.shared` (file open + WAL + `DatabaseMigrator`) is first touched *non-async* inside
`CaskManager()` init at app start (AppDatabase.swift:22-30). On a slow disk / fresh-install DDL this
blocks the UI before first paint — against the project's own "never block the main actor on disk"
rule. *(finder, structural)*

### P2-14 — `fatalError` on DB-open failure → unrecoverable crash-loop for non-technical users
AppDatabase.swift:28 hard-crashes on open failure (corrupt WAL after a force-quit, full disk). No
recreate/backup/recovery path, and it runs before any UI. The target audience can't recover without
deleting `casks.sqlite*` by hand. (Also raised in Pass 1 carry-forward.) *(finder, structural)*

## 🟡 Tier 3 — Should fix

- **P2-15 — Brewfile regex drops versioned casks.** `readCaskFile`'s `cask "([\w/-]+)"` excludes `@`
  and `.`, so `cask "temurin@17"` / `firefox@esr` silently vanish on import — and it **breaks Applite's
  own export→import round trip** (export writes fullToken). Empirically verified. AppMigration.swift:41. *(finder)*
- **P2-16 — `installAnnex` catch swallows genuine errors when `Task.isCancelled`** (bootstrap:162):
  a real failure coinciding with an unrelated cancel is discarded, leaving `phase` stuck at
  `.installing` (overlay hangs forever if no follow-up task runs). *(finder, PLAUSIBLE)*
- **P2-17 — `Shell.stream` TOCTOU: cancel between process store and `run()`** skips `terminate()`,
  orphaning a `brew`/`curl|tar` process (Shell.swift ~142/267). *(finder, PLAUSIBLE — narrow timing)*
- **P2-18 — `primeRuby()` has no real mutual exclusion** (bootstrap:201) — only safe if exactly one
  bootstrap pass runs; concurrent passes (P2-4) collide on brew's `vendor-install ruby` lock. *(finder, PLAUSIBLE)*
- **P2-19 — `reconcileBatch` outdated recheck drops the `-g` greedy flag** (BrewService.swift:589):
  a greedy-outdated cask brew declined to touch is marked succeeded + `isOutdated` cleared. *(finder, PLAUSIBLE)*
- **P2-20 — Non-atomic `shouldSync`+`syncFromAPI`** → two overlapping loads both fetch + full
  delete/upsert (double network, state flicker). Same re-entrancy root as P2-4. *(finder)*
- **P2-21 — Mirror env vars set to `""` when blank** (MirrorEnvironment.swift:17-22) → brew sees an
  empty `HOMEBREW_BOTTLE_DOMAIN` (truthy in Ruby) instead of unset, defeating its default fallback. *(finder)*
- **P2-22 — Brewfile BOM not stripped** (`CharacterSet.whitespaces` excludes U+FEFF) → first token of a
  BOM-prefixed list fails to resolve, invisibly. AppMigration.swift:52-58. *(finder)*
- **P2-23 — `IN (?,?…)` with no chunking** (CaskDatabaseService.swift:41-48,121) can exceed SQLite's
  variable limit on a large import (thousands of tokens, doubled by the two-column check). *(finder, PLAUSIBLE)*
- **P2-24 — Stale detail panes after a refresh.** `SidebarItem.tap` embeds the whole `TapLoadResult`
  (SidebarItem.swift:21) and categories can `compactMap`-drop on sync — a selected tap/category then
  shows a stale or blank detail pane with the sidebar highlight lost. *(finder, PLAUSIBLE)*
- **P2-25 — Trailing-byte / partial-line loss on stream teardown** (Shell.swift ~66/235): a final
  unterminated `Error:` fragment arriving as the process is killed can be dropped, weakening the shown
  failure message. *(finder, PLAUSIBLE)*

## ⚪️ Tier 4 — Note / latent / pre-existing (not new to this release)

- **P2-26 — Proxy port `0` not validated** (NetworkProxyManager.swift:88) → an all-requests-fail proxy
  config instead of falling back to none. *(finder, PLAUSIBLE)*
- **P2-27 — `preferredProxyType` raw-read default bypass** (NetworkProxyManager.swift:23) — latent
  today (auto-detect also tries HTTP first); becomes visible if priorities change. Same class as P2-11. *(finder)*
- **P2-28 — `INSERT OR REPLACE` churns all ~10k rows + FTS triggers every sync** (efficiency/altitude,
  → also Pass 4) and reassigns rowids each cycle. *(finder)*
- **P2-29 — `fullToken` UNIQUE collision under `INSERT OR REPLACE`** silently drops a row on a rename
  overlap (order-dependent). Rare. *(finder, PLAUSIBLE)*
- **P2-30 — `Bundle.main.bundleIdentifier!` force-unwrap** in AppDatabase/CaskDatabaseService loggers —
  latent; crashes only in a Swift unit-test/CLI harness (none exist yet). *(finder)*
- **P2-31 — Shared app-wide alert across every AppView card** (AppView.swift:60) — one failure can
  present on the wrong card / not at all. **Pre-existing since v1.3.1** (confirmed via git show), not a
  regression; relates to Pass 1 F5. *(finder)*
- **P2-32 — Non-exhaustive `switch` on bootstrap `Phase`** (ComponentsInstallView / SetupStatusIcon,
  `default:` catch-all) — no compiler safety net if a Phase case is added. Latent. *(finder)*

## Coverage gaps (honest limits of this pass)
Not deeply exercised, candidates for a follow-up or Pass 3: **Sparkle updater** integration
(`UpdaterEnvironmentKey`, background update flow); the **askpass.js runtime path** (only the Swift side
was traced, not the JXA dialog behavior under a real sudo invocation); **SwiftUI setup-flow view
states** beyond the phase-switch exhaustiveness; and **GRDB migration idempotency** across a
version-upgrade path (only the current schema was read). A separate Phase-3 sweep agent was not run.

## Pass 2 verdict
**Recommend NOT shipping as-is.** The security cluster (P2-1) plus the confirmed data-loss/wrong-state
bugs (P2-3, P2-5, P2-6, P2-4) are release-gating in my judgment. Full triage (ranking + fix decisions)
still happens after Pass 3/4 per the findings-first rule — but P2-1 (shell injection) is the one item
that may warrant acting before the review completes. That's a call for the maintainer.

---

# Pass 3 — Failure & Resource Handling

Method: 5 parallel finders (error-surfacing, failure-recovery/stuck-UI, resource-cleanup,
partial-failure-outcomes, coverage-gaps) told to skip Pass-2 correctness bugs and hunt only the
failure/resource angle: *when something fails, does the app surface it, recover, and clean up?*
Tier-2 items verified by direct read.

**Through-line:** Pass 3 mostly *confirms* the Pass-1 architectural seams — F1 (no single owner of
"broken" state) and F5 (three AlertManager ownership patterns) — now showing up as concrete
failure-handling gaps. The dominant pattern is **"the failure is computed but never reaches the
user"**, plus **thin recovery** (dead-ends, disabled-when-needed buttons) and **non-atomic annex ops**
that turn a transient failure into a destroyed install. No new security/data-loss at Pass-2 severity,
but two solid Tier-2 robustness items.

## 🟠 Tier 2 — Fix before release

### P3-1 — `brew --version` runs with no timeout → app silently hangs in `.checking` forever *(CONFIRMED)*
`isBrewPathValid` calls `Shell.runAsync("… --version")` with **no timeout** (BrewPaths.swift:85);
`resolveBrewOnPath` one method down uses `timeout: .seconds(5)` precisely "so a hung shell can never
stall app launch." Since `runProcessAsync` also has no cancellation (P2-7), a hanging `brew --version`
(locked brew, network-mounted prefix, broken login-shell env) leaves `bootstrap.run()` awaiting
forever → `phase` stuck at `.checking`. `showSetup` treats `.checking` as not-showing and
`hasBrokenInstall` is false, so **no overlay and no BrokenInstallView appear**; the DB catalog renders
so the app looks normal, but installed/outdated state never resolves and there's no recovery short of
force-quit.

### P3-2 — Non-atomic annex reinstall destroys the working install on failure *(CONFIRMED)*
`installAnnexClean` wipes the existing tree (`prepareAnnexDirectory(clean:true)`,
AnnexBrewManager.swift:91) **then** extracts as a separate throwing step (:92) — no temp-dir-then-swap,
no rollback. A `curl|tar` failure after the wipe (network drop, disk full, quit mid-extract) leaves the
annex empty/partial; the previously-working Homebrew is gone and the only path back is a lucky retry.
The non-destructive refresh overlay (:110) has the sibling problem: a mid-extract failure leaves mixed
stale/new files that `verifyAnnexInstall`'s `brew --version` can still pass, surfacing later as an
obscure "cannot load such file." *(pipefail guards the silent-truncation case, not a thrown failure)*

### P3-3 — Partial two-stage load shows "All your apps are up to date" when the check failed
`loadInstalledState` runs `refreshInstalled` then `refreshOutdated` in one do/catch
(CaskManager.swift:270). If `refreshOutdated` throws, `outdatedViewModels` stays empty and
`UpdateView` (:88) renders `ContentUnavailableView("No Updates Available" / "All your apps are up to
date.")` — **false reassurance**: the user silently misses updates because the outdated check never
ran, with no per-stage retry (only a full `loadData`). *(finder)*

### P3-4 — Import shows success regardless of outcome AND the failure alert can't present there
`ImportAppsView` sets `importSuccessful = true` / `importedCount` optimistically before observing the
batch (:77) — permanent green "Installing N apps…" even if most fail. Worse, the migration screen
mounts **no AppView**, and the batch failure alert writes to `caskManager.alert` which is only bound via
`.alertManager(…)` inside `AppView` (:60) — so on the migration screen the alert **cannot present at
all**; it only appears later, out of context, on some other screen. No path back to the failed subset
even though `reconcileBatch` computes the exact failed-names list. (Confirms & expands Pass-1 F4.) *(finder)*

## 🟡 Tier 3 — Should fix

- **P3-5 — Shared single-slot `AlertManager` loses/misroutes messages.** `BrewService.alert` is bound
  to *every* AppView card (AppView.swift:60; one per cask in the grid); a failure flips the one shared
  `isPresented` while many cards are mounted (esp. during install-all) → SwiftUI presents on an
  arbitrary/wrong card, or "already presenting", or not at all if the card recycled. And `alert.show()`
  has no queue (AlertManager.swift:20), so a batch's "these failed" message is silently overwritten by
  the next failure. Elevates Pass-1 F5 / Pass-2 P2-31 with concrete triggers. *(finder ×2)*
- **P3-6 — Title-only failure alerts, no message, one not even logged.** `BrewActionsView`'s "Refresh
  failed" (:107) and "Reinstall failed" (:163) alerts pass no `message:`; the reinstall catch (:137)
  doesn't even `logger.error` → a persistent cause (locked/partial annex dir) yields identical
  uninformative alerts on every retry with nothing in Console to diagnose. Dead-end for the target user. *(finder ×2)*
- **P3-7 — Settings "Refresh Catalog" recovery button disabled exactly when needed.**
  `.disabled(… || !isSelectedBrewPathValid)` (BrewSettingsView.swift:97) — the affordance to recover
  from a bad brew path is disabled *by* the bad brew path, and isn't re-polled while Settings stays open.
  The only recovery is the undiscoverable ⌘R. *(finder)*
- **P3-8 — `.brewMissing` shows wrong recovery copy + no in-overlay annex fallback.**
  `ownBrewNote` ("switch to your own brew in Settings") shows even in `.brewMissing`, where the user's
  own brew IS the missing thing (ComponentsInstallView.swift:153); Retry just re-validates the broken
  path and loops, with no offered fallback to the annex. *(finder)*
- **P3-9 — `pruneAnnexCache` skipped on the failure path → unbounded cache growth** *(CONFIRMED)*.
  It's only reached at the tail of a fully successful `refreshAnnexBrew` (AnnexBrewManager.swift:116);
  repeated refresh failures + continued installs grow `HOMEBREW_CACHE` without bound (sole prune site). *(finder)*
- **P3-10 — `cancelAllAndWait` gives up after 2s with no SIGKILL escalation** (BrewService.swift:290)
  and `applicationShouldTerminate` exits anyway → a slow-to-SIGTERM brew/curl (pty `script` child) is
  left running detached after Applite quits. *(finder)*
- **P3-11 — `refreshAnnexIfStale` fails silently with no cap/warning** (HomebrewBootstrap.swift:225) →
  Homebrew drifts stale release after release with zero UI indication until an unrelated op breaks. *(finder)*
- **P3-12 — Silent tap disappearance (user-facing half of P2-5).** `fetchTapDTOs` logs-and-returns `[]`
  on any failure (CaskDataLoader.swift:203); `loadCatalogData` returns normally, so tap sections vanish
  from the sidebar with **no alert/toast** — looks like the user's taps deleted themselves. *(finder)*
- **P3-13 — FTS5 triggers live only in `v1_initial`** (AppDatabase.swift:98). A future `casks`-table
  rebuild (GRDB's recommended migration technique drops+recreates the table) silently drops the FTS
  sync triggers → search returns stale/empty for upgraders, indistinguishable from "no matches". Latent
  but a real upgrade-path landmine. *(finder)*
- **P3-14 — `AppDatabase.schemaVersion` is never read** (AppDatabase.swift:14) — dead code that looks
  load-bearing (a real `CategoryCatalog.schemaVersion` exists elsewhere). A contributor bumping it to
  force a migration gets nothing; `eraseDatabaseOnSchemaChange` derives from migration identifiers, not
  this field. *(finder)*

## ⚪️ Tier 4 — Note / latent / minor

- **P3-15 — `failureReason` defined on `CaskLoadError`/`ShellError`/`AnnexBrewError` but never read**
  anywhere (all sites use `.localizedDescription` → `errorDescription` only) → the more actionable text
  is structurally unreachable. *(finder)*
- **P3-16 — `AskpassIcon.write()`'s handle-less `Task.detached` can recreate `~/Library/Application
  Support/Applite` AFTER uninstall's `rm -rf`** (AskpassIcon.swift:33), leaving a folder behind that
  survives the uninstall it raced. *(finder)*
- **P3-17 — `activeTasks` grows unbounded** — failed entries are only removed by explicit
  `dismissFailure` or re-queue; no cap/TTL, each pins a finished Task + CaskViewModel
  (BrewService.swift:282). *(finder)*
- **P3-18 — Sparkle "Check for Updates" has no `canCheckForUpdates` guard/observation** at its three
  call sites (Commands.swift:36, AppliteAppView.swift:36, UpdateSettingsView.swift:26) → re-entrant
  clicks during an in-flight check, no feedback. *(finder)*
- **P3-19 — Auto-update toggles are `@State` captured once from `updater.*` in init, never re-synced**
  with Sparkle's KVO (UpdateSettingsView.swift:17) → the switches can desync from the updater's real
  state (relevant to the project's KVO-in-AsyncStream convention). *(finder)*
- **P3-20 — `askpass.js` `catch` discards all diagnostics** (:44) — user-Cancel and a JXA/TCC failure
  both collapse to `$.exit(255)` with no log, so "brew fails, never prompts for password" is
  unreproducible and invisible in Console. Plus no wrong-password/attempt-count context on sudo's retry
  (:38). *(finder — the Pass-2 askpass-cancel coverage gap, now closed)*
- **P3-21 — Orphaned `primeRuby` process on escape-hatch** — its `brew list --cask` (which triggers the
  large one-time `vendor-install ruby`) has no timeout and can't be cancelled (HomebrewBootstrap.swift:196);
  links P2-7 / P2-18 from the resource-leak angle. *(finder)*

## Coverage note
Pass 3 closed the three Pass-2 gaps (Sparkle, askpass.js runtime, migration idempotency). Still not
exercised: real-device behavior of the sudo dialog under current macOS TCC, and an actual
old-DB→new-schema upgrade run (only the migrator source was read).

## Pass 3 verdict
No new release-gating security/data-loss beyond Pass 2. Adds **two Tier-2 robustness items** (P3-1
silent hang, P3-2 destructive reinstall) and a broad set of *failure-surfacing/recovery* gaps that
share roots with Pass-1 F1/F5. These strengthen the "don't ship as-is" recommendation but the fix
decisions remain for Triage.

---

# Pass 4 — Dead Code, Clarity & Style

Method: 5 parallel finders (dead-code, CLAUDE.md conventions, reuse/simplification, efficiency+altitude,
SwiftUI clarity/perf) over the changed surface + swiftui-pro lens. Low-severity maintainability —
**none release-gating**. Items are well-evidenced (usage counts, quoted rules, structural), so unlike
the Pass-2/3 gating bugs I did not independently re-read each. Grouped by cleanup type. The de-extension
reorg has largely held (no Combine, no `Type+View.swift` owned-type splits) — remaining items are the tail.

## A. Dead code — remove (or wire up)
- **P4-A1 — `CaskViewModelRegistry.busyViewModels`** — 0 references; superseded by `activeTasks`. Remove. *(confirms Pass-1/P2)*
- **P4-A2 — `CaskRecord.hasWarning` + `CaskViewModel.hasWarning`** forwarding chain — 0 references (views check `warning != nil` directly). Remove both.
- **P4-A3 — `loadCatalog(surfaceError:)` parameter** — every call passes `false`; the `true` branch (loadAlert.show) is unreachable. Drop the param.
- **P4-A4 — `CaskDatabaseService.hasCasks()`** — 0 references. NOTE: don't just delete — this is the exact helper P2-6's offline-fallback fix should *use* (read DB when sync fails). Wire it up instead.
- **P4-A5 — `CaskLoadError.failureReason` / `AnnexBrewError.failureReason`** — 0 reads (all sites use `.localizedDescription` → `errorDescription`). Either wire into surfacing (P3-15) or remove. (`ShellError` has none — earlier assumption corrected.)
- **P4-A6 — `AlertManager.primaryAction`/`primaryButtonTitle` dead *for `loadAlert`*** — not globally dead (`UpdateView` uses them); it's a symptom of F5's split alert usage, resolved by unifying the alert path, not by deletion.

## B. Duplication — consolidate (several are the right home for Pass-2/3 fixes)
- **P4-B1 — token-OR-fullToken match repeated 3×** (registry `markInstalled`/`markOutdated`, `BrewService.swift:606`, batch lookup `:444`) → one `CaskViewModel.matches(anyOf:)`. **This is where P2-2's token bug should be fixed once.**
- **P4-B2 — `markInstalled`/`markOutdated` byte-identical** → `updateFlag(tokens:_ keyPath:)`.
- **P4-B3 — catalog-error + resolve-installed-state block duplicated 3×** across `bootstrapAndLoad`/`loadData` (CaskManager :173/:203/:234) → one helper. Concrete form of **Pass-1 F3**; the place to land the P2-4/F3 single-orchestration fix.
- **P4-B4 — `casksCoupled(by:)` re-implements `Array.chunked(into:)`** (CategoryLoadResult.swift:53) → call the existing helper.
- **P4-B5 — appdir-arg building** duplicated `install()` vs `runBatchOperation` → `appdirArguments()`.
- **P4-B6 — brew-path-invalid guard block** copy-pasted `runTask`/`runBatch` (BrewService :356/:417) → shared helper.
- **P4-B7 — raw-`UserDefaults` reads** bypass the typed accessor at SendNotification :47-48 and NetworkProxyManager :23 → `UserDefaults.value(for:)`. **Fixes P2-11 and P2-27 as a DRY change.**
- **P4-B8 — `remark(title:color:message:)` `Text + Text + Text`** helper copy-pasted in UninstallView :84 and BrewActionsView :77 → one shared helper, use interpolation.
- **P4-B9 — askpass icon path hardcoded in Swift and JS** (AskpassIcon :20 / askpass.js :25) → single source. (Pass-1 F7.)

## C. Conventions — CLAUDE.md (rule quoted in each)
- **P4-C1 — `BrokenInstallView` lives in `DetailView.swift`** but is owned/used from `ContentView.swift:68` → own file. ("One view struct per file.")
- **P4-C2 — `EnvironmentInput` second view struct in `MirrorsView.swift`** → own file in `Components/`.
- **P4-C3 — `View+CardActionPill.swift` defines owned types** (`CardActionPillModifier`, `CardPillButtonStyle`) in `Extensions/` → move to `Components/`. (Sole `Extensions/` file that isn't a pure external-type extension.)
- **P4-C4 — `FontExtension.swift`** breaks the `Type+Feature.swift` naming convention → `Font+Applite.swift` (or similar).

## D. View performance — the roadmap's "view-perf pending" cluster
- **P4-D1 — Registry `installedViewModels`/`outdatedViewModels` filter+sort the whole registry on every access**, read in ≥2 sites/render; the always-on-screen sidebar count badge is thereby observation-tied to *every* cask, so one install/uninstall triggers a full O(n log n) refilter just to redraw a number. Cache incrementally on `markInstalled`/`markOutdated`, or expose O(1) `installedCount`/`outdatedCount` for the badge. **Highest-impact perf item.**
- **P4-D2 — `DiscoverSectionView.casksCoupled`** re-sorts ~5× per body pass, once per category, on the default landing screen (DiscoverSectionView :73). Derive once.
- **P4-D3 — `CategoryView` sorts inline in `body`** (`sortedCasks(by:)`, :31) every render.
- **P4-D4 — `SearchView.displayedResults` filter+sort runs twice per body** (read at :33 and :36); same shape in `TapView`/`UpdateView`/`InstalledView.filteredCasks`. Compute once.
- **P4-D5 — `CaskSelectionSheet` builds `Binding(get:set:)` per row in body** (:136) → `@State` + `onChange` (project's own preferred pattern).
- **P4-D6 — `Shell.createProcess` rebuilds env synchronously on the main actor every call** (proxy CFNetwork + UserDefaults + `GitShim.ensureInstalled` doing a full file read) → memoize, invalidate on settings/annex change. (Pass-1 F6, + GitShim disk I/O :53.)
- **P4-D7 — `isSelectedBrewPathValid()` spawns a `brew --version` subprocess before every queued op** (BrewService :356/:417) → validate once per load/settings-change and cache, or use a lightweight executable-exists check. (Also intersects P3-1's no-timeout hang.)
- **P4-D8 — `syncFromAPI` `INSERT OR REPLACE` churns all ~10k rows + FTS triggers every sync** → diff and write only changed rows. (= P2-28.)
- **P4-D9 — First-run `loadCatalog` and `bootstrap.run` run serially though independent** (CaskManager :170) → `async let` to overlap catalog sync with annex download (distinct from the intentionally-serial refreshInstalled→refreshOutdated).

## E. Altitude — deeper refactors (Pass-1 seams, now with concrete shape)
- **P4-E1 — Fold `hasBrokenInstall` into `HomebrewBootstrap.Phase`** (one source of truth ContentView switches on) — the code's own comment (CaskManager :219) admits it's "a fallback for the currently-unreachable case." (**Pass-1 F1**; also fixes the F1 UX-divergence.)
- **P4-E2 — Give `Shell` a `BrewEnvironmentStrategy` per `PathOption`** instead of `if selectedBrewOption == .annex` inside the generic spawner (Shell :330) so `Shell` needn't know the annex exists. (**Pass-1 F6**.)
- **P4-E3 — Move `brokenPathOrInstallMessage` out of `AnnexBrewManager`** to a neutral strings home; `BrewService`/`DetailView` shouldn't import annex machinery for a generic message. (**Pass-1 F8**.)

## F. Accessibility — quick wins (VoiceOver)
- **P4-F1 — Icon-only controls with no accessible label**: the per-card ellipsis `Menu` (AppView :154, hundreds of instances), the failed-install error-row buttons (AppView :273-288, only `.help()`), and the self-card trash button (AppliteAppView :40). Add labels (`Menu("More Options", systemImage:)` etc.).
- **P4-F2 — `InfoPopup` reachable only by mouse hover** (:34) — a plain `Image` with `.onHover`, no `Button`/`.accessibilityAddTraits(.isButton)`/keyboard path, so VoiceOver & keyboard users never see cask warnings/deprecations/tap caveats. Also a dead `.buttonStyle(.plain)` on a non-Button.

## Pass 4 verdict
No release-gating items. The cleanup naturally *co-locates* with the real fixes: P4-B1/B3/B7 are the
right homes for the P2-2/P2-4/P2-11 fixes, P4-A4 is P2-6's fix, and P4-E1/E2/E3 turn the Pass-1
architectural seams into concrete refactors. The view-perf cluster (D1–D4) is the roadmap's pending
item and is worth doing regardless of this release. Ready for **Triage**.

# Release Triage — Ranked Ship-Gate

Cross-pass ranking of all findings (Passes 1–4, baseline `v1.3.1`). Full detail per finding in
`review-findings.md`. This is the go/no-go decision doc; the final call is the maintainer's.

---

> ## ⚠️ Status as of 2026-08-04 — the verdict below is HISTORICAL
>
> The ranking is kept as the record of what the review found and why it was ordered that way.
> It is **not** the current state of the code. Since it was written:
>
> - **Tier 1 — all 8 shipped** (each of P2-1…P2-7, P3-1 is referenced by a commit on `main`).
>   The NO-GO verdict is cleared.
> - **Tier 2 — 9 of 11 shipped.** Still open: **P2-8** and **P2-9** (batch failure
>   mis-reporting), blocked on a reliable repro. P2-8 is verifiable in the code today —
>   `BrewService.swift` still carries the `/Error: (\S+?):/` matcher the finding is about.
> - **Tier 3 — not audited item-by-item.** Treat it as the backlog it always was, not as a
>   list of known-open bugs; some entries were fixed in passing.
>
> Before acting on any single item here, check `git log` for its id and confirm against the
> code — a finding referenced by a commit is closed, an unreferenced one probably isn't.

---

## Verdict (as written, pre-fix)

**NO-GO as-is.** The release carries one security bug and several confirmed data-loss / wrong-state
bugs that reach ordinary users. Clearing **Tier 1 (8 items)** is the minimum bar to ship; Tier 2 is
strongly recommended in the same release or a fast point-release.

**Two root causes explain most of Tier 1:**
1. **Command strings built by interpolation** (`Shell` runs `/bin/sh -c "<string>"`) → injection + no
   cancellation/timeout. Fixing the Shell layer (argv array + a cancellation/timeout wrapper) knocks
   out P2-1, P2-7, and P3-1 together.
2. **No single owner of "installed/broken" state** (optimistic writes vs. reconciliation; two
   broken-state machines; three alert owners) → F2 stomp, bootstrap revert, false "up to date", lost
   alerts. Pass-1 F1/F3/F5 named these seams; Pass-4 B1/B3/E1 are the concrete refactors.

---

## 🔴 Tier 1 — MUST-FIX before release (blockers)

| # | Finding | Why it blocks | Fix home |
|---|---------|---------------|----------|
| 1 | **P2-1 shell injection** | Untrusted third-party tap token (trust deliberately disabled) + custom paths spliced unescaped into `sh -c` → arbitrary code execution on install/update/uninstall | Rework `Shell.createProcess` to argv-array `Process` (no shell) or a real POSIX-quoter; fix all callers. Land P4-B1 (`matches(anyOf:)`) alongside |
| 2 | **P2-2 install() wrong cask** | `install()` uses bare `vm.token` where all siblings use `fullToken` → silently installs the wrong (core) cask on a tap/core collision | One-line change; do it inside the P4-B1 consolidation |
| 3 | **P2-3 / F2 state stomp** | Stale `brew list` reconciliation forces a just-installed cask back to "not installed" (and re-flags just-updated apps as outdated) — visible, common | Serialize/guard the two writers; P4-B2/B3 are the refactor homes |
| 4 | **P2-4 bootstrap revert + corruption** | First-run: switching to your own brew is silently reverted to the annex; concurrent bootstrap can corrupt the annex tree | Single-flight `bootstrap.run()`; fold `hasBrokenInstall` into `Phase` (P4-E1); dedupe orchestration (P4-B3) |
| 5 | **P2-5 tap-cask deletion (data loss)** | One transient tap-fetch failure → `syncFromAPI` deletes *all* custom-tap casks from the DB (incl. installed) | Guard the delete: skip destructive prune when tap fetch failed / returned empty; make `fetchTapDTOs` failures visible (P3-12) |
| 6 | **P2-6 offline no-fallback** | Returning user, offline, stale catalog → whole catalog load throws → infinite shimmer all session though data is in SQLite | Fall back to DB when sync fails — **wire up the already-existing `hasCasks()`** (P4-A4) |
| 7 | **P2-7 hung brew wedges the queue** | `runProcessAsync` has no timeout/cancellation; one wedged brew (stalled sudo, lock, stall) permanently blocks *every* later install/update | Add `withTaskCancellationHandler` + timeout to the Shell continuation |
| 8 | **P3-1 silent unrecoverable hang** | `brew --version` runs with no timeout (the sibling function *does*); a hang leaves the app stuck at `phase=.checking` with no overlay/error/recovery — force-quit only | Same Shell timeout fix as #7 + a timeout on the validity probe |

*#7 and #8 are one fix family (Shell timeout+cancellation) and also mitigate P2-4's cancellation gap,
P2-18, and P3-21. #1 and #2 share the same fix home. So Tier 1 is ~5 focused pieces of work, not 8
independent ones.*

---

## 🟠 Tier 2 — Fast-follow (this release if time allows, else immediate point-release)

- **P3-2 non-atomic annex reinstall** — a failed reinstall destroys the working Homebrew (no
  temp-dir-then-swap). User-initiated + recoverable-by-retry, so not a hard blocker, but destructive.
  *(Borderline Tier 1 — promote if reinstall is a prominent action.)*
- **P2-11 notifications silently off on fresh install** — cheap fix (P4-B7 typed-accessor); high
  annoyance, low effort → good to bundle with Tier 1.
- **P3-3 false "All your apps are up to date"** when `refreshOutdated` failed — users silently miss
  updates; meaningful for an app-updater.
- **P2-12 uninstall wipes own data before a throwing step** — conditional (uninstall + Homebrew +
  no admin) but irreversible when hit.
- **P2-8 / P2-9 batch failure mis-reporting** — wrong/missing per-cask reasons; casks after a failure
  marked failed though fine.
- **P3-4 / F4 import shows success on failure** + its alert can't present on the migration screen;
  **P3-5 shared alert drops messages** — the "failure computed but never surfaced" cluster; unify the
  alert path (Pass-1 F5).
- **P2-13 synchronous DB open on the main actor at launch** — beachball on a slow disk.
- **P2-15 Brewfile regex drops `@`-versioned casks** — silent import loss + breaks Applite's own
  export→import round trip.
- **P2-10 activeTasks eviction by cask-identity** — a card can vanish / become uncancellable.

---

## ⚪️ Tier 3 — Backlog (post-release / roadmap)

- **Recovery UX** (Pass 3): P3-6 title-only alerts, P3-7 recovery button disabled-when-needed, P3-8
  `.brewMissing` wrong copy, P3-11 silent stale-brew drift, P3-10 orphan-on-quit (no SIGKILL).
- **Resource** (Pass 3): P3-9 cache never pruned on failure, P3-16 uninstall/askpass race, P3-17
  unbounded `activeTasks`.
- **Coverage-gap items** (Pass 3): P3-18/19 Sparkle re-entrancy + toggle desync, P3-20 askpass has no
  diagnostics, and the **latent upgrade landmines** P3-13 (FTS dropped by a future table rebuild) +
  P3-14 (`schemaVersion` dead) — *not urgent now, but gate the next schema change on them.*
- **Lower-severity correctness** (Pass 2): P2-16…P2-30 (mirror empty vars, proxy port/type, IN-clause
  chunking, `INSERT OR REPLACE` churn, `fatalError` recovery, non-exhaustive switch, etc.).
- **All of Pass 4 not already pulled into a Tier-1/2 fix**: remaining dead code (A1–A3, A5), the
  duplication tail (B4–B6, B8–B9), the 4 CLAUDE.md convention nits (C1–C4), the **view-perf cluster
  (D1–D4)** — this is the roadmap's standing "view-perf pending" item, worth its own focused pass —
  the altitude refactors (E1–E3, do E1 with Tier-1 #4), and accessibility (F1–F2).

---

## Effort read
Tier 1 is concentrated: ~2 fix families (Shell layer; state-ownership) cover 6 of 8. The Shell rework
is the biggest single piece (touches every brew caller) and the highest-value (security + hang +
queue-wedge in one). Recommend: do Tier 1 + the cheap Tier-2 wins (P2-11, P2-15) for the release,
schedule the rest.

## Coverage honesty
Not exercised anywhere in the review: real-device sudo/TCC dialog behavior on current macOS, and an
actual old-DB→new-schema upgrade run (P3-13/14 are read-only inferences). Recommend a manual pass on
both before shipping, plus re-running `Testing/applite_test.py` for the annex/external E2E rounds.

//
//  AnnexBrewManager.swift
//  Applite
//
//  Created by Milán Várady on 2023. 01. 14..
//

import Foundation
import OSLog

/// Installs and maintains Applite's own ("annex") Homebrew installation at
/// `~/Library/Application Support/Applite/Homebrew`.
///
/// Applite only installs **casks** (precompiled app binaries), so it needs neither a compiler
/// nor the Xcode Command Line Tools. The annex is a plain tarball extraction of Homebrew; brew
/// then runs in API mode (cask metadata over curl) with auto-update disabled (see `Shell`), which
/// keeps git — the one tool macOS won't provide without CLT — off the cask install path.
///
/// As of Homebrew 6.0.12 the CLT-free cask flow is handled entirely by brew itself: the fatal ARM
/// dev-tools check and the `xcrun -find` fallback went away in 6.0.10, and the FFI
/// quarantine/xattr/trash helpers (which need no Swift) became the default for all users in 6.0.12
/// (PR #23061), replacing the old `HOMEBREW_DEVELOPER`-gated path. So the annex is now an
/// unpatched, plain extraction that tracks `master` — kept current by the periodic refresh (see
/// `refreshAnnexBrew`), the same rolling source `brew update` pulls.
struct AnnexBrewManager {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: AnnexBrewManager.self)
    )

    /// Homebrew source tarball, extracted verbatim into the annex directory.
    ///
    /// Tracks `main` (no version pin) — the same rolling source `brew update` pulls — because the
    /// annex is no longer patched: brew 6.0.10+ handles CLT-free cask installs natively (see the
    /// `AnnexBrewManager` header and `Shell`). The periodic refresh keeps this current.
    ///
    /// **Must be `main`, not `master`.** Homebrew made `main` its default branch and on 2026-09-04
    /// (PR #23733) reduced `master` to a three-file stub: a `bin/brew` that prints "Homebrew's
    /// master branch is no longer supported" and exits 1 for every command except `brew update`.
    /// That stub's migration path is `git fetch` + `git checkout` against a real clone, which the
    /// annex can never satisfy — it is a tarball extraction with no `.git` at all — so there is no
    /// in-place recovery from pointing at `master`. It broke both paths at once: a clean install
    /// extracted 3 files and failed `verifyAnnexInstall`, and the non-destructive refresh overlaid
    /// the stub's `bin/brew` onto a working tree and bricked it.
    static let brewTarballURL = "https://github.com/Homebrew/brew/tarball/main"

    // MARK: - Annex install / refresh

    /// The shell command that fetches the Homebrew tarball and unpacks it into `directory`
    /// (the annex directory by default; a staging dir for an atomic clean reinstall).
    /// Shared by the clean install, the streaming first-run install, and the freshness refresh.
    static func annexExtractCommand(into directory: URL = BrewPaths.annexBrewDirectory) -> String {
        // `set -o pipefail` + `curl -fL`: without them a truncated download or an HTTP error body is
        // swallowed — the pipeline's exit status is tar's, so tar happily extracts a partial (or
        // garbage) tree and the command "succeeds" with a half-installed brew. `verifyAnnexInstall`'s
        // `brew --version` check won't catch that (it loads too little), so it only surfaces later as
        // a missing-file crash. `-f` fails on HTTP errors; pipefail propagates curl's exit through
        // the pipe. (macOS `/bin/sh` is bash, which supports `pipefail`.)
        "set -o pipefail; curl -fL \(brewTarballURL) | tar xz --strip 1 -C \(directory.quotedPath())"
    }

    /// Ensures the annex directory exists.
    ///
    /// - Parameter clean: When `true` the directory is deleted first (a pristine reinstall). When
    ///   `false` the tarball is unpacked *over* the existing tree, which overwrites brew's own
    ///   program files while leaving the runtime dirs (`Caskroom`, `Cellar`, `var`, cache)
    ///   untouched — this is what makes a freshness refresh safe for already-installed apps.
    static func prepareAnnexDirectory(clean: Bool) throws {
        if clean, FileManager.default.fileExists(atPath: BrewPaths.annexBrewDirectory.path) {
            Self.logger.info("Removing existing annex Homebrew directory for a clean install")
            try FileManager.default.removeItem(at: BrewPaths.annexBrewDirectory)
        }

        try FileManager.default.createDirectory(
            at: BrewPaths.annexBrewDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Verifies a brew executable actually runs and reports Homebrew (defaults to the annex's).
    static func verifyAnnexInstall(at executable: URL = BrewPaths.annexBrewExecutable) async throws {
        guard await BrewPaths.isBrewPathValid(at: executable) else {
            throw AnnexBrewError.invalidBrewInstallation
        }
    }

    /// Records "the annex tarball is current as of now" so the freshness check (see
    /// `HomebrewBootstrap.refreshAnnexIfStale`) doesn't immediately re-fetch after an install.
    static func stampAnnexRefreshed() {
        UserDefaults.standard.setValue(Date().timeIntervalSince1970, for: Preferences.annexLastRefreshDate)
    }

    /// Clean install of the annex brew: unpacks the tarball into a staging dir, verifies it, and
    /// only then atomically swaps it into place. Used by the "Reinstall" action.
    ///
    /// Staging-then-swap (P3-2): the old, working install is never touched until a fresh tree has
    /// been fully downloaded, extracted, and verified. A failure at any point (network drop, disk
    /// full, quit mid-extract) leaves the existing Homebrew intact instead of destroying it — the
    /// previous "wipe first, then download" order turned any transient failure into a dead install.
    static func installAnnexClean() async throws {
        Self.logger.info("Clean annex Homebrew install started")

        let fm = FileManager.default
        let finalDir = BrewPaths.annexBrewDirectory
        let parent = finalDir.deletingLastPathComponent()
        let stagingDir = parent.appending(path: "Homebrew.staging", directoryHint: .isDirectory)
        let backupDir = parent.appending(path: "Homebrew.old", directoryHint: .isDirectory)

        // 1. Extract into a clean staging dir and verify it — all before touching the live install.
        try? fm.removeItem(at: stagingDir)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        do {
            try await Shell.runShellScript(annexExtractCommand(into: stagingDir))
            try await verifyAnnexInstall(at: stagingDir.appendingPathComponent("bin/brew"))
        } catch {
            try? fm.removeItem(at: stagingDir)   // leave the existing install untouched
            throw error
        }

        // 2. Swap in the verified tree via fast same-volume renames; the only non-atomic gap is
        //    between two renames (sub-millisecond), and a failure there is rolled back.
        try? fm.removeItem(at: backupDir)
        if fm.fileExists(atPath: finalDir.path) {
            try fm.moveItem(at: finalDir, to: backupDir)
        }
        do {
            try fm.moveItem(at: stagingDir, to: finalDir)
        } catch {
            // Restore the previous install if the swap-in failed.
            if fm.fileExists(atPath: backupDir.path) {
                try? fm.moveItem(at: backupDir, to: finalDir)
            }
            throw error
        }
        try? fm.removeItem(at: backupDir)   // discard the old tree once the new one is in place

        BrewPaths.selectedBrewOption = .annex
        stampAnnexRefreshed()
        Self.logger.info("Clean annex Homebrew install done")
    }

    /// Re-fetches the Homebrew tarball over the existing annex without deleting it, keeping the
    /// program files current while preserving installed apps. No-op unless the annex is the
    /// selected brew. Replaces the git-based `brew update`, which can't run without CLT.
    static func refreshAnnexBrew() async throws {
        guard BrewPaths.selectedBrewOption == .annex else {
            Self.logger.info("Skipping annex refresh — annex is not the selected brew")
            return
        }

        Self.logger.info("Refreshing annex Homebrew (non-destructive overlay)")

        var refreshError: Error?
        do {
            try prepareAnnexDirectory(clean: false)
            try await Shell.runShellScript(annexExtractCommand())
            try await verifyAnnexInstall()
            stampAnnexRefreshed()
            Self.logger.info("Annex Homebrew refresh done")
        } catch {
            refreshError = error
        }

        // Prune regardless of the refresh outcome. This was the *only* prune site and it ran only on
        // full success, so repeated refresh failures + continued installs grew HOMEBREW_CACHE without
        // bound (P3-9). Best-effort: it logs and moves on if brew is unusable.
        await pruneAnnexCache()

        if let refreshError { throw refreshError }
    }

    /// Best-effort `brew cleanup --prune=all` on the annex's periodic refresh tick.
    ///
    /// Applite installs only casks, and a downloaded cask artifact (`dmg`/`pkg`/`zip`) is reused
    /// only for a same-version reinstall or an interrupted-download resume — for a self-updating
    /// app store it's effectively write-once, read-never, so we drop *all* cached downloads to
    /// reclaim disk that annex users never asked brew to hold. This runs as a silent maintenance
    /// step, so a failure here must never fail the refresh — we log and move on. Caller has already
    /// verified the annex is the selected, working brew (see `refreshAnnexBrew`).
    static func pruneAnnexCache() async {
        do {
            try await Shell.runBrewCommand(["cleanup", "--prune=all"])
            Self.logger.info("Pruned annex Homebrew cache")
        } catch {
            Self.logger.warning("Annex cache prune failed (non-fatal): \(error.localizedDescription)")
        }
    }
}

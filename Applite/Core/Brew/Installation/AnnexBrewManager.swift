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

    /// Message shown when brew path is broken
    static let brokenPathOrInstallMessage = "Error. Broken brew path, or damaged installation. Check brew path in settings, or try reinstalling Homebrew (Manage Homebrew->Reinstall)"

    /// Homebrew source tarball, extracted verbatim into the annex directory.
    ///
    /// Tracks `master` (no version pin) — the same rolling source `brew update` pulls — because the
    /// annex is no longer patched: brew 6.0.10+ handles CLT-free cask installs natively (see the
    /// `AnnexBrewManager` header and `Shell`). The periodic refresh keeps this current.
    static let brewTarballURL = "https://github.com/Homebrew/brew/tarball/master"

    // MARK: - Annex install / refresh

    /// The shell command that fetches the Homebrew tarball and unpacks it over the annex directory.
    /// Shared by the clean install, the streaming first-run install, and the freshness refresh.
    static func annexExtractCommand() -> String {
        // `set -o pipefail` + `curl -fL`: without them a truncated download or an HTTP error body is
        // swallowed — the pipeline's exit status is tar's, so tar happily extracts a partial (or
        // garbage) tree and the command "succeeds" with a half-installed brew. `verifyAnnexInstall`'s
        // `brew --version` check won't catch that (it loads too little), so it only surfaces later as
        // a missing-file crash. `-f` fails on HTTP errors; pipefail propagates curl's exit through
        // the pipe. (macOS `/bin/sh` is bash, which supports `pipefail`.)
        "set -o pipefail; curl -fL \(brewTarballURL) | tar xz --strip 1 -C \(BrewPaths.annexBrewDirectory.quotedPath())"
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

    /// Verifies the annex brew executable actually runs and reports Homebrew.
    static func verifyAnnexInstall() async throws {
        guard await BrewPaths.isBrewPathValid(at: BrewPaths.annexBrewExecutable) else {
            throw AnnexBrewError.invalidBrewInstallation
        }
    }

    /// Records "the annex tarball is current as of now" so the freshness check (see
    /// `HomebrewBootstrap.refreshAnnexIfStale`) doesn't immediately re-fetch after an install.
    static func stampAnnexRefreshed() {
        UserDefaults.standard.setValue(Date().timeIntervalSince1970, for: Preferences.annexLastRefreshDate)
    }

    /// Clean install of the annex brew: wipes any existing annex, unpacks the tarball, verifies,
    /// and selects it as the active brew. Used by the "Reinstall" action.
    static func installAnnexClean() async throws {
        Self.logger.info("Clean annex Homebrew install started")

        try prepareAnnexDirectory(clean: true)
        try await Shell.runAsync(annexExtractCommand())
        try await verifyAnnexInstall()

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
        try prepareAnnexDirectory(clean: false)
        try await Shell.runAsync(annexExtractCommand())
        try await verifyAnnexInstall()
        stampAnnexRefreshed()
        Self.logger.info("Annex Homebrew refresh done")
    }
}

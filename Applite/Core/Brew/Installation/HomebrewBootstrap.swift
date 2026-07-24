//
//  HomebrewBootstrap.swift
//  Applite
//
//  Created by Milán Várady on 2025.07.06.
//

import Foundation
import OSLog

/// Resolves a usable Homebrew on launch — with **no onboarding and no Xcode Command Line Tools**.
///
/// Replaces the old first-run setup flow. On launch it honors an existing/selected brew if there
/// is one, otherwise silently installs Applite's own annex brew from a tarball while the (DB-backed)
/// catalog stays browsable underneath. The `phase` drives a non-dismissable overlay over `ContentView`.
@MainActor
@Observable
final class HomebrewBootstrap {
    enum Phase: Equatable {
        /// Detecting an existing brew.
        case checking
        /// Installing the annex brew (drives the progress overlay).
        case installing
        /// The annex was just installed; brew is usable, but the success overlay stays up until the
        /// user acknowledges it (so they learn setup finished and can opt into their own brew).
        case installed
        /// A valid brew is selected; the app can use brew. No overlay.
        case ready
        /// Bootstrap failed; the overlay shows the message plus Retry and the "use my own brew" escape hatch.
        case failed(String)
    }

    private(set) var phase: Phase = .checking

    /// Whether brew is usable — either a pre-existing brew (`.ready`) or a freshly installed annex
    /// still awaiting the user's acknowledgment (`.installed`). Data loading gates on this.
    var isBrewReady: Bool {
        phase == .ready || phase == .installed
    }

    /// Latest streamed line from the tarball install, shown in the overlay.
    private(set) var statusLine: String = ""

    /// Bumped to ask `ContentView` to re-run the bootstrap+load (`.task(id:)`). Bumping cancels
    /// any in-flight annex install (SwiftUI cancels the previous task) — this is how the "use my
    /// own brew" escape hatch and the Retry button interrupt a running install.
    private(set) var attempt = 0

    /// Requests a fresh bootstrap+load pass. The escape hatch calls this after the user has picked
    /// a valid brew in the embedded path selector; Retry calls it after a failure.
    func requestReload() {
        attempt += 1
    }

    /// Dismisses the post-install success overlay. Brew was already usable in `.installed`, so this
    /// just hides the overlay; no reload needed.
    func acknowledgeInstall() {
        if phase == .installed { phase = .ready }
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: HomebrewBootstrap.self)
    )

    /// Resolves brew, installing the annex only as a last resort. Safe to call again (Retry).
    func run() async {
        phase = .checking

        // 1. Honor a working selection first — covers existing users, custom paths, and a prior
        //    annex. Never overrides a brew the user is already pointed at.
        if await BrewPaths.isSelectedBrewPathValid() {
            Self.logger.info("Selected brew path is valid — ready")
            phase = .ready
            return
        }

        // 2. Detect an existing brew anywhere (arch defaults, then PATH).
        if let detected = await BrewPaths.detectHomebrew(setPathOption: true) {
            Self.logger.info("Detected existing brew (\(String(describing: detected))) — ready")
            phase = .ready
            return
        }

        // 3. A prior annex install that just isn't the selected option yet.
        if await BrewPaths.isBrewPathValid(at: BrewPaths.annexBrewExecutable) {
            Self.logger.info("Found existing annex brew — selecting it")
            BrewPaths.selectedBrewOption = .annex
            phase = .ready
            return
        }

        // 4. No brew anywhere → install Applite's own annex (CLT-free).
        await installAnnex()
    }

    /// Streams the annex tarball install, surfacing progress lines to the overlay.
    func installAnnex() async {
        Self.logger.info("No brew found — installing annex Homebrew")
        phase = .installing
        statusLine = ""

        do {
            try AnnexBrewManager.prepareAnnexDirectory(clean: true)

            for try await line in Shell.stream(AnnexBrewManager.annexExtractCommand(), pty: true) {
                statusLine = line
            }

            // If the user bailed to their own brew mid-install, don't override their choice.
            try Task.checkCancellation()

            try await AnnexBrewManager.verifyAnnexInstall()
            BrewPaths.selectedBrewOption = .annex
            AnnexBrewManager.stampAnnexRefreshed()

            // Install brew's Portable Ruby now (serially, while the overlay is still up) so later
            // commands — and an eager user install — can't race its one-time setup.
            await primeRuby()

            Self.logger.info("Annex Homebrew installed — awaiting acknowledgment")
            // Keep the overlay up (success state) until the user dismisses it, rather than flashing
            // and vanishing when the install is quick.
            phase = .installed
        } catch {
            // Cancellation means the escape hatch/Retry superseded this install — stay quiet and
            // leave the selection alone; the follow-up bootstrap pass sets the real phase.
            if Task.isCancelled { return }
            Self.logger.error("Annex install failed: \(error.localizedDescription)")
            phase = .failed(Self.setupFailureMessage(for: error))
        }
    }

    /// The message the setup overlay shows on a failed annex install. The overwhelmingly common
    /// failure — no network — gets a plain-language line instead of the raw `curl | tar` command
    /// dump (which a non-technical user can't act on); the raw output still lands in the log above.
    /// Any other failure falls through to `localizedDescription` so support can still read it.
    private static func setupFailureMessage(for error: Error) -> String {
        // curl network exit codes: 6 = couldn't resolve host, 7 = couldn't connect, 28 = timeout.
        let isOffline: Bool = {
            if error is URLError { return true }
            if case let ShellError.nonZeroExit(_, code, _) = error { return [6, 7, 28].contains(code) }
            if case ShellError.timedOut = error { return true }
            return false
        }()

        if isOffline {
            return String(
                localized: "No internet connection. Applite needs to connect to the internet to download Homebrew and finish setting up. Check your connection and try again.",
                comment: "Setup overlay message when the Homebrew download fails because the machine is offline"
            )
        }
        return error.localizedDescription
    }

    /// Boots brew's Portable Ruby once by running a single command serially.
    ///
    /// On a fresh annex the VM/machine's system Ruby is usually too old, so the first brew command
    /// runs a one-time `brew vendor-install ruby`. That step takes a lock — if two brew processes
    /// hit it at once (e.g. the concurrent installed/outdated queries) they collide with
    /// "already locked" and one fails. Priming it here, serially, makes every later brew call safe.
    private func primeRuby() async {
        statusLine = "Preparing components…"
        do {
            // `brew list --cask` is a Ruby command (so it triggers the Portable Ruby install) but
            // only reads the local Caskroom — no network/git needed.
            _ = try await Shell.runBrewCommand(["list", "--cask"])
        } catch {
            // Non-fatal: a real failure resurfaces in the subsequent data load with full output.
            Self.logger.error("Ruby prime failed: \(error.localizedDescription)")
        }
    }

    /// Silent background maintenance: if the annex is stale, re-fetch the tarball over it. Runs
    /// only for the annex (`.annex`) and only after the UI is up, so it never blocks launch.
    /// This stands in for brew's git-based self-update, which can't run without CLT.
    func refreshAnnexIfStale() async {
        guard BrewPaths.selectedBrewOption == .annex else { return }

        let last = UserDefaults.standard.value(for: Preferences.annexLastRefreshDate)
        let frequency = UserDefaults.standard.value(for: Preferences.annexUpdateFrequency)
        let now = Date().timeIntervalSince1970

        guard now - last >= frequency.timeInterval else { return }

        Self.logger.info("Annex is stale — refreshing in the background")
        do {
            // `refreshAnnexBrew` stamps the refresh date on success.
            try await AnnexBrewManager.refreshAnnexBrew()
            Self.logger.info("Background annex refresh complete")
        } catch {
            Self.logger.error("Background annex refresh failed: \(error.localizedDescription)")
        }
    }
}

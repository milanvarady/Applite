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
        /// The user selected their *own* (non-annex) brew and it can't be found. Distinct from
        /// `.failed` so we can name the missing path and never silently install/switch to the annex
        /// over their explicit choice.
        case brewMissing(path: String)
    }

    /// The single source of truth for "can Applite use brew". Every surface that reacts to a
    /// broken/missing brew derives from this — there is no parallel flag anywhere (E1/F1).
    private(set) var phase: Phase = .checking

    /// Whether brew is usable — either a pre-existing brew (`.ready`) or a freshly installed annex
    /// still awaiting the user's acknowledgment (`.installed`). Data loading gates on this.
    var isBrewReady: Bool {
        phase == .ready || phase == .installed
    }

    /// Whether the non-dismissable setup card should cover the window. It's up for the annex install
    /// *and* for every broken outcome, which is why brokenness needs no second UI surface of its own:
    /// the card already shows the real message plus Retry, Troubleshooting and the own-brew escape
    /// hatch. Lives here, next to `phase`, so `ContentView` doesn't re-derive it.
    var needsSetupOverlay: Bool {
        switch phase {
        case .installing, .installed, .failed, .brewMissing: true
        case .checking, .ready: false
        }
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

    /// Extra re-checks of the user's *own* selected brew before declaring it missing. A single
    /// `brew --version` probe can fail transiently (cold start, machine under load), and we must
    /// not throw a "Homebrew not found" overlay at a user whose brew is actually fine. Only runs
    /// when their brew already looks invalid, so it adds no latency to the healthy path.
    private static let selectedBrewRevalidationRetries = 2
    private static let selectedBrewRevalidationDelay: Duration = .milliseconds(400)

    /// The in-flight bootstrap pass and the `attempt` generation it was started for. Used to make
    /// `run()` single-flight so a second entry point (`loadData(forceSync:)` from ⌘R / Settings)
    /// can't kick off a bootstrap concurrently with the launch one — two `installAnnex()` passes
    /// would both `prepareAnnexDirectory(clean:)`, one wiping the tree the other extracts into.
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var runningAttempt = -1

    /// Resolves brew, installing the annex only as a last resort. Safe to call again (Retry).
    ///
    /// Single-flight, generation-aware:
    /// - A concurrent call for the *same* `attempt` (e.g. `loadData` overlapping the launch pass)
    ///   awaits the in-flight pass instead of starting a second, concurrent one.
    /// - A call after `attempt` was bumped (Retry / the "use my own brew" escape hatch) supersedes
    ///   the old pass: it cancels it, waits for it to finish unwinding (so the annex directory is
    ///   never touched by two passes at once), then starts fresh.
    func run() async {
        if let runTask, runningAttempt == attempt {
            await runTask.value
            return
        }

        // A newer generation supersedes any still-running older pass.
        runTask?.cancel()
        await runTask?.value

        let started = attempt
        let task = Task { await self.runBootstrap() }
        runningAttempt = started
        runTask = task
        await task.value

        // Only clear if we're still the current pass (a newer generation may have replaced us).
        if runningAttempt == started { runTask = nil }
    }

    /// The actual bootstrap sequence. Runs inside the `run()`-owned `Task`, so `Task.isCancelled`
    /// here reflects `run()` cancelling it when a newer generation supersedes this pass.
    private func runBootstrap() async {
        phase = .checking

        // 1. Honor a working selection first — covers existing users, custom paths, and a prior
        //    annex. Never overrides a brew the user is already pointed at.
        if await BrewPaths.isSelectedBrewPathValid() {
            Self.logger.info("Selected brew path is valid — ready")
            phase = .ready
            return
        }

        // 1b. The user is pointed at their *own* brew (not the annex) and step 1 said it's invalid.
        //     We must NOT fall through to the steps below: detect-and-switch (2) would silently
        //     move them to a *different* brew if theirs is gone, and adopt/install-annex (3, 4)
        //     would switch to the annex — all three orphan their installed apps, the very bug
        //     we're preventing. What we CAN safely do is re-check their *own* path, since a
        //     `brew --version` probe fails transiently now and then; only after it stays invalid
        //     do we surface it (the annex path gets an equivalent recheck at step 3).
        if BrewPaths.selectedBrewOption != .annex {
            for retry in 1...Self.selectedBrewRevalidationRetries {
                try? await Task.sleep(for: Self.selectedBrewRevalidationDelay)
                if Task.isCancelled { return }  // escape hatch / Retry superseded us
                if await BrewPaths.isSelectedBrewPathValid() {
                    Self.logger.info("Selected brew validated on retry \(retry) — ready")
                    phase = .ready
                    return
                }
            }
            let path = BrewPaths.currentBrewExecutable.path(percentEncoded: false)
            Self.logger.error("Selected non-annex brew still invalid at \(path) after \(Self.selectedBrewRevalidationRetries) retries")
            phase = .brewMissing(path: path)
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

        // 3b. An annex tree is on disk but its brew won't run, and it still holds apps the user
        //     installed. Re-extract the tarball *over* it — the same non-destructive overlay the
        //     periodic refresh uses — rather than dropping through to step 4, whose `clean: true`
        //     deletes the entire annex directory and with it `Caskroom` and `Cellar`. That would
        //     bring brew back working but knowing about none of the user's apps: the `.app` files
        //     survive in the applications folder while Applite's Installed list goes empty and
        //     updates and uninstalls stop working for every one of them.
        //
        //     This is the recovery path for the 2026-09-04 `master`-branch breakage (see
        //     `AnnexBrewManager.brewTarballURL`). The refresh overlaid a three-file stub onto a
        //     working tree, so only `bin/brew` is damaged — the rest of Homebrew is still there,
        //     and re-extracting is enough to make it run again.
        if AnnexBrewManager.annexHasInstalledApps() {
            if await repairAnnex() { return }
            // Cancelled by Retry or the escape hatch: leave the tree alone and let the superseding
            // pass decide. Falling through would hand it to `installAnnex`, which wipes the
            // directory *before* it checks for cancellation.
            if Task.isCancelled { return }
        }

        // 4. No brew anywhere → install Applite's own annex (CLT-free).
        await installAnnex()
    }

    /// Repairs a broken annex in place, keeping everything the user has installed.
    ///
    /// Extracts the tarball over the existing tree, so brew's own program files are replaced while
    /// the runtime directories (`Caskroom`, `Cellar`, `var`, cache) are left untouched, then
    /// verifies the result. Returns `true` when it produced a working brew (or when the user
    /// switched to their own brew while it ran), `false` when the caller should fall back to the
    /// destructive clean install — which loses the Caskroom, but at least leaves a usable Homebrew.
    ///
    /// Unlike `installAnnex` this ends in `.ready`, not `.installed`: the user didn't ask to install
    /// anything, so there's no success card worth making them dismiss.
    private func repairAnnex() async -> Bool {
        Self.logger.info("Annex brew is invalid but has installed apps — repairing in place")
        phase = .installing
        statusLine = ""

        do {
            try AnnexBrewManager.prepareAnnexDirectory(clean: false)

            for try await line in Shell.streamShellScript(AnnexBrewManager.annexExtractCommand(), pty: true) {
                statusLine = line
            }

            try Task.checkCancellation()
            try await AnnexBrewManager.verifyAnnexInstall()
        } catch {
            if Task.isCancelled { return false }
            Self.logger.error("In-place annex repair failed: \(error.localizedDescription)")
            return false
        }

        // Same guard as `installAnnex`: don't override a brew the user pointed Applite at while the
        // repair was downloading.
        if BrewPaths.selectedBrewOption != .annex, await BrewPaths.isSelectedBrewPathValid() {
            Self.logger.info("User selected their own valid brew during the repair — honoring it")
            phase = .ready
            return true
        }

        BrewPaths.selectedBrewOption = .annex
        AnnexBrewManager.stampAnnexRefreshed()

        // Prime Ruby for the same reason `installAnnex` does. The overlay extract replaces
        // `Library/Homebrew/vendor/bundle` (though not the runtime-installed portable Ruby, which
        // isn't in the tarball), so a brew whose version moved can still run its one-time gem
        // setup on the next command — and that takes a lock the data load's concurrent
        // installed/outdated queries would collide on.
        await primeRuby()

        Self.logger.info("Annex Homebrew repaired in place — installed apps preserved")
        phase = .ready
        return true
    }

    /// Streams the annex tarball install, surfacing progress lines to the overlay.
    func installAnnex() async {
        Self.logger.info("No brew found — installing annex Homebrew")
        phase = .installing
        statusLine = ""

        do {
            try AnnexBrewManager.prepareAnnexDirectory(clean: true)

            for try await line in Shell.streamShellScript(AnnexBrewManager.annexExtractCommand(), pty: true) {
                statusLine = line
            }

            // If the user bailed to their own brew mid-install, don't override their choice.
            try Task.checkCancellation()

            try await AnnexBrewManager.verifyAnnexInstall()

            // Don't clobber a choice the user made *while* the annex was downloading. The Settings
            // "switch to my own brew" path doesn't bump `attempt` (so it doesn't cancel us via the
            // check above); if they've since pointed Applite at their own, now-valid brew, honor it
            // instead of silently switching them to the annex and orphaning their apps.
            if BrewPaths.selectedBrewOption != .annex, await BrewPaths.isSelectedBrewPathValid() {
                Self.logger.info("User selected their own valid brew during annex install — honoring it")
                phase = .ready
                return
            }

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

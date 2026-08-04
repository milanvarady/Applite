//
//  CaskManager.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 04..
//

import Foundation
import OSLog
import SwiftUI

typealias CaskId = String
typealias TapId = String
typealias BrewAnalyticsDictionary = [CaskId: Int]

/// Thin coordinator that owns the data loader, registry, and brew service.
/// Views access it via `@Environment(CaskManager.self)`.
@Observable
@MainActor
final class CaskManager {
    private let dataLoader: CaskDataLoader
    private let registry: CaskViewModelRegistry
    private let brewService: BrewService

    /// Resolves brew on launch (detect existing / install annex) without onboarding or CLT.
    /// `ContentView` observes `bootstrap.phase` to show the install sheet.
    let bootstrap = HomebrewBootstrap()

    /// Categories shown in the sidebar and Discover view.
    /// Initialized synchronously from the bundled `categories.json` with empty `casks`
    /// arrays so the UI renders structure from launch; replaced with resolved view models
    /// after `loadCatalogData()` finishes. `CategoryLoadResult` equality is id-based, so
    /// this assignment is invisible to `selection` and to SwiftUI's identity tracking —
    /// the cask cards inside each section just flip from shimmer placeholders to real data.
    private(set) var categories: [CategoryLoadResult]

    private(set) var taps: [TapLoadResult] = []

    /// True while brew CLI is being queried for installed/outdated state.
    /// Catalog (categories/taps) is independent and lights up before this flips false.
    private(set) var isResolvingInstalledState: Bool = false

    /// True while a manual catalog refresh is running (toolbar action).
    private(set) var isRefreshingCatalog: Bool = false

    /// True when the last `brew outdated` check failed (or couldn't run). `UpdateView` reads this so
    /// an empty outdated list shows "couldn't check for updates" instead of a false "all up to date"
    /// when the check never actually ran (P3-3).
    private(set) var outdatedRefreshFailed: Bool = false

    /// The main window's single alert surface — brew failures, catalog/load failures and errors
    /// raised by views all queue here, and `ContentView` presents it once at the window root.
    /// Windows that can't see that root (Settings, the uninstaller) own a local one instead.
    let alert: AlertManager

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: CaskManager.self)
    )

    // MARK: - Convenience Forwarding

    var installedViewModels: [CaskViewModel] { registry.installedViewModels }
    var outdatedViewModels: [CaskViewModel] { registry.outdatedViewModels }
    /// Sort-free counts for sidebar badges (see registry) — avoids sorting the whole registry just
    /// to render a number.
    var installedCount: Int { registry.installedCount }
    var outdatedCount: Int { registry.outdatedCount }
    var activeTasks: [ActiveBrewTask] { brewService.activeTasks }
    var batchProgress: BatchProgress? { brewService.batchProgress }

    /// One-shot navigation request from deep views (e.g. the "See Active Tasks" button on a
    /// batched app card) to the `ContentView`, which applies it to its sidebar selection and
    /// resets this to nil. Lives here because `CaskManager` is the shared environment object
    /// every card already holds, so no extra wiring is needed.
    var requestedTab: SidebarItem?

    // MARK: - Init

    init(
        dataLoader: CaskDataLoader? = nil,
        registry: CaskViewModelRegistry? = nil,
        brewService: BrewService? = nil
    ) {
        let reg = registry ?? CaskViewModelRegistry()
        self.registry = reg
        self.dataLoader = dataLoader ?? CaskDataLoader(registry: reg)
        // One alert instance for the whole window: hand it to the brew service rather than letting
        // that layer keep a second one (an injected service brings its own — tests don't present).
        let alert = brewService?.alert ?? AlertManager()
        self.alert = alert
        self.brewService = brewService ?? BrewService(alert: alert)
        self.categories = Self.loadInitialCategories()

        // An operation that finds the brew path invalid re-resolves brew through `bootstrap` — the
        // one owned "is brew usable" state — instead of handling a broken brew its own way (E1/F1).
        let bootstrap = self.bootstrap
        self.brewService.recoverBrew = {
            await bootstrap.run()
            return bootstrap.isBrewReady
        }
    }

    /// Loads the category list (cached remote copy → bundled fallback) and returns placeholder
    /// `CategoryLoadResult`s (no resolved casks). Lets the sidebar and Discover section structure
    /// render before stage 1 completes — including any last-known-good remote curation. Returns
    /// `[]` on total failure; the catalog load will repopulate it later.
    private static func loadInitialCategories() -> [CategoryLoadResult] {
        CategoryProvider.loadCategories()
            .map { CategoryLoadResult(id: $0.id, sfSymbol: $0.sfSymbol, casks: []) }
    }
    
    // MARK: - Registry Forwarding
    
    /// Resolves import tokens to view models via the DB (creates them if not already live), so an
    /// imported app list installs casks the user has never opened — not just ones already on screen.
    func resolveViewModels(forTokens tokens: Set<CaskId>) async throws -> [CaskViewModel] {
        try await dataLoader.viewModels(forTokens: tokens)
    }

    // MARK: - Brew Operation Forwarding

    func install(_ cask: CaskViewModel) {
        brewService.install(cask)
    }

    func uninstall(_ cask: CaskViewModel, zap: Bool = false) {
        brewService.uninstall(cask, zap: zap)
    }

    func update(_ cask: CaskViewModel) {
        brewService.update(cask)
    }

    func reinstall(_ cask: CaskViewModel) {
        brewService.reinstall(cask)
    }

    func cancel(_ cask: CaskViewModel) {
        brewService.cancel(cask)
    }

    func cancelBatch() {
        brewService.cancelBatch()
    }

    func dismissFailure(_ cask: CaskViewModel) {
        brewService.dismissFailure(cask)
    }

    func cancelAllAndWait() async {
        await brewService.cancelAllAndWait()
    }

    func installAll(_ casks: [CaskViewModel]) {
        brewService.installAll(casks)
    }

    func updateAll(_ casks: [CaskViewModel]) {
        brewService.updateAll(casks)
    }

    func getAdditionalInfoForCask(_ cask: CaskViewModel) async throws -> CaskAdditionalInfo {
        try await brewService.getAdditionalInfoForCask(cask)
    }

    // MARK: - Search Forwarding

    func search(query: String) async throws -> [CaskViewModel] {
        try await dataLoader.search(query: query)
    }
    
    // MARK: - Data Loading

    /// Buttons for a load-failure alert. These used to live in a hand-rolled `.alert` in
    /// `ContentView` — the only consumer that bypassed `.alertManager(_:)` — which is why
    /// `AlertManager`'s action fields went unused there (F5). Now the alert carries its own buttons,
    /// so every surface goes through the same modifier.
    private var loadFailureActions: [AppAlert.Action] {
        [
            AppAlert.Action("Retry") { [weak self] in
                Task { await self?.loadData() }
            },
            AppAlert.Action("Quit", role: .destructive) {
                NSApplication.shared.terminate(nil)
            },
            .ok
        ]
    }

    /// Launch entry point. Loads the brew-independent catalog immediately (so the UI lights up
    /// even while the annex is still installing), resolves brew via `bootstrap`, then loads the
    /// installed/outdated state once a valid brew is `.ready`. Finally kicks a silent annex
    /// freshness check. Any non-ready outcome leaves `bootstrap.phase` broken, which is the single
    /// surface for it — the install sheet `ContentView` shows for `.installing` also covers every
    /// failure, so nothing else has to react here.
    func bootstrapAndLoad() async {
        Self.logger.info("Bootstrap + load started")

        // Defer the catalog error: if the brew bootstrap also fails (same offline root cause), the
        // setup overlay is the single error surface — the catalog alert must not stack on it. Only
        // raise it below, once brew is ready and the overlay won't appear.
        let catalogError = await loadCatalog()
        await bootstrap.run()

        if bootstrap.isBrewReady {
            if let catalogError {
                alert.show(error: catalogError, title: "Couldn't load app catalog", actions: loadFailureActions)
            }
            await loadInstalledState()
            await bootstrap.refreshAnnexIfStale()
        } else if case .failed(let message) = bootstrap.phase {
            Self.logger.error("Bootstrap failed: \(message)")
        } else if case .brewMissing(let path) = bootstrap.phase {
            Self.logger.error("Selected brew missing at \(path)")
        }
    }

    /// Explicit reload used by the ⌘R menu action, the Settings "Refresh Catalog" prompt, and the
    /// load-failure alert's retry. Reloads the catalog, then — if the selected brew is valid — the
    /// installed/outdated state; otherwise re-runs `bootstrap` to try to recover, leaving the
    /// resulting `bootstrap.phase` to surface a brew that's genuinely unusable.
    func loadData(forceSync: Bool = false) async {
        Self.logger.info("Starting data load process (forceSync: \(forceSync))")

        if forceSync { isRefreshingCatalog = true }
        defer { if forceSync { isRefreshingCatalog = false } }

        // Defer the catalog error (see `bootstrapAndLoad`): a forced ⌘R sync while brew is also
        // unusable and offline would otherwise stack the catalog alert on the setup overlay. Raise
        // it only on the branches where brew is valid/recovered and no overlay will show.
        let catalogError = await loadCatalog(forceSync: forceSync)

        if await BrewPaths.isSelectedBrewPathValid() {
            if let catalogError {
                alert.show(error: catalogError, title: "Couldn't load app catalog", actions: loadFailureActions)
            }
            await loadInstalledState()
            return
        }

        // Selected brew is invalid — attempt recovery (detect existing / reinstall annex).
        await bootstrap.run()

        guard bootstrap.isBrewReady else {
            // Brew is genuinely unusable. `bootstrap` is now in `.failed`/`.brewMissing`, so
            // ContentView is already showing the setup overlay (real message + Retry +
            // Troubleshooting + "use your own Homebrew"). That phase is the single surface for a
            // broken brew, so don't stack an alert on it — the catalog error is dropped here.
            let versionOutput = (try? await Shell.runBrewCommand(["--version"])) ?? "n/a"
            Self.logger.error(
                """
                Cask load failure. Reason: selected brew path seems invalid and recovery failed.
                Brew executable path: \(BrewPaths.currentBrewExecutable.path(percentEncoded: false))
                brew --version output: \(versionOutput)
                """
            )
            return
        }

        // Recovered — the catalog alert is now the only possible surface, so raise it.
        if let catalogError {
            alert.show(error: catalogError, title: "Couldn't load app catalog", actions: loadFailureActions)
        }
        await loadInstalledState()
    }

    /// Stage 1: catalog (categories + taps) from the local DB — fast, no brew CLI dependency.
    ///
    /// Returns the failure (or `nil` on success) instead of surfacing it directly, so the caller
    /// can decide *whether* to raise the alert: on launch/recovery a catalog failure often shares
    /// its root cause (offline) with a brew bootstrap failure, and the setup overlay must be the
    /// single error surface — the alert can't stack on top. Every caller currently defers, so this
    /// only logs and returns the error.
    @discardableResult
    private func loadCatalog(forceSync: Bool = false) async -> Error? {
        do {
            // Animate the placeholder→full transition so cask cards cross-fade into place
            // rather than swapping instantly mid-shimmer-cycle.
            let catalog = try await dataLoader.loadCatalogData(forceSync: forceSync)
            withAnimation(.easeInOut(duration: 0.25)) {
                self.categories = catalog.categories
                self.taps = catalog.taps
            }
            return nil
        } catch {
            Self.logger.error("Catalog load failure. Reason: \(error.localizedDescription)")
            return error
        }
    }

    /// Stage 2: installed/outdated state from the brew CLI (slow). Updates the registry reactively,
    /// so view models already on screen flip their flags without rebuilding the catalog views.
    private func loadInstalledState() async {
        self.isResolvingInstalledState = true
        defer { self.isResolvingInstalledState = false }

        do {
            // Run the refresh on the serial brew queue so its `brew list`/`outdated` snapshot can't
            // interleave with — and then revert — a concurrent install/update's optimistic state
            // write (F2 / P2-3 dual-writer stomp).
            //
            // Within the queue slot the two calls stay serial, not concurrent: on a fresh annex the
            // first brew command triggers a one-time `brew vendor-install ruby`, and two brews racing
            // that lock fail with "already locked". Bootstrap primes Ruby up front, but keep these
            // ordered as a second line of defense.
            try await brewService.runSerialized {
                try await self.dataLoader.refreshInstalled()
                // Outdated is a nested best-effort step: if it fails, keep the (good) installed state
                // and just flag the failure, so UpdateView shows "couldn't check" instead of a false
                // "all up to date" (P3-3).
                do {
                    try await self.dataLoader.refreshOutdated()
                    self.outdatedRefreshFailed = false
                } catch {
                    self.outdatedRefreshFailed = true
                    Self.logger.error("Outdated refresh failed: \(error.localizedDescription)")
                }
            }
            Self.logger.info("Installed/outdated state loaded successfully!")
        } catch {
            // Installed refresh itself failed — outdated state is unknown too, so don't let
            // UpdateView claim everything is up to date.
            self.outdatedRefreshFailed = true
            alert.show(error: error, title: "Couldn't load installed apps", actions: loadFailureActions)
            Self.logger.error("Installed-state load failure. Reason: \(error.localizedDescription)")
        }
    }

    /// Refreshes the list of outdated casks (the toolbar "Refresh" action and UpdateView's retry).
    /// Serialized behind the brew queue (like `loadInstalledState`) so it can't race an install's
    /// optimistic write, and updates `outdatedRefreshFailed` so the empty-state UI stays accurate.
    func refreshOutdated() async throws {
        do {
            try await brewService.runSerialized {
                try await self.dataLoader.refreshOutdated()
            }
            outdatedRefreshFailed = false
        } catch {
            outdatedRefreshFailed = true
            throw error
        }
    }

}

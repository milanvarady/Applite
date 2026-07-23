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

    /// True when the selected brew path failed validation on the last `loadData()`.
    /// Views read this to swap in `BrokenInstallView` for the home tab.
    private(set) var hasBrokenInstall: Bool = false

    /// Alert surface for catalog load/refresh failures. Mirrors the `BrewService.alert`
    /// pattern so views can bind directly without owning load-error state.
    var loadAlert = AlertManager()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: CaskManager.self)
    )

    // MARK: - Convenience Forwarding

    var installedViewModels: [CaskViewModel] { registry.installedViewModels }
    var outdatedViewModels: [CaskViewModel] { registry.outdatedViewModels }
    var activeTasks: [ActiveBrewTask] { brewService.activeTasks }
    var batchProgress: BatchProgress? { brewService.batchProgress }
    var alert: AlertManager { brewService.alert }

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
        self.brewService = brewService ?? BrewService()
        self.categories = Self.loadInitialCategories()
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

    /// Launch entry point. Loads the brew-independent catalog immediately (so the UI lights up
    /// even while the annex is still installing), resolves brew via `bootstrap`, then loads the
    /// installed/outdated state once a valid brew is `.ready`. Finally kicks a silent annex
    /// freshness check. The install sheet (shown by `ContentView` while `bootstrap` is
    /// `.installing`) covers the app during step 2 — `hasBrokenInstall` is never set here, so
    /// `BrokenInstallView` can't flash during a normal first-run install.
    func bootstrapAndLoad() async {
        Self.logger.info("Bootstrap + load started")

        await loadCatalog()
        await bootstrap.run()

        if bootstrap.isBrewReady {
            hasBrokenInstall = false
            await loadInstalledState()
            await bootstrap.refreshAnnexIfStale()
        } else if case .failed(let message) = bootstrap.phase {
            Self.logger.error("Bootstrap failed: \(message)")
        }
    }

    /// Explicit reload used by the ⌘R menu action, the Settings "Refresh Catalog" prompt, and the
    /// `BrokenInstallView`/alert retry. Reloads the catalog, then — if the selected brew is valid —
    /// the installed/outdated state; otherwise re-runs `bootstrap` to try to recover, and only
    /// surfaces `hasBrokenInstall` if brew is genuinely unusable afterwards.
    func loadData(forceSync: Bool = false) async {
        Self.logger.info("Starting data load process (forceSync: \(forceSync))")

        if forceSync { isRefreshingCatalog = true }
        defer { if forceSync { isRefreshingCatalog = false } }

        await loadCatalog(forceSync: forceSync)

        if await BrewPaths.isSelectedBrewPathValid() {
            hasBrokenInstall = false
            await loadInstalledState()
            return
        }

        // Selected brew is invalid — attempt recovery (detect existing / reinstall annex).
        await bootstrap.run()

        guard bootstrap.isBrewReady else {
            // Brew is genuinely unusable. `bootstrap` is in `.failed`, so ContentView is
            // already showing the setup overlay's failed state (message + Retry +
            // Troubleshooting + "use your own Homebrew"). Don't also raise `loadAlert` or
            // BrokenInstallView — one error surface, not three stacked. `hasBrokenInstall`
            // stays set as a fallback for the (currently unreachable) no-overlay case.
            hasBrokenInstall = true

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

        hasBrokenInstall = false
        await loadInstalledState()
    }

    /// Stage 1: catalog (categories + taps) from the local DB — fast, no brew CLI dependency.
    private func loadCatalog(forceSync: Bool = false) async {
        do {
            // Animate the placeholder→full transition so cask cards cross-fade into place
            // rather than swapping instantly mid-shimmer-cycle.
            let catalog = try await dataLoader.loadCatalogData(forceSync: forceSync)
            withAnimation(.easeInOut(duration: 0.25)) {
                self.categories = catalog.categories
                self.taps = catalog.taps
            }
        } catch {
            loadAlert.show(error: error, title: "Couldn't load app catalog")
            Self.logger.error("Catalog load failure. Reason: \(error.localizedDescription)")
        }
    }

    /// Stage 2: installed/outdated state from the brew CLI (slow). Updates the registry reactively,
    /// so view models already on screen flip their flags without rebuilding the catalog views.
    private func loadInstalledState() async {
        self.isResolvingInstalledState = true
        defer { self.isResolvingInstalledState = false }

        do {
            // Serial, not concurrent: on a fresh annex the first brew command triggers a one-time
            // `brew vendor-install ruby`, and two brews racing that lock fail with "already locked".
            // Bootstrap primes Ruby up front, but keep these ordered as a second line of defense.
            try await dataLoader.refreshInstalled()
            try await dataLoader.refreshOutdated()
            Self.logger.info("Installed/outdated state loaded successfully!")
        } catch {
            loadAlert.show(error: error, title: "Couldn't load installed apps")
            Self.logger.error("Installed-state load failure. Reason: \(error.localizedDescription)")
        }
    }

    /// Refreshes the list of outdated casks
    func refreshOutdated() async throws {
        try await dataLoader.refreshOutdated()
    }

}

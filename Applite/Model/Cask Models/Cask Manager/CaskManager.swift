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

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: CaskManager.self)
    )

    // MARK: - Convenience Forwarding

    var installedViewModels: [CaskViewModel] { registry.installedViewModels }
    var outdatedViewModels: [CaskViewModel] { registry.outdatedViewModels }
    var activeTasks: [ActiveBrewTask] { brewService.activeTasks }
    var alert: AlertManager { brewService.alert }

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

    /// Reads the bundled `categories.json` and returns placeholder `CategoryLoadResult`s
    /// (no resolved casks). Lets the sidebar and Discover section structure render
    /// before stage 1 completes. Returns `[]` on parse failure — the catalog load will
    /// repopulate it later.
    private static func loadInitialCategories() -> [CategoryLoadResult] {
        guard let url = Bundle.main.url(forResource: "categories", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let defs = try? JSONDecoder().decode([Category].self, from: data) else {
            return []
        }
        return defs.map { CategoryLoadResult(id: $0.id, sfSymbol: $0.sfSymbol, casks: []) }
    }
    
    // MARK: - Registry Forwarding
    
    func existingViewModels(forTokens tokens: Set<CaskId>) -> [CaskViewModel] {
        registry.existingViewModels(forTokens: tokens)
    }

    // MARK: - Brew Operation Forwarding

    func install(_ cask: CaskViewModel, force: Bool = false) {
        brewService.install(cask, force: force)
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
    
    /// Loads cask data in two stages:
    ///
    ///   1. Catalog (categories + taps) from the local DB — fast, no brew CLI dependency.
    ///      Commits to `categories`/`taps` as soon as it returns so the UI lights up.
    ///   2. Installed/outdated state from the brew CLI (slow). Updates the registry
    ///      reactively, so any view models already on screen flip their installed/outdated
    ///      flags without rebuilding the catalog views.
    func loadData() async throws {
        Self.logger.info("Starting data load process")

        // Stage 1: Catalog. Animate the placeholder→full transition so cask cards
        // cross-fade into place rather than swapping instantly mid-shimmer-cycle.
        let catalog = try await dataLoader.loadCatalogData()
        withAnimation(.easeInOut(duration: 0.25)) {
            self.categories = catalog.categories
            self.taps = catalog.taps
        }

        // Stage 2: Brew CLI state
        self.isResolvingInstalledState = true
        defer { self.isResolvingInstalledState = false }

        async let installed: () = dataLoader.refreshInstalled()
        async let outdated: () = dataLoader.refreshOutdated()
        _ = try await (installed, outdated)

        Self.logger.info("Cask data loaded successfully!")
    }

    /// Refreshes the list of outdated casks
    func refreshOutdated() async throws {
        try await dataLoader.refreshOutdated()
    }

    /// Manually re-syncs the catalog from the API, bypassing the freshness gate.
    /// Picks up new third-party taps the user added externally via `brew tap`.
    /// Does NOT re-query brew CLI for installed/outdated state — that has its own button.
    func refreshCatalog() async throws {
        Self.logger.info("Manual catalog refresh requested")
        isRefreshingCatalog = true
        defer { isRefreshingCatalog = false }

        let catalog = try await dataLoader.loadCatalogData(forceSync: true)
        withAnimation(.easeInOut(duration: 0.25)) {
            self.categories = catalog.categories
            self.taps = catalog.taps
        }
    }
}

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
    let dataLoader: CaskDataLoader
    let registry: CaskViewModelRegistry
    var brewService: BrewService

    /// Categories shown in the sidebar and Discover view.
    /// Initialized synchronously from the bundled `categories.json` with empty `casks`
    /// arrays so the UI renders structure from launch; replaced with resolved view models
    /// after `loadCatalogData()` finishes. `CategoryLoadResult` equality is id-based, so
    /// this assignment is invisible to `selection` and to SwiftUI's identity tracking —
    /// the cask cards inside each section just flip from shimmer placeholders to real data.
    var categories: [CategoryLoadResult]

    var taps: [TapLoadResult] = []

    /// True while brew CLI is being queried for installed/outdated state.
    /// Catalog (categories/taps) is independent and lights up before this flips false.
    var isResolvingInstalledState: Bool = false

    /// True while a manual catalog refresh is running (toolbar action).
    var isRefreshingCatalog: Bool = false

    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: CaskManager.self)
    )

    // MARK: - Convenience Forwarding

    var installedViewModels: [CaskViewModel] { registry.installedViewModels }
    var outdatedViewModels: [CaskViewModel] { registry.outdatedViewModels }
    var activeTasks: [ActiveBrewTask] { brewService.activeTasks }

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
}

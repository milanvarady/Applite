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

    var categories: [CategoryLoadResult] = []
    var taps: [TapLoadResult] = []

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

    func search(query: String) throws -> [CaskViewModel] {
        try dataLoader.search(query: query)
    }
}

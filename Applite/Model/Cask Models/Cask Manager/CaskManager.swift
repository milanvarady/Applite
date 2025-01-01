//
//  CaskManager.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 04..
//

import Foundation
import OSLog

typealias CaskId = String
typealias BrewAnalyticsDictionary = [CaskId: Int]
typealias BrewTask = (cask: Cask, task: Task<Void, Never>)

/// Holds all cask data and provides methods to take actions on them (e.g. install, update)
@MainActor
final class CaskManager: ObservableObject {
    /// Cask view models
    @Published var casks: [CaskId: Cask] = [:]
    /// All currently running brew tasks
    @Published var activeTasks: [BrewTask] = []
    @Published var installedCasks: Set<Cask> = []
    @Published var outdatedCasks: Set<Cask> = []

    @Published var alert = AlertManager()

    // Precompiled cask category dicts
    var categories: [CategoryViewModel] = []

    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: CaskManager.self)
    )

    init() {
        // Load categories at init so the view can display them
        do {
            let categories = try loadCategoryJSON()
            let categoryViewModels = categories.map {
                CategoryViewModel(name: $0.id, sfSymbol: $0.sfSymbol, casks: [], casksCoupled: [])
            }

            self.categories = categoryViewModels
        } catch {
            self.alert.show(title: "Couldn't load categories")
            Self.logger.error("Failed to load categories: \(error.localizedDescription)")
        }
    }

    func loadCategoryJSON() throws -> [Category] {
        let decoder = JSONDecoder()
        guard let url = Bundle.main.url(forResource: "categories", withExtension: "json") else {
            throw CaskLoadError.failedToLoadCategoryJSON
        }

        let data = try Data(contentsOf: url)
        let categories = try decoder.decode([Category].self, from: data)

        return categories
    }
}

//
//  CaskModelBuilder.swift
//  Applite
//
//  Created by Milán Várady on 2025.05.09.
//

import Foundation
import OSLog
import SwiftUI

/// Responsible for constructing cask models from raw data
actor CaskModelBuilder {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: CaskModelBuilder.self)
    )

    /// Result struct containing all compiled cask view models
    struct CompiledCaskViewModels {
        var allCasksList: [Cask] = []
        var allCasksDict: [CaskId: Cask] = [:]
        var installedCasks: [Cask] = []
        var outdatedCasks: [Cask] = []
        var categoryDict: [CategoryId: [Cask]] = [:]
        var tapDict: [TapId: [Cask]] = [:]
    }

    /// Creates cask models from raw cask information
    /// - Parameters:
    ///   - caskInfos: Array of raw cask information
    ///   - installedCasks: Set of installed cask IDs
    ///   - outdatedCasks: Set of outdated cask IDs
    ///   - analyticsDict: Dictionary of download analytics
    ///   - categories: Array of categories
    ///   - batchSize: Size of batches for concurrent processing
    /// - Returns: Compiled cask view models
    func createCaskModels(
        from caskInfos: [CaskInfo],
        installedCasks: Set<CaskId>,
        outdatedCasks: Set<CaskId>,
        analyticsDict: BrewAnalyticsDictionary,
        categories: [Category],
        batchSize: Int = 1024
    ) async throws -> CompiledCaskViewModels {
        var viewModels = CompiledCaskViewModels()

        /// Precomputed cask IDs that are in any of the categories for faster lookup
        let casksInCategories: Set<CaskId> = Set(
            categories
                .map { $0.casks }
                .reduce([], +)
        )

        // Break caskInfos into chunks for better performance
        let chunks = caskInfos.chunked(into: batchSize)

        try await withThrowingTaskGroup(of: ([Cask], [(CategoryId, Cask)], [(TapId, Cask)])?.self) { group in
            // Process each chunk concurrently
            for chunk in chunks {
                group.addTask {
                    var chunkCasks: [Cask] = []
                    var categoryAssignments: [(CategoryId, Cask)] = []
                    var tapAssignments: [(TapId, Cask)] = []

                    for caskInfo in chunk {
                        let isInstalled = installedCasks.contains(caskInfo.fullToken)

                        let cask = await Cask(
                            info: caskInfo,
                            downloadsIn365days: analyticsDict[caskInfo.token] ?? 0,
                            isInstalled: isInstalled
                        )

                        chunkCasks.append(cask)

                        // Pre-compute category assignments
                        if casksInCategories.contains(cask.id) {
                            for category in categories {
                                if category.casks.contains(cask.id) {
                                    categoryAssignments.append((category.id, cask))
                                }
                            }
                        }

                        // Pre-compute tap assignments
                        if cask.info.tap != "homebrew/cask" {
                            tapAssignments.append((cask.info.tap, cask))
                        }
                    }

                    return (chunkCasks, categoryAssignments, tapAssignments)
                }
            }

            // Process chunk results
            for try await result in group {
                guard let (chunkCasks, categoryAssignments, tapAssignments) = result else { continue }

                // Store casks from chunk
                for cask in chunkCasks {
                    viewModels.allCasksList.append(cask)
                    viewModels.allCasksDict[cask.id] = cask

                    if await cask.isInstalled {
                        viewModels.installedCasks.append(cask)

                        let isOutdated = outdatedCasks.contains(cask.info.fullToken)
                        if isOutdated {
                            viewModels.outdatedCasks.append(cask)
                        }
                    }
                }

                // Process category assignments
                for (categoryId, cask) in categoryAssignments {
                    viewModels.categoryDict[categoryId, default: []].append(cask)
                }

                // Process tap assignments
                for (tapId, cask) in tapAssignments {
                    viewModels.tapDict[tapId, default: []].append(cask)
                }
            }
        }

        return viewModels
    }

    /// Creates category view models from raw data and compiled casks
    /// - Parameters:
    ///   - categories: Array of categories
    ///   - compiledModels: Compiled cask view models
    /// - Returns: Array of category view models
    func createCategoryViewModels(
        from categories: [Category],
        using compiledModels: CompiledCaskViewModels
    ) -> [CategoryViewModel] {
        var categoryViewModels: [CategoryViewModel] = []

        for category in categories {
            if let casksInCategory = compiledModels.categoryDict[category.id] {
                let casks = casksInCategory.sorted(by: { $0.downloadsIn365days > $1.downloadsIn365days })
                let chunkedCasks = casks.chunked(into: 2)

                categoryViewModels.append(
                    CategoryViewModel(
                        name: category.id,
                        sfSymbol: category.sfSymbol,
                        casks: casks,
                        casksCoupled: chunkedCasks
                    )
                )
            }
        }

        return categoryViewModels
    }

    /// Creates tap view models from compiled casks
    /// - Parameter compiledModels: Compiled cask view models
    /// - Returns: Array of tap view models
    @MainActor
    func createTapViewModels(using compiledModels: CompiledCaskViewModels) -> [TapViewModel] {
        var tapViewModels: [TapViewModel] = []

        for (tapId, casks) in compiledModels.tapDict {
            let tapViewModel = TapViewModel(
                tapId: tapId,
                caskCollection: SearchableCaskCollection(casks: casks.sorted())
            )
            tapViewModels.append(tapViewModel)
        }

        return tapViewModels
    }

    /// Converts analytics data to a dictionary for faster lookups
    /// - Parameter analytics: Raw analytics data from API
    /// - Returns: Dictionary mapping cask IDs to download counts
    func createAnalyticsDictionary(from analytics: BrewAnalytics) -> BrewAnalyticsDictionary {
        Dictionary(uniqueKeysWithValues: analytics.items.map {
            ($0.cask, Int($0.count.replacingOccurrences(of: ",", with: "")) ?? 0)
        })
    }
}

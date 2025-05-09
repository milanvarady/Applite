//
//  CaskDataCoordinator.swift
//  Applite
//
//  Created by Milán Várady on 2025.05.09.
//

import Foundation
import OSLog

/// Coordinates the loading and processing of cask data using various services
@MainActor
final class CaskDataCoordinator {
    private let networkService: CaskNetworkService
    private let cacheService: CaskCacheService
    private let installedService: InstalledCaskService
    private let modelBuilder: CaskModelBuilder

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: CaskDataCoordinator.self)
    )

    init(
        networkService: CaskNetworkService = CaskNetworkService(),
        cacheService: CaskCacheService = CaskCacheService(),
        installedService: InstalledCaskService = InstalledCaskService(),
        modelBuilder: CaskModelBuilder = CaskModelBuilder()
    ) {
        self.networkService = networkService
        self.cacheService = cacheService
        self.installedService = installedService
        self.modelBuilder = modelBuilder
    }

    /// Loads all cask data and builds the necessary models
    /// - Returns: Complete cask data including models and collections
    func loadAllCaskData() async throws -> CaskDataResult {
        logger.info("Starting to load cask data")

        // Load data concurrently
        async let categories = try await loadCategories()
        async let caskInfo = loadCaskInfo()
        async let tapCaskInfo = loadTapCaskInfo()
        async let analytics = loadAnalyticsData()
        async let installedCasks = getInstalledCasks()
        async let outdatedCasks = getOutdatedCasks()

        // Wait for all async operations to complete
        let (caskInfoResult, tapCaskInfoResult, analyticsResult, installedCasksResult, outdatedCasksResult) =
        try await (caskInfo, tapCaskInfo, analytics, installedCasks, outdatedCasks)

        // Combine cask info from main repository and taps
        let combinedCaskInfo = caskInfoResult + tapCaskInfoResult

        // Create analytics dictionary
        let analyticsDict = await modelBuilder.createAnalyticsDictionary(from: analyticsResult)

        // Build cask models
        logger.info("Building cask models")
        let compiledCaskModels = try await modelBuilder.createCaskModels(
            from: combinedCaskInfo,
            installedCasks: installedCasksResult,
            outdatedCasks: outdatedCasksResult,
            analyticsDict: analyticsDict,
            categories: categories
        )

        // Create category view models
        logger.info("Creating category view models")
        let categoryViewModels = await modelBuilder.createCategoryViewModels(
            from: try categories,
            using: compiledCaskModels
        )

        // Create tap view models
        logger.info("Creating tap view models")
        let tapViewModels = modelBuilder.createTapViewModels(
            using: compiledCaskModels
        )

        // Create searchable collections
        let allCasksCollection = SearchableCaskCollection(casks: compiledCaskModels.allCasksList)
        let installedCasksCollection = SearchableCaskCollection(casks: compiledCaskModels.installedCasks.sorted())
        let outdatedCasksCollection = SearchableCaskCollection(casks: compiledCaskModels.outdatedCasks.sorted())

        logger.info("Cask data loading completed successfully")

        // Return result
        return CaskDataResult(
            allCasks: compiledCaskModels.allCasksDict,
            allCasksCollection: allCasksCollection,
            installedCasksCollection: installedCasksCollection,
            outdatedCasksCollection: outdatedCasksCollection,
            categories: categoryViewModels,
            taps: tapViewModels
        )
    }

    /// Gets the set of outdated casks
    func getOutdatedCasks() async throws -> Set<CaskId> {
        return try await installedService.getOutdatedCasks()
    }

    /// Loads cask information with caching strategy
    private func loadCaskInfo() async throws -> [CaskInfo] {
        return try await cacheService.loadModelWithCaching(
            networkFetch: { @Sendable in
                let data = try await self.networkService.fetchCaskInfo()
                return (try JSONEncoder().encode(data), data)
            },
            cacheURL: CaskCacheService.caskCacheURL,
            as: [CaskInfo].self
        )
    }

    /// Loads tap cask information
    private func loadTapCaskInfo() async -> [CaskInfo] {
        return await networkService.fetchTapCaskInfo()
    }

    /// Loads analytics data with caching strategy
    private func loadAnalyticsData() async throws -> BrewAnalytics {
        return try await cacheService.loadModelWithCaching(
            networkFetch: { @Sendable in
                let data = try await self.networkService.fetchAnalyticsData()
                return (try JSONEncoder().encode(data), data)
            },
            cacheURL: CaskCacheService.analyticsCacheURL,
            as: BrewAnalytics.self
        )
    }

    /// Gets the set of installed casks
    private func getInstalledCasks() async throws -> Set<CaskId> {
        return try await installedService.getInstalledCasks()
    }

    /// Loads category data from JSON file
    private func loadCategories() async throws -> [Category] {
        let decoder = JSONDecoder()
        guard let url = Bundle.main.url(forResource: "categories", withExtension: "json") else {
            throw CaskLoadError.failedToLoadCategoryJSON
        }

        let data = try Data(contentsOf: url)
        return try decoder.decode([Category].self, from: data)
    }
}

/// Structure containing all loaded cask data
struct CaskDataResult {
    let allCasks: [CaskId: Cask]
    let allCasksCollection: SearchableCaskCollection
    let installedCasksCollection: SearchableCaskCollection
    let outdatedCasksCollection: SearchableCaskCollection
    let categories: [CategoryViewModel]
    let taps: [TapViewModel]
}

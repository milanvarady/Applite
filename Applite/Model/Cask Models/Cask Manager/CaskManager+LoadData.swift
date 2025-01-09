//
//  CaskManager+LoadData.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.31.
//

import Foundation
import SwiftUI

extension CaskManager {
    // URLs
    private static let cacheDirectory = URL.cachesDirectory
        .appendingPathComponent("Applite", conformingTo: .directory)

    private static let caskCacheURL = URL.cachesDirectory
        .appendingPathComponent("Applite", conformingTo: .directory)
        .appendingPathComponent("cask.json", conformingTo: .json)

    private static let analyicsCacheURL = URL.cachesDirectory
        .appendingPathComponent("Applite", conformingTo: .directory)
        .appendingPathComponent("caskAnalytics.json", conformingTo: .json)

    /// Gathers all necessary information and combines them to a list of ``Cask`` objects
    /// - Returns: Void
    func loadData() async throws -> Void {
        /// Gets cask information from the Homebrew API and decodes it into a list of ``Cask`` objects
        /// - Returns: List of ``Cask`` objects
        @Sendable
        func loadCaskInfo() async throws -> [CaskInfo] {
            // Get json data from api
            guard let casksURL = URL(string: "https://formulae.brew.sh/api/cask.json") else { return [] }

            let caskData: Data

            let sessionConfiguration = NetworkProxyManager.getURLSessionConfiguration()
            let urlSession = URLSession(configuration: sessionConfiguration)

            do {
                (caskData, _) = try await urlSession.data(from: casksURL)
            } catch {
                await Self.logger.error("Couldn't get cask data from brew API. Error: \(error.localizedDescription)")

                // Try to load from cache
                await Self.logger.notice("Attempting to load cask data from cache")
                caskData = try await loadDataFromCache(dataURL: Self.caskCacheURL)
            }

            // Chache json file
            await cacheData(data: caskData, to: Self.caskCacheURL)

            // Decode static cask data
            async let casks = try JSONDecoder().decode([CaskInfo].self, from: caskData)

            return try await casks
        }

        /// Gets cask analytics information from the Homebrew API and decodes it into a dictionary
        /// - Returns: A Cask ID to download count dictionary
        @Sendable
        func loadAnalyticsData() async throws -> BrewAnalyticsDictionary {
            // Get json data from api
            guard let analyticsURL = URL(string: "https://formulae.brew.sh/api/analytics/cask-install/365d.json") else { return [:] }

            let analyticsData: Data

            let sessionConfiguration = NetworkProxyManager.getURLSessionConfiguration()
            let urlSession = URLSession(configuration: sessionConfiguration)

            do {
                (analyticsData, _) = try await urlSession.data(from: analyticsURL)
            } catch {
                await Self.logger.error("Couldn't get analytics data from brew API. Error: \(error.localizedDescription)")

                // Try to load from cache
                await Self.logger.notice("Attempting to load analytics data from cache")
                analyticsData = try await loadDataFromCache(dataURL: Self.analyicsCacheURL)
            }

            // Chache json file
            await cacheData(data: analyticsData, to: Self.analyicsCacheURL)

            // Decode data
            async let analyticsDecoded = try JSONDecoder().decode(BrewAnalytics.self, from: analyticsData)

            // Convert analytics to a cask ID to download count dictionary
            let analyticsDict: BrewAnalyticsDictionary = Dictionary(uniqueKeysWithValues: try await analyticsDecoded.items.map {
                ($0.cask, Int($0.count.replacingOccurrences(of: ",", with: "")) ?? 0)
            })

            return analyticsDict
        }

        /// Gets the list of installed casks
        /// - Returns: A list of Cask ID's
        @Sendable
        func getInstalledCasks() async throws -> Set<String> {
            let output = try await Shell.runBrewCommand(["list", "--cask"])

            if output.isEmpty {
                await Self.logger.notice("No installed casks were found. Output: \(output)")
            }

            let arr = output
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n")

            return Set(arr)
        }

        /// Saves ``Data`` objects to cache
        ///
        /// - Parameters:
        ///   - data: Data to be saved to cache
        ///
        /// - Returns: Void
        @Sendable
        func cacheData(data: Data, to filePath: URL) async {
            // Create cache directory if doesn't exists
            do {
                var isDirectory: ObjCBool = true

                if await !FileManager.default.fileExists(atPath: Self.cacheDirectory.path, isDirectory: &isDirectory) {
                    await Self.logger.warning("Cache directory doesn't exists, attempting to create it")
                    try await FileManager.default.createDirectory(at: Self.cacheDirectory, withIntermediateDirectories: false)
                }
            } catch {
                await Self.logger.error("Cound't create cache directory")
                return
            }

            // Save data to cache
            do {
                try data.write(to: filePath)
            } catch {
                await Self.logger.error("Couldn't write data to cache")
            }
        }

        /// Loads data from cache
        /// - Returns: A ``Data`` object
        @Sendable
        func loadDataFromCache(dataURL: URL) async throws -> Data {
            do {
                return try Data(contentsOf: dataURL)
            } catch {
                throw CaskLoadError.failedToLoadFromCache
            }
        }

        func loadCategoryJSONAsync() async throws -> [Category] {
            try loadCategoryJSON()
        }

        /// Creates ``Cask`` objects concurrently in batches
        func createCasks(
            from caskInfos: [CaskInfo],
            installedCasks: Set<String>,
            analyticsDict: BrewAnalyticsDictionary,
            categories: [Category],
            batchSize: Int = 1024
        ) async throws -> ([String: Cask], [CategoryId: [Cask]]) {
            var casks: [String: Cask] = [:]
            var categoryDict: [CategoryId: [Cask]] = [:]

            /// Precomputed cask IDs that are in any of the cateogires for faster lookup
            let casksInCategories: Set<CaskId> = Set(
                categories
                    .map { $0.casks }
                    .reduce([], +)
            )

            // Break caskInfos into chunks of ~100 items
            let chunks = caskInfos.chunked(into: batchSize)

            try await withThrowingTaskGroup(of: ([(String, Cask)], [(CategoryId, Cask)])?.self) { group in
                // Process each chunk concurrently instead of individual casks
                // Creating too many tasks at once will slow down the loading process
                for chunk in chunks {
                    group.addTask {
                        var chunkCasks: [(String, Cask)] = []
                        var categoryAssignments: [(CategoryId, Cask)] = []

                        for caskInfo in chunk {
                            let isInstalled = installedCasks.contains(caskInfo.token)
                            let cask = await Cask(
                                info: caskInfo,
                                downloadsIn365days: analyticsDict[caskInfo.token] ?? 0,
                                isInstalled: isInstalled
                            )

                            chunkCasks.append((cask.id, cask))

                            // Pre-compute category assignments
                            if casksInCategories.contains(cask.id) {
                                for category in categories {
                                    if category.casks.contains(cask.id) {
                                        categoryAssignments.append((category.id, cask))
                                    }
                                }
                            }
                        }

                        return (chunkCasks, categoryAssignments)
                    }
                }

                // Process chunk results
                for try await result in group {
                    guard let (chunkCasks, categoryAssignments) = result else { continue }

                    // Store casks from chunk
                    for (id, cask) in chunkCasks {
                        casks[id] = cask
                        self.allCasks.addCask(cask)
                        if cask.isInstalled {
                            self.installedCasks.addCask(cask)
                        }
                    }

                    // Process category assignments
                    for (categoryId, cask) in categoryAssignments {
                        categoryDict[categoryId, default: []].append(cask)
                    }
                }
            }

            return (casks, categoryDict)
        }


        // Get data components concurrently
        async let categories = loadCategoryJSONAsync()
        async let caskInfo = loadCaskInfo()
        async let analyticsDict = loadAnalyticsData()
        async let installedCasks = getInstalledCasks()

        // Set casks reseve capacity for better performance
        await self.casks.reserveCapacity(try caskInfo.count)
        await self.allCasks.setReserveCapacity(try caskInfo.count)

        let (processedCasks, categoryDict) = try await createCasks(
            from: caskInfo,
            installedCasks: installedCasks,
            analyticsDict: analyticsDict,
            categories: categories
        )

        self.casks = processedCasks

        Self.logger.info("Compiling categories")

        var categoryViewModels: [CategoryViewModel] = []

        // Make category view models
        for category in try await categories {
            if let casksInCategory = categoryDict[category.id] {
                let casks = casksInCategory.sorted(by: { $0.downloadsIn365days > $1.downloadsIn365days })
                let chunkedCasks = casks.chunked(into: 2)

                categoryViewModels.append(
                    CategoryViewModel(
                        name: LocalizedStringKey(category.id),
                        sfSymbol: category.sfSymbol,
                        casks: casks,
                        casksCoupled: chunkedCasks
                    )
                )
            }
        }

        self.categories = categoryViewModels

        Self.logger.info("Cask data loaded successfully!")

        try await self.refreshOutdated()
    }
}

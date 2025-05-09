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
    private static let caskAPIURL = URL(string: "https://formulae.brew.sh/api/cask.json")!
    private static let analyticsAPIURL = URL(string: "https://formulae.brew.sh/api/analytics/cask-install/365d.json")!

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
    func loadData() async throws {
        @Sendable
        func loadModel<T: Decodable>(apiURL: URL, cacheURL: URL, as type: T.Type) async throws -> T {
            // Load from cache if fresh enough
            do {
                let updateFreqRawValue = UserDefaults.standard.integer(forKey: Preferences.catalogUpdateFrequency.rawValue)

                guard let updateFreq = CatalogUpdateFrequency(rawValue: updateFreqRawValue) else {
                    throw CaskLoadError.failedToGetUpdateFrequency
                }

                if try updateFreq.shouldLoadFromCache(at: cacheURL) {
                    await Self.logger.notice("Cache for \(type) is up to date.")
                    return try await loadModelFromCache(from: cacheURL, as: type)
                }
            } catch {
                await Self.logger.error("Failed to load \(type) from cache. Error: \(error.localizedDescription).")
                await Self.logger.notice("Defaulting to API load for \(type).")
            }

            // Load from web API
            do {
                let sessionConfiguration = NetworkProxyManager.getURLSessionConfiguration()
                let urlSession = URLSession(configuration: sessionConfiguration)

                let (modelData, _) = try await urlSession.data(from: apiURL)

                // Chache json file
                await cacheData(data: modelData, to: cacheURL)

                return try JSONDecoder().decode(type, from: modelData)
            } catch {
                await Self.logger.error("Couldn't get cask data from brew API. Error: \(error.localizedDescription)")
            }

            await Self.logger.notice("Loading of \(type) has failed. Attempting to load from cache.")
            return try await loadModelFromCache(from: cacheURL, as: type)
        }

        /// Gets cask information from the Homebrew API and decodes it into a list of ``Cask`` objects
        /// - Returns: List of ``Cask`` objects
        @Sendable
        func loadCaskInfo() async throws -> [CaskInfo] {
            return try await loadModel(
                apiURL: Self.caskAPIURL,
                cacheURL: Self.caskCacheURL,
                as: [CaskInfo].self
            )
        }

        func loadTapCaskInfo() async -> [CaskInfo] {
            // Check if taps are enabled
            let enabled = UserDefaults.standard.value(forKey: Preferences.includeCasksFromTaps.rawValue) as? Bool ?? true

            // If not return empty array
            guard enabled else {
                return []
            }

            guard let tapInfoRubyScriptPath = Bundle.main.path(forResource: "brew-tap-cask-info", ofType: "rb") else {
                Self.logger.error("Failed to locate tap info ruby script")
                return []
            }

            let arguments = [BrewPaths.currentBrewExecutable.quotedPath(), "ruby", tapInfoRubyScriptPath.paddedWithQuotes()]
            let command = arguments.joined(separator: " ")

            var shellOutput = ""

            // We need to use stream here because the regular runAsync cannot handle an output this long
            do {
                for try await line in Shell.stream(command) {
                    shellOutput += line + "\n"
                }
            } catch {
                Self.logger.error("Failed to load tap cask info from shell: \(error).\nOutput: \(shellOutput)")
            }

            // Extract JSON data (text between [] marks)
            guard let match = shellOutput.firstMatch(of: /\[((.|\n|\r)*)\]/) else {
                return []
            }

            let jsonString = match.0

            guard let jsonData = jsonString.data(using: .utf8) else {
                return []
            }

            guard let casks = try? JSONDecoder().decode([CaskInfo].self, from: jsonData) else {
                return []
            }

            return casks
        }

        /// Gets cask analytics information from the Homebrew API and decodes it into a dictionary
        /// - Returns: A Cask ID to download count dictionary
        @Sendable
        func loadAnalyticsData() async throws -> BrewAnalyticsDictionary {
            let analyticsModel = try await loadModel(
                apiURL: Self.analyticsAPIURL,
                cacheURL: Self.analyicsCacheURL,
                as: BrewAnalytics.self
            )

            // Convert analytics to a cask ID to download count dictionary
            let analyticsDict: BrewAnalyticsDictionary = Dictionary(uniqueKeysWithValues: analyticsModel.items.map {
                ($0.cask, Int($0.count.replacingOccurrences(of: ",", with: "")) ?? 0)
            })

            return analyticsDict
        }

        /// Gets the list of installed casks
        /// - Returns: A list of Cask ID's
        @Sendable
        func getInstalledCasks() async throws -> Set<CaskId> {
            let output = try await Shell.runBrewCommand(["list", "--cask", "--full-name"])

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
        func loadModelFromCache<T: Decodable>(from url: URL, as type: T.Type) async throws -> T {
            do {
                let modelData = try Data(contentsOf: url)
                return try JSONDecoder().decode(type, from: modelData)
            } catch {
                throw CaskLoadError.failedToLoadFromCache
            }
        }

        func loadCategoryJSONAsync() async throws -> [Category] {
            try loadCategoryJSON()
        }

        struct CompiledCaskViewModels {
            var allCasksList: [Cask] = []
            var allCasksDict: [CaskId: Cask] = [:]
            var installedCasks: [Cask] = []
            var categoryDict: [CategoryId: [Cask]] = [:]
            var tapDict: [TapId: [Cask]] = [:]
        }

        /// Creates ``Cask`` objects concurrently in batches
        /// - Returns: Cask ID to Cask dict, Category ID to Casks dict, Tap ID to Casks dict
        func createCasks(
            from caskInfos: [CaskInfo],
            installedCasks: Set<CaskId>,
            analyticsDict: BrewAnalyticsDictionary,
            categories: [Category],
            batchSize: Int = 1024
        ) async throws -> CompiledCaskViewModels {
            var viewModels = CompiledCaskViewModels()

            /// Precomputed cask IDs that are in any of the cateogires for faster lookup
            let casksInCategories: Set<CaskId> = Set(
                categories
                    .map { $0.casks }
                    .reduce([], +)
            )

            // Break caskInfos into chunks of ~100 items
            let chunks = caskInfos.chunked(into: batchSize)

            try await withThrowingTaskGroup(of: ([(CaskId, Cask)], [(CategoryId, Cask)], [(TapId, Cask)])?.self) { group in
                // Process each chunk concurrently instead of individual casks
                // Creating too many tasks at once will slow down the loading process
                for chunk in chunks {
                    group.addTask {
                        var chunkCasks: [(CaskId, Cask)] = []
                        var categoryAssignments: [(CategoryId, Cask)] = []
                        var tapAssignments: [(TapId, Cask)] = []

                        for caskInfo in chunk {
                            let isInstalled = installedCasks.contains(caskInfo.fullToken)
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
                    for (id, cask) in chunkCasks {
                        viewModels.allCasksList.append(cask)
                        viewModels.allCasksDict[id] = cask

                        if cask.isInstalled {
                            viewModels.installedCasks.append(cask)
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

        Self.logger.info("Initial model load started")

        // Get data components concurrently
        async let categories = loadCategoryJSONAsync()
        async let caskInfo = loadCaskInfo()
        async let tapCaskInfo = loadTapCaskInfo()
        async let analyticsDict = loadAnalyticsData()
        async let installedCasks = getInstalledCasks()

        let combinedCaskInfo = try await caskInfo + tapCaskInfo

        // Set casks reseve capacity for better performance
        self.casks.reserveCapacity(combinedCaskInfo.count)
        self.allCasks.setReserveCapacity(combinedCaskInfo.count)

        Self.logger.info("Precompiling cask view models")

        let caskViewModels = try await createCasks(
            from: combinedCaskInfo,
            installedCasks: installedCasks,
            analyticsDict: analyticsDict,
            categories: categories
        )

        self.casks = caskViewModels.allCasksDict
        self.allCasks.defineCasks(caskViewModels.allCasksList)
        self.installedCasks.defineCasks(caskViewModels.installedCasks.sorted())

        // Make category view models
        Self.logger.info("Precompiling category view models")

        var categoryViewModels: [CategoryViewModel] = []

        for category in try await categories {
            if let casksInCategory = caskViewModels.categoryDict[category.id] {
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

        // Make tap view models
        Self.logger.info("Precomping tap view models")

        var tapViewModels: [TapViewModel] = []

        for (tapId, casks) in caskViewModels.tapDict {
            let tapViewModel = TapViewModel(tapId: tapId, caskCollection: SearchableCaskCollection(casks: casks.sorted()))
            tapViewModels.append(tapViewModel)
        }

        self.taps = tapViewModels

        Self.logger.info("Precompiling category view models")

        Self.logger.info("Cask data loaded successfully!")
        Self.logger.info("Refreshing outdated casks")

        try await self.refreshOutdated()
    }
}

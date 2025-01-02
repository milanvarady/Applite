//
//  CaskManager+LoadData.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.31.
//

import Foundation

extension CaskManager {
    // URLs
    private static let cacheDirectory = URL.cachesDirectory
        .appendingPathComponent(Bundle.main.appName, conformingTo: .directory)

    private static let caskCacheURL = URL.cachesDirectory
        .appendingPathComponent(Bundle.main.appName, conformingTo: .directory)
        .appendingPathComponent("cask.json", conformingTo: .json)

    private static let analyicsCacheURL = URL.cachesDirectory
        .appendingPathComponent(Bundle.main.appName, conformingTo: .directory)
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

            let caskManager: Data

            let sessionConfiguration = NetworkProxyManager.getURLSessionConfiguration()
            let urlSession = URLSession(configuration: sessionConfiguration)

            do {
                (caskManager, _) = try await urlSession.data(from: casksURL)
            } catch {
                await Self.logger.error("Couldn't get cask data from brew API. Error: \(error.localizedDescription)")

                // Try to load from cache
                await Self.logger.notice("Attempting to load cask data from cache")
                caskManager = try await loadDataFromCache(dataURL: Self.caskCacheURL)
            }

            // Chache json file
            await cacheData(data: caskManager, to: Self.caskCacheURL)

            // Decode static cask data
            return try JSONDecoder().decode([CaskInfo].self, from: caskManager)
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

            let analyticsDecoded: BrewAnalytics

            // Decode data
            analyticsDecoded = try JSONDecoder().decode(BrewAnalytics.self, from: analyticsData)

            // Convert analytics to a cask ID to download count dictionary
            let analyticsDict: BrewAnalyticsDictionary = Dictionary(uniqueKeysWithValues: analyticsDecoded.items.map {
                ($0.cask, Int($0.count.replacingOccurrences(of: ",", with: "")) ?? 0)
            })

            return analyticsDict
        }

        /// Gets the list of installed casks
        /// - Returns: A list of Cask ID's
        @Sendable
        func getInstalledCasks() async throws -> [String] {
            let output = try await Shell.runBrewCommand(["list", "--cask"])

            if output.isEmpty {
                await Self.logger.notice("No installed casks were found. Output: \(output)")
            }

            return output
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n")
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

        // Get data components concurrently
        async let categories = loadCategoryJSONAsync()
        async let caskInfo = loadCaskInfo()
        async let analyticsDict = loadAnalyticsData()
        async let installedCasks = getInstalledCasks()

        // Set casks reseve capacity for better performance
        await self.casks.reserveCapacity(try caskInfo.count)

        // Casks by category
        var categoryDict: [CategoryId: [Cask]] = [:]

        for caskInfo in try await caskInfo {
            let isInstalled = try await installedCasks.contains(caskInfo.id)

            let cask = Cask(
                info: caskInfo,
                downloadsIn365days: try await analyticsDict[caskInfo.id] ?? 0,
                isInstalled: isInstalled
            )

            casks[cask.id] = cask

            if isInstalled {
                self.installedCasks.insert(cask)
            }

            // Add to category if needed
            for category in try await categories {
                // Add to category
                if category.casks.contains(cask.id) {
                    if let casksInCategory = categoryDict[category.id] {
                        categoryDict[category.id] = casksInCategory + [cask]
                    } else {
                        categoryDict[category.id] = [cask]
                    }
                }
            }
        }

        Self.logger.info("Compiling categories")

        var categoryViewModels: [CategoryViewModel] = []

        // Make category view models
        for category in try await categories {
            if let casksInCategory = categoryDict[category.id] {
                let casks = casksInCategory.sorted(by: { $0.downloadsIn365days > $1.downloadsIn365days })
                let chunkedCasks = casks.chunked(into: 2)

                categoryViewModels.append(
                    CategoryViewModel(
                        name: category.id,
                        sfSymbol: category.sfSymbol,
                        casks: casks,
                        casksCoupled: chunkedCasks)
                )
            }
        }

        self.categories = categoryViewModels

        Self.logger.info("Cask data loaded successfully!")

        try await self.refreshOutdated()
    }
}

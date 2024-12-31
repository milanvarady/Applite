//
//  CaskData.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 04..
//

import Foundation
import OSLog

/// A dictionary that has cask id's as keys and number of downloads as the values
typealias BrewAnalyticsDictionary = [String: Int]

/// Gathers data from Homebrew API and local sources and combines them concurrently into ``Cask`` objects
@MainActor
final class CaskData: ObservableObject {
    @Published var casks: [Cask] = []
    @Published var busyCasks: Set<Cask> = []
    @Published var outdatedCasks: Set<Cask> = []
    
    private static let cacheDirectory = URL.cachesDirectory
        .appendingPathComponent(Bundle.main.appName, conformingTo: .directory)
    
    private static let caskCacheURL = URL.cachesDirectory
        .appendingPathComponent(Bundle.main.appName, conformingTo: .directory)
        .appendingPathComponent("cask.json", conformingTo: .json)
    
    private static let analyicsCacheURL = URL.cachesDirectory
        .appendingPathComponent(Bundle.main.appName, conformingTo: .directory)
        .appendingPathComponent("caskAnalytics.json", conformingTo: .json)
    
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: CaskData.self)
    )
    
    typealias CaskCategoryDict = [String: [Cask]]
    typealias CoupledCaskCategoryDict = [String: [[Cask]]]
    
    var casksByCategory: CaskCategoryDict = [:]
    var casksByCategoryCoupled: CoupledCaskCategoryDict = [:]
    
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
            return try JSONDecoder().decode([CaskInfo].self, from: caskData)
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
            let output = try await Shell.runAsync("\(BrewPaths.currentBrewExecutable) list --cask")

            if output.isEmpty {
                await Self.logger.notice("No installed casks were found")
            }
            
            return output
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n")
        }
        
        /// Gets the list of outdated casks
        /// - Returns: A list of Cask ID's
        @Sendable
        func getOutdatedCasks() async throws -> [String] {
            let output = try await Shell.runAsync("\(BrewPaths.currentBrewExecutable) outdated --cask -q")

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
            let data = try Data(contentsOf: dataURL)

            return data
        }
        
        /// Filters casks into a category to casks dictionary
        /// - Returns: A tuple of two dictionaries, the first is just a category to casks dict, the second is the same but chunked into two for the discover view
        func fillCategoryDicts() -> (CaskCategoryDict, CoupledCaskCategoryDict) {
            var categoryDict: CaskCategoryDict = [:]
            
            for category in categories {
                // Filter casks
                let filteredCasks = casks.filter {
                    category.casks.contains($0.info.id)
                }
                
                // Sort by number of downloads
                categoryDict[category.id] = filteredCasks.sorted(by: { $0.downloadsIn365days > $1.downloadsIn365days })
            }
            
            var coupledCategoryDict: CoupledCaskCategoryDict = [:]
            
            for (categoryID, cask) in categoryDict {
                let chunkedCasks = cask.chunked(into: 2)
                
                coupledCategoryDict[categoryID] = chunkedCasks
            }
            
            return (categoryDict, coupledCategoryDict)
        }
        
        // Get data components concurrently
        async let caskInfo = loadCaskInfo()
        async let analyticsDict = loadAnalyticsData()
        async let installedCasks = getInstalledCasks()
        async let outdatedCaskIDs = getOutdatedCasks()

        var casks: [Cask] = []

        for caskInfo in try await caskInfo {
            let cask = Cask(
                info: caskInfo,
                downloadsIn365days: try await analyticsDict[caskInfo.id] ?? 0,
                isInstalled: try await installedCasks.contains(caskInfo.id),
                isOutdated: try await outdatedCaskIDs.contains(caskInfo.id)
            )

            casks.append(cask)
        }

        self.casks = casks

        Self.logger.info("Cask data loaded successfully!")
        
        // Create category dicts
        (casksByCategory, casksByCategoryCoupled) = fillCategoryDicts()
    }

    func refreshOutdatedApps(greedy: Bool = false) async throws -> Void {
        let output = try await Shell.runAsync("\(BrewPaths.currentBrewExecutable) outdated --cask \(greedy ? "-g" : "") -q")

        let outdatedCaskIDs = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
            .filter({ !$0.isEmpty })                                        // Remove empty strings
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })    // Trim whitespace
        
        for i in self.casks.indices {
            if outdatedCaskIDs.contains(self.casks[i].info.id) && self.casks[i].isInstalled {
                self.casks[i].isOutdated = true
                outdatedCasks.insert(casks[i])
            }
        }
          
        Self.logger.info("Outdated apps refreshed")
    }
    
    /// Filters busy casks
    func filterBusyCasks() {
        self.busyCasks = self.busyCasks.filter {
            $0.progressState != .idle
        }
    }
}

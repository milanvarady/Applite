//
//  CaskData.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 04..
//

import Foundation
import os

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
        func loadCaskObjects() async throws -> [Cask] {
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
            
            // Decode data
            do {
                return try JSONDecoder().decode([Cask].self, from: caskData)
            }
            catch {
                await Self.logger.error("Failed to parse cask data, error: \(error.localizedDescription)")
                throw CaskDataLoadError.decodeError
            }
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
            do {
                analyticsDecoded = try JSONDecoder().decode(BrewAnalytics.self, from: analyticsData)
            }
            catch {
                await Self.logger.error("Failed to parse cask data, error: \(error.localizedDescription)")
                throw CaskDataLoadError.decodeError
            }
            
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
            let result = await shell("\(BrewPaths.currentBrewExecutable) list --cask")
            
            if result.didFail {
                await Self.logger.error("Couldn't get installed apps. Shell output: \(result.output)")
                throw CaskDataLoadError.shellError
            }
            
            if result.output.isEmpty {
                await Self.logger.notice("No installed casks were found")
            }
            
            return result.output.components(separatedBy: "\n")
        }
        
        /// Gets the list of outdated casks
        /// - Returns: A list of Cask ID's
        @Sendable
        func getOutdatedCasks() async throws -> [String] {
            let result = await shell("\(BrewPaths.currentBrewExecutable) outdated --cask -q")
            
            if result.didFail {
                await Self.logger.error("Couldn't get outdated apps. Shell output: \(result.output)")
                throw CaskDataLoadError.shellError
            }
            
            return result.output.components(separatedBy: "\n")
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
                let data = try Data(contentsOf: dataURL)
                
                return data
            } catch {
                throw CaskDataLoadError.cacheError
            }
        }
        
        /// Filters casks into a category to casks dictionary
        /// - Returns: A tuple of two dictionaries, the first is just a category to casks dict, the second is the same but chunked into two for the discover view
        func fillCategoryDicts() -> (CaskCategoryDict, CoupledCaskCategoryDict) {
            var categoryDict: CaskCategoryDict = [:]
            
            for category in categories {
                // Filter casks
                let filteredCasks = casks.filter {
                    category.casks.contains($0.id)
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
        async let caskData = loadCaskObjects()
        async let analyticsDict = loadAnalyticsData()
        async let installedCasks = getInstalledCasks()
        async let outdatedCaskIDs = getOutdatedCasks()
        
        // Combine data into a final list of `Cask` objects
        do {
            for i in try await caskData.indices {
                try await caskData[i].downloadsIn365days = try await analyticsDict[try await caskData[i].id] ?? 0
                
                if try await installedCasks.contains(try await caskData[i].id) {
                    try await caskData[i].isInstalled = true
                    
                    if try await outdatedCaskIDs.contains(try await caskData[i].id) {
                        try await caskData[i].isOutdated = true
                        self.outdatedCasks.insert(try await caskData[i])
                    }
                }
            }
        } catch {
            Self.logger.error("Error while trying to combine cask data. Message: \(error.localizedDescription)")
        }
        
        self.casks = try await caskData
        
        Self.logger.info("Cask data loaded successfully!")
        
        // Create category dicts
        (casksByCategory, casksByCategoryCoupled) = fillCategoryDicts()
    }

    func refreshOutdatedApps(greedy: Bool = false) async -> Void {
        let outdatedCaskIDs = await shell("\(BrewPaths.currentBrewExecutable) outdated --cask \(greedy ? "-g" : "") -q").output
            .components(separatedBy: "\n")
            .filter({ $0.count > 0 })                                       // Remove empty strings
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })    // Trim whitespace
        
        for i in self.casks.indices {
            if outdatedCaskIDs.contains(self.casks[i].id) && self.casks[i].isInstalled {
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

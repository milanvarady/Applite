//
//  CaskDataLoader.swift
//  Applite
//
//  Created by Milán Várady on 2026. 02. 11..
//

import Foundation
import OSLog

// MARK: - Result Types

/// A category with its resolved view models.
///
/// `==` includes `casks` so SwiftUI re-renders when the placeholder state
/// (empty casks at launch) is replaced with the full result after stage 1.
/// `hash(into:)` uses `id` only — hash buckets don't need fine-grained content.
struct CategoryLoadResult: Identifiable, Equatable, Hashable {
    let id: String
    let sfSymbol: String
    let casks: [CaskViewModel]

    static func == (lhs: CategoryLoadResult, rhs: CategoryLoadResult) -> Bool {
        lhs.id == rhs.id && lhs.casks == rhs.casks
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// A third-party tap with its resolved view models.
///
/// Same equality contract as `CategoryLoadResult`: include `casks` for SwiftUI updates,
/// hash by `id` only.
struct TapLoadResult: Identifiable, Equatable, Hashable {
    let id: String
    let casks: [CaskViewModel]

    var title: String {
        let tapComponent = id.components(separatedBy: "/").last ?? ""
        if id.count < 16 || tapComponent.lowercased() == "tap" {
            return id
        } else {
            return tapComponent
        }
    }

    static func == (lhs: TapLoadResult, rhs: TapLoadResult) -> Bool {
        lhs.id == rhs.id && lhs.casks == rhs.casks
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - CaskDataLoader

/// Orchestrates loading cask data from the database, network, and brew CLI.
@MainActor
final class CaskDataLoader {
    private let dbService: CaskDatabaseService
    private let registry: CaskViewModelRegistry
    private let installedService: InstalledCaskService

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: CaskDataLoader.self)
    )

    init(
        dbService: CaskDatabaseService = CaskDatabaseService(),
        registry: CaskViewModelRegistry = CaskViewModelRegistry(),
        installedService: InstalledCaskService = InstalledCaskService()
    ) {
        self.dbService = dbService
        self.registry = registry
        self.installedService = installedService
    }

    // MARK: - Main Loading Flow

    /// Loads catalog data (categories + taps) from the database.
    /// Does NOT shell out to the brew CLI — that's `refreshInstalled`/`refreshOutdated`.
    /// On a warm DB this completes in tens of milliseconds; on a cold DB it triggers an API sync first.
    func loadCatalogData() async throws -> (categories: [CategoryLoadResult], taps: [TapLoadResult]) {
        logger.info("Starting catalog load")

        // 1. Sync database from API if stale
        try await syncIfNeeded()

        // 2. Load category definitions from bundled JSON
        let categoryDefs = try loadCategories()

        // 3. Batch fetch records for all tokens referenced by categories
        let categoryTokens = categoryDefs.flatMap(\.casks)
        let categoryRecords = try dbService.fetchCasks(forTokens: categoryTokens)
        let recordsByToken = Dictionary(categoryRecords.map { ($0.token, $0) }, uniquingKeysWith: { first, _ in first })
        let recordsByFullToken = Dictionary(categoryRecords.map { ($0.fullToken, $0) }, uniquingKeysWith: { first, _ in first })

        // 4. Build view models via registry (get-or-create for identity)
        _ = registry.viewModels(for: categoryRecords)

        // 5. Build category results
        let categoryResults: [CategoryLoadResult] = categoryDefs.compactMap { category in
            let records = category.casks.compactMap { token -> CaskRecord? in
                recordsByToken[token] ?? recordsByFullToken[token]
            }
            guard !records.isEmpty else { return nil }
            let vms = registry.viewModels(for: records)
            return CategoryLoadResult(id: category.id, sfSymbol: category.sfSymbol, casks: vms)
        }

        // 6. Build tap results from DB
        let tapResults = try buildTapResults()

        logger.info("Catalog load completed: \(categoryResults.count) categories, \(tapResults.count) taps")

        return (categories: categoryResults, taps: tapResults)
    }

    // MARK: - Search

    /// Searches casks using FTS5 and returns view models (reuses existing instances)
    func search(query: String, limit: Int = 50) async throws -> [CaskViewModel] {
        let records = try await dbService.search(query: query, limit: limit)
        return registry.viewModels(for: records)
    }

    // MARK: - Refresh

    /// Re-queries brew CLI for installed casks, ensures view models exist for each,
    /// and marks them installed in the registry.
    func refreshInstalled() async throws {
        let tokens = try await installedService.getInstalledCasks()
        let records = try dbService.fetchCasks(forTokens: Array(tokens))
        _ = registry.viewModels(for: records)
        registry.markInstalled(tokens: tokens)
    }

    /// Re-queries brew CLI for outdated casks, ensures view models exist for each,
    /// and marks them outdated in the registry.
    func refreshOutdated() async throws {
        let tokens = try await installedService.getOutdatedCasks()
        let records = try dbService.fetchCasks(forTokens: Array(tokens))
        _ = registry.viewModels(for: records)
        registry.markOutdated(tokens: tokens)
    }

    // MARK: - Sync

    /// Checks database freshness and syncs from API if stale
    private func syncIfNeeded() async throws {
        guard try dbService.shouldSync() else {
            logger.info("Database is fresh, skipping sync")
            return
        }

        logger.info("Database is stale, syncing from API")

        // Fetch DTOs, analytics, and tap casks concurrently
        async let dtos = fetchCaskDTOs()
        async let analytics = fetchAnalytics()
        async let tapDTOs = fetchTapDTOs()

        let (dtosResult, analyticsResult, tapDTOsResult) = try await (dtos, analytics, tapDTOs)

        // Build analytics lookup
        var analyticsDict: [String: Int] = [:]
        for item in analyticsResult.items {
            if let count = Int(item.count.replacingOccurrences(of: ",", with: "")) {
                analyticsDict[item.cask] = count
            }
        }

        // Convert DTOs → CaskRecords with analytics
        let allDTOs = dtosResult + tapDTOsResult
        let records = allDTOs.map { dto in
            CaskRecord(fromDTO: dto, downloadsIn365days: analyticsDict[dto.token] ?? 0)
        }

        // Sync to database (delete removed, upsert all, rebuild FTS)
        try dbService.syncFromAPI(records: records)

        logger.info("Sync completed: \(records.count) casks")
    }

    // MARK: - Network Fetching

    /// Fetches cask DTOs from the Homebrew API
    private func fetchCaskDTOs() async throws -> [CaskDTO] {
        let url = URL(string: "https://formulae.brew.sh/api/cask.json")!
        return try await fetchJSON(from: url, as: [CaskDTO].self)
    }

    /// Fetches analytics data from the Homebrew API
    private func fetchAnalytics() async throws -> BrewAnalytics {
        let url = URL(string: "https://formulae.brew.sh/api/analytics/cask-install/365d.json")!
        return try await fetchJSON(from: url, as: BrewAnalytics.self)
    }

    /// Fetches cask DTOs from third-party taps via brew ruby script
    private func fetchTapDTOs() async -> [CaskDTO] {
        let enabled = UserDefaults.standard.value(forKey: Preferences.includeCasksFromTaps.rawValue) as? Bool ?? true
        guard enabled else { return [] }

        guard let scriptPath = Bundle.main.path(forResource: "brew-tap-cask-info", ofType: "rb") else {
            logger.error("Failed to locate tap info ruby script")
            return []
        }

        let arguments = [BrewPaths.currentBrewExecutable.quotedPath(), "ruby", scriptPath.paddedWithQuotes()]
        let command = arguments.joined(separator: " ")

        var shellOutput = ""
        do {
            for try await line in Shell.stream(command) {
                shellOutput += line + "\n"
            }
        } catch {
            logger.error("Failed to load tap cask info: \(error)")
        }

        guard let match = shellOutput.firstMatch(of: /\[((.|\n|\r)*)\]/) else {
            return []
        }

        guard let jsonData = String(match.0).data(using: .utf8) else {
            logger.error("Failed to convert tap JSON string to data")
            return []
        }

        guard let dtos = try? JSONDecoder().decode([CaskDTO].self, from: jsonData) else {
            logger.error("Failed to decode tap DTOs from JSON")
            return []
        }

        return dtos
    }

    /// Generic JSON fetch with proxy support
    private func fetchJSON<T: Decodable>(from url: URL, as type: T.Type) async throws -> T {
        let configuration = NetworkProxyManager.getURLSessionConfiguration()
        let session = URLSession(configuration: configuration)
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(type, from: data)
    }

    // MARK: - Private Helpers

    /// Loads category definitions from the bundled JSON file
    private func loadCategories() throws -> [Category] {
        guard let url = Bundle.main.url(forResource: "categories", withExtension: "json") else {
            throw CaskLoadError.failedToLoadCategoryJSON
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Category].self, from: data)
    }

    /// Builds tap results from the database
    private func buildTapResults() throws -> [TapLoadResult] {
        let taps = try dbService.fetchAllTaps()
        return try taps.map { tap in
            let records = try dbService.fetchCasks(forTap: tap)
            let vms = registry.viewModels(for: records)
            return TapLoadResult(id: tap, casks: vms)
        }
    }
}

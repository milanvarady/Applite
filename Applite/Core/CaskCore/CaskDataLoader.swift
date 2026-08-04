//
//  CaskDataLoader.swift
//  Applite
//
//  Created by Milán Várady on 2026. 02. 11..
//

import Foundation
import OSLog

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
    /// Pass `forceSync: true` to bypass the freshness gate (used by the manual refresh action).
    func loadCatalogData(forceSync: Bool = false) async throws -> (categories: [CategoryLoadResult], taps: [TapLoadResult]) {
        logger.info("Starting catalog load (forceSync: \(forceSync))")

        // 1. Sync database from API. If a non-forced sync fails (offline / transient) but the DB
        // already holds a catalog, fall back to that stale data instead of throwing the whole load
        // into an all-session shimmer. A forced manual refresh still throws so the caller can tell
        // the user the refresh didn't go through (their previously-loaded catalog stays on screen).
        do {
            if forceSync {
                try await performSync()
            } else {
                try await syncIfNeeded()
            }
        } catch {
            guard !forceSync, try await dbService.hasCasks() else { throw error }
            logger.warning("Catalog sync failed (\(error.localizedDescription)); using existing database data")
        }

        // 2. Load category definitions from bundled JSON
        let categoryDefs = try loadCategories()

        // 3. Batch fetch records for all tokens referenced by categories
        let categoryTokens = categoryDefs.flatMap(\.casks)
        let categoryRecords = try await dbService.fetchCasks(forTokens: categoryTokens)
        let recordsByToken = Dictionary(categoryRecords.map { ($0.token, $0) }, uniquingKeysWith: { first, _ in first })
        let recordsByFullToken = Dictionary(categoryRecords.map { ($0.fullToken, $0) }, uniquingKeysWith: { first, _ in first })

        // 4. Build view models via registry (get-or-create for identity)
        _ = registry.viewModels(for: categoryRecords)

        // 5. Build category results
        let categoryResults: [CategoryLoadResult] = categoryDefs.compactMap { category in
            let records = category.casks
                .compactMap { token -> CaskRecord? in
                    recordsByToken[token] ?? recordsByFullToken[token]
                }
                // Keep curated categories clean of deprecated/disabled apps
                .filter { !$0.isDeprecatedOrDisabled }
            guard !records.isEmpty else { return nil }
            let vms = registry.viewModels(for: records)
            return CategoryLoadResult(id: category.id, sfSymbol: category.sfSymbol, casks: vms)
        }

        // 6. Build tap results from DB
        let tapResults = try await buildTapResults()

        logger.info("Catalog load completed: \(categoryResults.count) categories, \(tapResults.count) taps")

        return (categories: categoryResults, taps: tapResults)
    }

    // MARK: - Search

    /// Searches casks using FTS5 and returns view models (reuses existing instances)
    func search(query: String, limit: Int = 50) async throws -> [CaskViewModel] {
        let records = try await dbService.search(query: query, limit: limit)
        return registry.viewModels(for: records)
    }

    /// Resolves cask tokens to view models via the DB, creating any that aren't already live.
    /// Unlike `registry.existingViewModels`, this finds casks the user has never browsed — needed
    /// so an imported app list can install anything in the catalog. Unknown tokens are dropped.
    func viewModels(forTokens tokens: Set<CaskId>) async throws -> [CaskViewModel] {
        let records = try await dbService.fetchCasks(forTokens: Array(tokens))
        return registry.viewModels(for: records)
    }

    // MARK: - Refresh

    /// Re-queries brew CLI for installed casks, ensures view models exist for each,
    /// and marks them installed in the registry.
    func refreshInstalled() async throws {
        let tokens = try await installedService.getInstalledCasks()
        let records = try await dbService.fetchCasks(forTokens: Array(tokens))
        _ = registry.viewModels(for: records)
        registry.markInstalled(tokens: tokens)
    }

    /// Re-queries brew CLI for outdated casks, ensures view models exist for each,
    /// and marks them outdated in the registry.
    func refreshOutdated() async throws {
        let tokens = try await installedService.getOutdatedCasks()
        let records = try await dbService.fetchCasks(forTokens: Array(tokens))
        _ = registry.viewModels(for: records)
        registry.markOutdated(tokens: tokens)
    }

    // MARK: - Sync

    /// Checks database freshness and syncs from API if stale
    private func syncIfNeeded() async throws {
        guard try await dbService.shouldSync() else {
            logger.info("Database is fresh, skipping sync")
            return
        }
        try await performSync()
    }

    /// Always runs an API sync regardless of the freshness gate.
    private func performSync() async throws {
        logger.info("Syncing catalog from API")

        // Fetch DTOs, analytics, and tap casks concurrently.
        // The category refresh rides along on the same cadence; it's best-effort and never throws,
        // so a blocked/failed fetch can't abort the sync. It completes before `loadCategories()`
        // (step 2 of `loadCatalogData`), so a fresh list shows up within the same load.
        async let dtos = fetchCaskDTOs()
        async let analytics = fetchAnalytics()
        async let tapDTOs = fetchTapDTOs()
        async let categoriesRefresh: Void = CategoryProvider.refreshRemoteCategories()

        let (dtosResult, analyticsResult, tapDTOsResult) = try await (dtos, analytics, tapDTOs)
        await categoriesRefresh

        // A `nil` tap result means the fetch failed (vs. `[]` = legitimately no tap casks / disabled).
        // On failure, don't prune tap casks from the DB — otherwise one transient hiccup wipes every
        // installed custom-tap cask until the next successful fetch.
        let tapFetchFailed = tapDTOsResult == nil

        // Build analytics lookup
        var analyticsDict: [String: Int] = [:]
        for item in analyticsResult.items {
            if let count = Int(item.count.replacingOccurrences(of: ",", with: "")) {
                analyticsDict[item.cask] = count
            }
        }

        // Convert DTOs → CaskRecords with analytics
        let allDTOs = dtosResult + (tapDTOsResult ?? [])
        let records = allDTOs.map { dto in
            CaskRecord(fromDTO: dto, downloadsIn365days: analyticsDict[dto.token] ?? 0)
        }

        // Sync to database. FTS5 stays in lock-step via synchronize(withTable:) triggers.
        try await dbService.syncFromAPI(records: records, pruneTapCasks: !tapFetchFailed)

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

    /// Fetches cask DTOs from third-party taps via brew ruby script.
    ///
    /// Returns `nil` to signal a *failure* (script missing, brew error, unparseable output) as
    /// distinct from `[]` (tap fetch intentionally disabled, or genuinely no tap casks). Callers
    /// must not prune existing tap casks from the DB on `nil` — see `syncFromAPI(pruneTapCasks:)`.
    private func fetchTapDTOs() async -> [CaskDTO]? {
        let enabled = UserDefaults.standard.value(for: Preferences.includeCasksFromTaps)
        guard enabled else {
            logger.info("Tap fetch skipped: includeCasksFromTaps is disabled")
            return []
        }

        guard let scriptPath = Bundle.main.path(forResource: "brew-tap-cask-info", ofType: "rb") else {
            logger.error("Failed to locate tap info ruby script")
            return nil
        }

        logger.info("Running tap fetch: brew ruby \(scriptPath)")

        var shellOutput = ""
        do {
            for try await line in Shell.streamBrewCommand(["ruby", scriptPath]) {
                shellOutput += line + "\n"
            }
        } catch {
            logger.error("Failed to load tap cask info: \(error)")
            return nil
        }

        logger.info("Tap script output length: \(shellOutput.count) chars")

        guard let match = shellOutput.firstMatch(of: /\[((.|\n|\r)*)\]/) else {
            logger.error("Tap script output did not contain a JSON array. First 500 chars: \(shellOutput.prefix(500))")
            return nil
        }

        guard let jsonData = String(match.0).data(using: .utf8) else {
            logger.error("Failed to convert tap JSON string to data")
            return nil
        }

        do {
            let dtos = try JSONDecoder().decode([CaskDTO].self, from: jsonData)
            logger.info("Tap fetch decoded \(dtos.count) DTOs")
            return dtos
        } catch {
            logger.error("Failed to decode tap DTOs from JSON: \(error)")
            return nil
        }
    }

    /// Generic JSON fetch with proxy support
    private func fetchJSON<T: Decodable>(from url: URL, as type: T.Type) async throws -> T {
        let configuration = NetworkProxyManager.getURLSessionConfiguration()
        let session = URLSession(configuration: configuration)
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(type, from: data)
    }

    // MARK: - Private Helpers

    /// Loads category definitions via `CategoryProvider` (cached remote copy → bundled fallback).
    private func loadCategories() throws -> [Category] {
        let defs = CategoryProvider.loadCategories()
        guard !defs.isEmpty else {
            throw CaskLoadError.failedToLoadCategoryJSON
        }
        return defs
    }

    /// Builds tap results from the database in a single query, grouped in-memory by tap.
    /// Records are pre-ordered by `tap, name` so each tap's casks come out name-sorted.
    private func buildTapResults() async throws -> [TapLoadResult] {
        let records = try await dbService.fetchAllNonDefaultTapCasks()
        let grouped = Dictionary(grouping: records, by: \.tap)
        return grouped
            .map { TapLoadResult(id: $0.key, casks: registry.viewModels(for: $0.value)) }
            .sorted { $0.id < $1.id }
    }
}

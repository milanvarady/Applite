//
//  CaskDatabaseService.swift
//  Applite
//
//  Created by Milán Várady on 2026. 02. 10..
//

import Foundation
import GRDB
import OSLog

/// Service for all cask database operations
struct CaskDatabaseService {
    private let dbPool: DatabasePool
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: CaskDatabaseService.self)
    )

    init(dbPool: DatabasePool = AppDatabase.shared) {
        self.dbPool = dbPool
    }

    // MARK: - Read Operations

    /// Fetches a single cask by token
    func fetchCask(token: String) async throws -> CaskRecord? {
        try await dbPool.read { db in
            try CaskRecord.fetchOne(db, key: token)
        }
    }

    /// Fetches a single cask by full token
    func fetchCask(fullToken: String) async throws -> CaskRecord? {
        try await dbPool.read { db in
            try CaskRecord.filter(Column("fullToken") == fullToken).fetchOne(db)
        }
    }

    /// Fetches casks matching a list of tokens (checks both `token` and `fullToken` columns)
    func fetchCasks(forTokens tokens: [String]) async throws -> [CaskRecord] {
        guard !tokens.isEmpty else { return [] }
        return try await dbPool.read { db in
            try CaskRecord
                .filter(tokens.contains(Column("token")) || tokens.contains(Column("fullToken")))
                .fetchAll(db)
        }
    }

    /// Fetches all casks not in the default `homebrew/cask` tap, ordered by tap then name.
    /// Used to build per-tap result groups via in-memory partitioning.
    func fetchAllNonDefaultTapCasks() async throws -> [CaskRecord] {
        try await dbPool.read { db in
            try CaskRecord
                .filter(Column("tap") != "homebrew/cask")
                .order(Column("tap"), Column("name"))
                .fetchAll(db)
        }
    }

    /// Fetches the most popular casks
    func fetchPopularCasks(limit: Int = 50) async throws -> [CaskRecord] {
        try await dbPool.read { db in
            try CaskRecord.order(Column("downloadsIn365days").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Returns the count of all casks
    func caskCount() async throws -> Int {
        try await dbPool.read { db in
            try CaskRecord.fetchCount(db)
        }
    }

    /// Checks if the database has any casks
    func hasCasks() async throws -> Bool {
        try await caskCount() > 0
    }

    // MARK: - FTS5 Search

    /// Searches casks using FTS5 full-text search with prefix matching and BM25 ranking.
    /// Uses GRDB's `FTS5Pattern(matchingAllPrefixesIn:)` so every typed token gets
    /// prefix-matched (e.g. "adobe phot" → tokens "adobe*" AND "phot*").
    func search(query: String, limit: Int = 50) async throws -> [CaskRecord] {
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query) else {
            return []
        }

        let request: SQLRequest<CaskRecord> = """
            SELECT casks.*
            FROM casks
            JOIN cask_fts ON cask_fts.rowid = casks.rowid
            WHERE cask_fts MATCH \(pattern)
            ORDER BY bm25(cask_fts)
            LIMIT \(limit)
            """

        return try await dbPool.read { db in
            try request.fetchAll(db)
        }
    }

    // MARK: - Sync Operations

    /// Syncs cask records from API data: deletes removed casks and upserts all records.
    /// FTS5 stays in sync via `synchronize(withTable:)` triggers; no manual rebuild needed.
    func syncFromAPI(records: [CaskRecord]) async throws {
        logger.info("Syncing \(records.count) casks to database")

        try await dbPool.write { db in
            // Collect all tokens from the new data
            let newTokens = Set(records.map(\.token))

            // Delete casks that are no longer in the catalog
            let allExisting = try String.fetchAll(db, sql: "SELECT token FROM casks")
            let toDelete = allExisting.filter { !newTokens.contains($0) }
            if !toDelete.isEmpty {
                try CaskRecord
                    .filter(toDelete.contains(Column("token")))
                    .deleteAll(db)
                logger.info("Removed \(toDelete.count) casks no longer in catalog")
            }

            // Upsert all records. The FTS5 sync triggers from
            // `synchronize(withTable: "casks")` keep `cask_fts` in lock-step,
            // so no explicit rebuild is needed.
            for record in records {
                try record.upsert(db)
            }

            // Update last sync timestamp
            try setLastSyncDate(Date.now, in: db)
        }

        logger.info("Database sync completed")
    }

    // MARK: - Metadata

    /// Checks whether a sync is needed based on the catalog update frequency preference.
    /// A missing key falls back to `CatalogUpdateFrequency.default` (via the preference's
    /// declared default) instead of being read as `0` (= `.everyAppLaunch`).
    func shouldSync() async throws -> Bool {
        let frequency = UserDefaults.standard.value(for: Preferences.catalogUpdateFrequency)

        if frequency == .everyAppLaunch {
            return true
        }

        guard let lastSync = try await getLastSyncDate() else {
            return true
        }

        return Date().timeIntervalSince(lastSync) >= frequency.timeInterval
    }

    /// Returns the last sync date from the metadata table
    func getLastSyncDate() async throws -> Date? {
        try await dbPool.read { db in
            try getLastSyncDate(in: db)
        }
    }

    /// Stores the last sync date in the metadata table
    func setLastSyncDate(_ date: Date) async throws {
        try await dbPool.write { db in
            try setLastSyncDate(date, in: db)
        }
    }

    /// Reads the last sync date using an existing database connection.
    /// Use from inside an outer `dbPool.read`/`write` block to avoid a nested transaction.
    private func getLastSyncDate(in db: Database) throws -> Date? {
        let request: SQLRequest<String> = """
            SELECT value FROM metadata WHERE key = 'lastSyncDate'
            """
        guard let value = try request.fetchOne(db) else { return nil }
        return try? Date(value, strategy: .iso8601)
    }

    /// Writes the last sync date using an existing database connection.
    /// Use from inside an outer `dbPool.write` block to avoid a nested transaction.
    private func setLastSyncDate(_ date: Date, in db: Database) throws {
        try db.execute(literal: """
            INSERT OR REPLACE INTO metadata (key, value)
            VALUES ('lastSyncDate', \(date.ISO8601Format()))
            """)
    }

    // MARK: - Write Operations

    /// Deletes a cask by token
    func delete(token: String) async throws {
        try await dbPool.write { db in
            _ = try CaskRecord.deleteOne(db, key: token)
        }
    }

    /// Deletes all casks
    func deleteAll() async throws {
        try await dbPool.write { db in
            _ = try CaskRecord.deleteAll(db)
        }
    }
}

// MARK: - CaskRecord GRDB Upsert

extension CaskRecord {
    /// Upserts the record (insert or replace)
    func upsert(_ db: Database) throws {
        try insert(db, onConflict: .replace)
    }
}

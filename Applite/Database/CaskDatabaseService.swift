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
    func fetchCask(token: String) throws -> CaskRecord? {
        try dbPool.read { db in
            try CaskRecord.fetchOne(db, key: token)
        }
    }

    /// Fetches a single cask by full token
    func fetchCask(fullToken: String) throws -> CaskRecord? {
        try dbPool.read { db in
            try CaskRecord.filter(Column("fullToken") == fullToken).fetchOne(db)
        }
    }

    /// Fetches casks matching a list of tokens (checks both `token` and `fullToken` columns)
    func fetchCasks(forTokens tokens: [String]) throws -> [CaskRecord] {
        guard !tokens.isEmpty else { return [] }
        return try dbPool.read { db in
            try CaskRecord
                .filter(tokens.contains(Column("token")) || tokens.contains(Column("fullToken")))
                .fetchAll(db)
        }
    }

    /// Fetches casks for a given tap
    func fetchCasks(forTap tap: String) throws -> [CaskRecord] {
        try dbPool.read { db in
            try CaskRecord.filter(Column("tap") == tap)
                .order(Column("name"))
                .fetchAll(db)
        }
    }

    /// Fetches the most popular casks
    func fetchPopularCasks(limit: Int = 50) throws -> [CaskRecord] {
        try dbPool.read { db in
            try CaskRecord.order(Column("downloadsIn365days").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Returns the count of all casks
    func caskCount() throws -> Int {
        try dbPool.read { db in
            try CaskRecord.fetchCount(db)
        }
    }

    /// Checks if the database has any casks
    func hasCasks() throws -> Bool {
        try caskCount() > 0
    }

    /// Fetches all unique taps (excluding homebrew/cask)
    func fetchAllTaps() throws -> [String] {
        try dbPool.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT tap FROM casks
                WHERE tap != 'homebrew/cask'
                ORDER BY tap
            """)
        }
    }

    // MARK: - FTS5 Search

    /// Searches casks using FTS5 full-text search with prefix matching and BM25 ranking
    func search(query: String, limit: Int = 50) async throws -> [CaskRecord] {
        let sanitized = sanitizeFTSQuery(query)
        guard !sanitized.isEmpty else { return [] }

        // Append * for prefix matching (e.g., "fire" matches "firefox")
        let ftsQuery = "\(sanitized)*"

        return try await dbPool.read { db in
            let sql = """
                SELECT casks.*
                FROM casks
                JOIN cask_fts ON cask_fts.rowid = casks.rowid
                WHERE cask_fts MATCH ?
                ORDER BY bm25(cask_fts)
                LIMIT ?
            """
            return try CaskRecord.fetchAll(db, sql: sql, arguments: [ftsQuery, limit])
        }
    }

    // MARK: - Sync Operations

    /// Syncs cask records from API data: deletes removed casks, upserts all records, rebuilds FTS5
    func syncFromAPI(records: [CaskRecord]) throws {
        logger.info("Syncing \(records.count) casks to database")

        try dbPool.write { db in
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

            // Upsert all records
            for record in records {
                try record.upsert(db)
            }

            // Rebuild FTS5 index
            try db.execute(sql: "INSERT INTO cask_fts(cask_fts) VALUES('rebuild')")

            // Update last sync timestamp
            try db.execute(
                sql: "INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)",
                arguments: ["lastSyncDate", ISO8601DateFormatter().string(from: Date())]
            )
        }

        logger.info("Database sync completed")
    }

    // MARK: - Metadata

    /// Checks whether a sync is needed based on the catalog update frequency preference
    func shouldSync() throws -> Bool {
        let rawValue = UserDefaults.standard.integer(forKey: Preferences.catalogUpdateFrequency.rawValue)
        guard let frequency = CatalogUpdateFrequency(rawValue: rawValue) else {
            return true
        }

        if frequency == .everyAppLaunch {
            return true
        }

        guard let lastSync = try getLastSyncDate() else {
            return true
        }

        return Date().timeIntervalSince(lastSync) >= frequency.timeInterval
    }

    /// Returns the last sync date from the metadata table
    func getLastSyncDate() throws -> Date? {
        try dbPool.read { db in
            guard let value = try String.fetchOne(
                db,
                sql: "SELECT value FROM metadata WHERE key = ?",
                arguments: ["lastSyncDate"]
            ) else {
                return nil
            }
            return ISO8601DateFormatter().date(from: value)
        }
    }

    /// Stores the last sync date in the metadata table
    func setLastSyncDate(_ date: Date) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)",
                arguments: ["lastSyncDate", ISO8601DateFormatter().string(from: date)]
            )
        }
    }

    // MARK: - Write Operations

    /// Deletes a cask by token
    func delete(token: String) throws {
        _ = try dbPool.write { db in
            try CaskRecord.deleteOne(db, key: token)
        }
    }

    /// Deletes all casks
    func deleteAll() throws {
        _ = try dbPool.write { db in
            try CaskRecord.deleteAll(db)
        }
    }

    // MARK: - Private Helpers

    /// Sanitizes a query string for FTS5 by removing special characters
    private func sanitizeFTSQuery(_ query: String) -> String {
        // Remove FTS5 special characters that could cause syntax errors
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        return String(query.unicodeScalars.filter { allowed.contains($0) })
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - CaskRecord GRDB Upsert

extension CaskRecord {
    /// Upserts the record (insert or replace)
    func upsert(_ db: Database) throws {
        try insert(db, onConflict: .replace)
    }
}

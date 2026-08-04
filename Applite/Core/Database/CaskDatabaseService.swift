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
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: CaskDatabaseService.self)
    )

    /// The shared pool, obtained async-lazily so the (potentially slow) open never runs on the main
    /// actor at construction time — this service is created during `CaskManager` init (P2-13).
    private func pool() async throws -> DatabasePool {
        try await AppDatabase.pool()
    }

    // MARK: - Read Operations

    /// Fetches a single cask by its full token (the primary key).
    ///
    /// There is deliberately no bare-token equivalent: a bare token can match several casks across
    /// taps, so "fetch the one for this token" is a question with no correct answer.
    func fetchCask(fullToken: String) async throws -> CaskRecord? {
        try await pool().read { db in
            try CaskRecord.fetchOne(db, key: fullToken)
        }
    }

    /// Fetches casks matching a list of tokens (checks both `token` and `fullToken` columns)
    ///
    /// Not chunked, deliberately (P2-23): this binds 2× the token count, and the catalog itself is
    /// ~7.7k casks, so reaching even SQLite's *stock* 32,766-variable limit would take an import
    /// file with more tokens than there are casks in existence. Apple's build raises the limit to
    /// 500,000 besides. Chunking here would be complexity guarding an unreachable case.
    func fetchCasks(forTokens tokens: [String]) async throws -> [CaskRecord] {
        guard !tokens.isEmpty else { return [] }
        return try await pool().read { db in
            try CaskRecord
                .filter(tokens.contains(Column("token")) || tokens.contains(Column("fullToken")))
                .fetchAll(db)
        }
    }

    /// Fetches all casks not in the default `homebrew/cask` tap, ordered by tap then name.
    /// Used to build per-tap result groups via in-memory partitioning.
    func fetchAllNonDefaultTapCasks() async throws -> [CaskRecord] {
        try await pool().read { db in
            try CaskRecord
                .filter(Column("tap") != "homebrew/cask")
                .order(Column("tap"), Column("name"))
                .fetchAll(db)
        }
    }

    /// Fetches the most popular casks
    func fetchPopularCasks(limit: Int = 50) async throws -> [CaskRecord] {
        try await pool().read { db in
            try CaskRecord.order(Column("downloadsIn365days").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Returns the count of all casks
    func caskCount() async throws -> Int {
        try await pool().read { db in
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

        return try await pool().read { db in
            try request.fetchAll(db)
        }
    }

    // MARK: - Sync Operations

    /// Syncs cask records from API data: deletes removed casks and upserts all records.
    /// FTS5 stays in sync via `synchronize(withTable:)` triggers; no manual rebuild needed.
    ///
    /// - Parameter pruneTapCasks: When `false`, casks outside the default `homebrew/cask` tap are
    ///   never deleted even if absent from `records`. Pass `false` when the third-party tap fetch
    ///   failed (returned no trustworthy data) so a transient failure can't wipe every custom-tap
    ///   cask — including installed ones — from the DB.
    func syncFromAPI(records: [CaskRecord], pruneTapCasks: Bool = true) async throws {
        logger.info("Syncing \(records.count) casks to database (pruneTapCasks: \(pruneTapCasks))")

        try await pool().write { db in
            // Identity is `fullToken` throughout — matching on the bare token would delete *every*
            // tap's copy of a cask because one tap dropped it.
            let newFullTokens = Set(records.map(\.fullToken))

            // Delete casks that are no longer in the catalog. When tap data is untrusted
            // (`pruneTapCasks == false`), protect every non-default-tap cask from deletion.
            let existing = try Row.fetchAll(db, sql: "SELECT fullToken, tap FROM casks")
            let toDelete: [String] = existing.compactMap { row in
                let fullToken: String = row["fullToken"]
                if newFullTokens.contains(fullToken) { return nil }
                if !pruneTapCasks {
                    let tap: String? = row["tap"]
                    if tap != "homebrew/cask" { return nil }
                }
                return fullToken
            }
            if !toDelete.isEmpty {
                try CaskRecord
                    .filter(toDelete.contains(Column("fullToken")))
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
        try await pool().read { db in
            try getLastSyncDate(in: db)
        }
    }

    /// Stores the last sync date in the metadata table
    func setLastSyncDate(_ date: Date) async throws {
        try await pool().write { db in
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

    /// Deletes all casks
    func deleteAll() async throws {
        try await pool().write { db in
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

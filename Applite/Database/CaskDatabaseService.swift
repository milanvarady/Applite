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
@Observable
@MainActor
final class CaskDatabaseService {
    private let dbPool: DatabasePool
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: CaskDatabaseService.self)
    )

    init(dbPool: DatabasePool = AppDatabase.shared) {
        self.dbPool = dbPool
    }

    // MARK: - Read Operations

    /// Fetches all cask records from the database
    func fetchAllCasks() throws -> [CaskRecord] {
        try dbPool.read { db in
            try CaskRecord.fetchAll(db)
        }
    }

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

    // MARK: - Write Operations

    /// Inserts or updates a cask record
    func upsert(_ record: CaskRecord) throws {
        try dbPool.write { db in
            try record.upsert(db)
        }
    }

    /// Batch inserts or updates multiple cask records
    func upsertAll(_ records: [CaskRecord]) throws {
        try dbPool.write { db in
            for record in records {
                try record.upsert(db)
            }
        }
    }

    /// Syncs cask records from API data, handling inserts, updates, and rebuilding FTS
    func syncFromAPI(records: [CaskRecord]) async throws {
        logger.info("Syncing \(records.count) casks to database")

        try await dbPool.write { db in
            // Upsert all records
            for record in records {
                try record.upsert(db)
            }

            // Rebuild FTS index for optimal performance
            try db.execute(sql: "INSERT INTO cask_fts(cask_fts) VALUES('rebuild')")
        }

        logger.info("Database sync completed")
    }

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
}

// MARK: - CaskRecord Extensions for GRDB

extension CaskRecord {
    /// Upserts the record (insert or replace)
    func upsert(_ db: Database) throws {
        try insert(db, onConflict: .replace)
    }
}

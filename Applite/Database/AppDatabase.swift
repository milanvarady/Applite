//
//  AppDatabase.swift
//  Applite
//
//  Created by Milán Várady on 2026. 02. 09..
//

import Foundation
import GRDB
import OSLog

/// Manages the SQLite database for cask storage
struct AppDatabase {
    static let schemaVersion = 1
    
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: AppDatabase.self)
    )
    
    /// The shared database pool for the application
    static let shared: DatabasePool = {
        do {
            let pool = try openDatabase()
            logger.info("Database opened successfully")
            return pool
        } catch {
            fatalError("Failed to open database: \(error)")
        }
    }()

    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        // Erase database on schema change during development
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        // MARK: - Migration v1: Initial Schema
        migrator.registerMigration("v1_initial") { db in
            // Main casks table
            try db.create(table: "casks") { t in
                // Primary key - the cask token (e.g., "firefox")
                t.primaryKey("token", .text)

                // Full token including tap prefix (e.g., "homebrew/cask/firefox")
                t.column("fullToken", .text)
                    .notNull()
                    .unique()

                // Tap source (e.g., "homebrew/cask")
                t.column("tap", .text)
                    .notNull()

                // Display name (e.g., "Mozilla Firefox")
                t.column("name", .text)
                    .notNull()

                // Short description
                t.column("descriptionText", .text)
                    .notNull()

                // Homepage URL (stored as string, nullable)
                t.column("homepageURL", .text)

                // Whether app uses .pkg installer
                t.column("pkgInstaller", .boolean)
                    .notNull()
                    .defaults(to: false)

                // Warning information
                t.column("warningType", .text)
                t.column("warningDate", .text)
                t.column("warningReason", .text)

                // Analytics: downloads in last 365 days
                t.column("downloadsIn365days", .integer)
                    .notNull()
                    .defaults(to: 0)

                // When this record was last updated from API
                t.column("lastUpdated", .datetime)
                    .notNull()
            }

            // Index for filtering by tap
            try db.create(
                index: "idx_casks_tap",
                on: "casks",
                columns: ["tap"]
            )

            // Index for sorting by popularity
            try db.create(
                index: "idx_casks_downloads",
                on: "casks",
                columns: ["downloadsIn365days"]
            )
        }

        return migrator
    }

    /// Opens the database with DatabasePool for concurrent access
    private static func openDatabase() throws -> DatabasePool {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true

        // Optimize for read-heavy workload
        configuration.prepareDatabase { db in
            // Enable memory-mapped I/O for better read performance
            try db.execute(sql: "PRAGMA mmap_size = 268435456") // 256 MB
        }

        let dbPool = try DatabasePool(path: AppPaths.database.path, configuration: configuration)

        try migrator().migrate(dbPool)

        return dbPool
    }
}

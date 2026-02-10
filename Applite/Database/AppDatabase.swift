//
//  AppDatabase.swift
//  Applite
//
//  Created by Milán Várady on 2026. 02. 09..
//

import Foundation
import GRDB

struct AppDatabase {
    static let schemaVersion = 1

    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        // TODO: remove before release
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
            
            // Categories table
            try db.create(table: "categories") { t in
                t.primaryKey("id", .text) // e.g., "Browsers"
                t.column("sfSymbol", .text).notNull()
                t.column("displayOrder", .integer).notNull()
            }

            // Many-to-many relationship: categories ↔ casks
            try db.create(table: "category_casks") { t in
                t.column("categoryId", .text)
                    .notNull()
                    .references("categories", onDelete: .cascade)
                t.column("caskToken", .text)
                    .notNull()
                    .references("casks", onDelete: .cascade)

                t.primaryKey(["categoryId", "caskToken"])
            }
        }

        return migrator
    }

    static func openDatabase(at path: String) throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        
        let dbQueue = try DatabaseQueue(path: path, configuration: configuration)

        try migrator().migrate(dbQueue)

        return dbQueue
    }
}

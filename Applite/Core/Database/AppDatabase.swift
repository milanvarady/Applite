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
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: AppDatabase.self)
    )
    
    /// The shared database pool, opened lazily and **off the main actor** on first use.
    ///
    /// Opening it (file open + WAL + first-run DDL migration) can be slow on a cold disk or fresh
    /// install, so it must not run synchronously during `CaskManager` init on the main actor — that
    /// would block first paint (P2-13). The open also no longer `fatalError`s (P2-14): a failure
    /// (corrupt WAL, full disk) now propagates through the normal async DB call path and surfaces
    /// via the window's alert instead of crash-looping a non-technical user with no way out.
    private static let poolTask = Task.detached(priority: .userInitiated) { () throws -> DatabasePool in
        let pool = try openDatabase()
        logger.info("Database opened successfully")
        return pool
    }

    /// Awaits the shared database pool, kicking off (and caching) the off-main open on first call.
    static func pool() async throws -> DatabasePool {
        try await poolTask.value
    }

    /// ⚠️ Two rules for anyone adding a migration here:
    ///
    /// 1. **Never edit an applied migration's body** — GRDB identifies migrations by name and runs
    ///    each once, so editing `v1_initial` after release is a no-op for everyone who already has
    ///    the database. New installs would get the edited schema and existing ones would silently
    ///    keep the old: two schemas, one app. Add a `v2_…` instead. (Until the first release ships
    ///    this doesn't apply — nobody has the file yet, so `v1_initial` is still free to change.)
    /// 2. **Re-create the FTS5 triggers in any migration that rebuilds `casks`.** `t.synchronize(
    ///    withTable:)` below installs insert/update/delete triggers, and they live *only* in this
    ///    migration. GRDB's recommended way to alter a table is drop-and-recreate, which takes the
    ///    triggers with it — search then returns empty for upgraders, indistinguishable from "no
    ///    matches" and invisible in testing on a fresh install. Re-run `synchronize` after any
    ///    such rebuild. (P3-13)
    private static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        // Development only: rebuild from scratch when the schema changes, so dev iterations don't
        // need throwaway migrations. Deliberately NOT enabled for release — the catalog is what
        // serves an offline launch, and erasing it during an upgrade would leave an offline user
        // with an empty app until they get network back.
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        // MARK: - Migration v1: Initial Schema
        migrator.registerMigration("v1_initial") { db in
            // Main casks table
            try db.create(table: "casks") { t in
                // Primary key — the tap-qualified token (e.g. "homebrew/cask/firefox").
                //
                // The *bare* token is not unique and can't be the key: two taps may both ship a
                // "firefox", which is exactly what third-party tap support invites. Keying on it
                // meant `INSERT OR REPLACE` treated them as the same row, so whichever synced last
                // silently evicted the other (P2-29). `fullToken` is also the identity every brew
                // operation already uses.
                t.primaryKey("fullToken", .text)

                // Bare cask token (e.g. "firefox"). Not unique across taps — indexed below.
                t.column("token", .text)
                    .notNull()

                // Tap source (e.g., "homebrew/cask")
                t.column("tap", .text)
                    .notNull()

                // Display name (e.g., "Mozilla Firefox"). NOCASE so SQL-side ordering is
                // alphabetical to a human — binary collation sorts "Zoom" ahead of "aText".
                t.column("name", .text)
                    .notNull()
                    .collate(.nocase)

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
            }

            // Bare-token lookups (brew CLI reconciliation, imports) no longer ride the primary key.
            try db.create(
                index: "idx_casks_token",
                on: "casks",
                columns: ["token"]
            )

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

            // FTS5 virtual table for full-text search, synced with casks table
            try db.create(virtualTable: "cask_fts", using: FTS5()) { t in
                t.synchronize(withTable: "casks")
                t.tokenizer = .unicode61()
                // Prefix index for fast `tok*` lookups used by live search.
                t.prefixes = [2, 3]
                t.column("token")
                t.column("name")
                t.column("descriptionText")
            }

            // Metadata key/value table for app-level state (e.g. lastSyncDate)
            try db.create(table: "metadata") { t in
                t.primaryKey("key", .text)
                t.column("value", .text)
            }
        }

        return migrator
    }

    /// Opens the database with DatabasePool for concurrent access
    private static func openDatabase() throws -> DatabasePool {
        var configuration = Configuration()

        configuration.prepareDatabase { db in
            // Memory-mapped I/O speeds up reads on the catalog. The dataset
            // is small (~10k rows + FTS index), so 64 MB is plenty.
            try db.execute(sql: "PRAGMA mmap_size = 67108864")
        }
        
        try AppPaths.createApplicationSupportIfNeeded()

        let dbPool = try DatabasePool(path: AppPaths.database.path, configuration: configuration)

        try migrator().migrate(dbPool)

        return dbPool
    }
}

//
//  CategoryProvider.swift
//  Applite
//
//  Created by Milán Várady on 2026. 06. 28..
//

import Foundation
import OSLog

/// Loads the curated category list and keeps it fresh from GitHub.
///
/// The category list lives as a single `categories.json` in the repo: it is bundled into every
/// build (offline seed + permanent fallback) and fetched from `raw.githubusercontent.com` in the
/// background, so curation changes reach existing users without an app update.
///
/// Loading precedence (synchronous, no network on the hot path):
/// 1. Cached remote copy at `AppPaths.categories` — used only if it decodes, its `schemaVersion`
///    matches `supportedSchemaVersion`, and it is non-empty.
/// 2. Bundled `categories.json` — the always-present guarantee.
///
/// `refreshRemoteCategories()` is the separate, best-effort step that writes the cache. It never
/// throws into the caller, so a blocked or failing fetch can never break catalog loading.
enum CategoryProvider {
    /// Schema version this app build understands. A remote file with a different version is
    /// ignored (the bundled/cached copy keeps being used) so old apps never mis-parse new data.
    static let supportedSchemaVersion = 1

    /// The same `categories.json` contributors edit via PR, served raw from the main branch.
    static let remoteURL = URL(string: "https://raw.githubusercontent.com/milanvarady/Applite/main/Applite/Resources/categories.json")!

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: CategoryProvider.self)
    )

    // MARK: - Loading

    /// Best-effort synchronous load: cached remote copy → bundled copy.
    /// Returns `[]` only if even the bundle is unreadable (should never happen).
    static func loadCategories() -> [Category] {
        // 1. Cached remote copy
        if let data = try? Data(contentsOf: AppPaths.categories),
           let categories = decode(data) {
            return categories
        }

        // 2. Bundled fallback
        guard let url = Bundle.main.url(forResource: "categories", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let categories = decode(data) else {
            logger.error("Failed to load categories from both cache and bundle")
            return []
        }

        return categories
    }

    /// Decodes a category catalog, returning its categories only when the schema version is
    /// supported and the list is non-empty.
    private static func decode(_ data: Data) -> [Category]? {
        guard let catalog = try? JSONDecoder().decode(CategoryCatalog.self, from: data) else {
            return nil
        }
        guard catalog.schemaVersion == supportedSchemaVersion else {
            logger.notice("Ignoring category catalog with unsupported schema version \(catalog.schemaVersion)")
            return nil
        }
        guard !catalog.categories.isEmpty else {
            return nil
        }
        return catalog.categories
    }

    // MARK: - Remote Refresh

    /// Fetches the latest category list from GitHub and atomically caches it.
    /// Best-effort: validates the payload and swallows every failure (no network, blocked host,
    /// malformed JSON, incompatible schema) so the catalog sync can never be aborted by it.
    static func refreshRemoteCategories() async {
        do {
            let configuration = NetworkProxyManager.getURLSessionConfiguration()
            let session = URLSession(configuration: configuration)
            let (data, _) = try await session.data(from: remoteURL)

            // Validate before caching: must decode, match our schema, and be non-empty.
            let catalog = try JSONDecoder().decode(CategoryCatalog.self, from: data)

            guard catalog.schemaVersion == supportedSchemaVersion else {
                logger.notice("Remote category schema version \(catalog.schemaVersion) != supported \(Self.supportedSchemaVersion); keeping current categories")
                return
            }
            guard !catalog.categories.isEmpty else {
                logger.error("Remote category list is empty; keeping current categories")
                return
            }

            // Persist the original payload atomically.
            try AppPaths.createApplicationSupportIfNeeded()
            try data.write(to: AppPaths.categories, options: .atomic)

            logger.info("Refreshed category cache: \(catalog.categories.count) categories")
        } catch {
            logger.error("Failed to refresh remote categories: \(error.localizedDescription)")
        }
    }
}

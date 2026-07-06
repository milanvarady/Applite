//
//  CategoryCatalog.swift
//  Applite
//
//  Created by Milán Várady on 2026. 06. 28..
//

import Foundation

/// Decode-only wrapper for the bundled and remotely-fetched `categories.json`.
///
/// The `schemaVersion` field lets an older installed app detect a future, incompatible
/// schema and fall back to its bundled copy instead of mis-parsing newer remote data.
/// See `CategoryProvider`.
struct CategoryCatalog: Decodable {
    let schemaVersion: Int
    let categories: [Category]
}

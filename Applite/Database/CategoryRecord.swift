//
//  CategoryRecord.swift
//  Applite
//
//  Created by Milán Várady on 2026. 02. 10..
//

import Foundation
import GRDB

struct CategoryRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "categories"

    let id: String
    let sfSymbol: String
    let displayOrder: Int
}

struct CategoryCaskJoin: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "category_casks"

    let categoryId: String
    let caskToken: String
}

extension CategoryRecord {
    /// Fetches all casks in this category
    func fetchCasks(db: Database) throws -> [CaskRecord] {
        try CaskRecord.fetchAll(db, sql: """
            SELECT casks.*
            FROM casks
            JOIN category_casks ON casks.token = category_casks.caskToken
            WHERE category_casks.categoryId = ?
            ORDER BY casks.downloadsIn365days DESC
        """, arguments: [id])
    }
}

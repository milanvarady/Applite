//
//  CaskRecord.swift
//  Applite
//
//  Created by Milán Várady on 2026. 02. 10..
//

import Foundation
import GRDB

/// Represents a cask stored in the database.
struct CaskRecord: Codable, Equatable {
    // MARK: - Primary Key

    /// Unique identifier (e.g., "firefox")
    let token: String

    // MARK: - Identifiers

    /// Full token with tap prefix (e.g., "homebrew/cask/firefox")
    let fullToken: String

    /// Tap source (e.g., "homebrew/cask")
    let tap: String

    // MARK: - Display Info

    /// Display name (e.g., "Mozilla Firefox")
    let name: String

    /// Short description
    let descriptionText: String

    /// Homepage URL as string (use computed property to convert to URL)
    let homepageURL: String?

    // MARK: - Metadata

    /// True if app uses .pkg installer
    let pkgInstaller: Bool

    /// Warning type: "caveat", "deprecated", or "disabled"
    let warningType: String?

    /// Date of deprecation/disabling (ISO 8601)
    let warningDate: String?

    /// Caveat text or deprecation reason
    let warningReason: String?

    // MARK: - Analytics

    /// Number of downloads in last 365 days
    let downloadsIn365days: Int

    // MARK: - Cache Metadata

    /// When this record was last updated from the API
    let lastUpdated: Date
}

// MARK: - GRDB Protocols

extension CaskRecord: FetchableRecord, PersistableRecord {
    /// The database table name
    static let databaseTableName = "casks"
}

extension CaskRecord {
    /// Homepage as URL
    var homepage: URL? {
        homepageURL.flatMap { URL(string: $0) }
    }

    /// Reconstructs the CaskWarning enum from flattened columns
    var warning: CaskWarning? {
        guard let type = warningType else { return nil }

        switch type {
        case "caveat":
            return .hasCaveat(caveat: warningReason ?? "")
        case "deprecated":
            return .deprecated(date: warningDate ?? "", reason:
warningReason ?? "")
        case "disabled":
            return .disabled(date: warningDate ?? "", reason:
warningReason ?? "")
        default:
            return nil
        }
    }

    /// Returns true if this cask has any warning
    var hasWarning: Bool {
        warningType != nil
    }
}

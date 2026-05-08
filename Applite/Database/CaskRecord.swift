//
//  CaskRecord.swift
//  Applite
//
//  Created by Milán Várady on 2026. 02. 10..
//

import Foundation
import GRDB

/// Represents a cask stored in the database.
/// Can be decoded directly from Homebrew API JSON or fetched from SQLite.
struct CaskRecord: Equatable {
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
    var downloadsIn365days: Int
}

// MARK: - GRDB Protocols

extension CaskRecord: Codable, FetchableRecord, PersistableRecord {
    /// The database table name
    static let databaseTableName = "casks"
}

// MARK: - Computed Properties

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
            return .deprecated(date: warningDate ?? "", reason: warningReason ?? "")
        case "disabled":
            return .disabled(date: warningDate ?? "", reason: warningReason ?? "")
        default:
            return nil
        }
    }

    /// Returns true if this cask has any warning
    var hasWarning: Bool {
        warningType != nil
    }
}

// MARK: - Decoding from Homebrew API

extension CaskRecord {
    /// Creates a CaskRecord from a CaskDTO (API response object)
    init(fromDTO dto: CaskDTO, downloadsIn365days: Int = 0) {
        self.token = dto.token
        self.fullToken = dto.fullToken
        self.tap = dto.tap
        self.name = dto.nameArray.first ?? "N/A"
        self.descriptionText = dto.desc ?? "N/A"
        self.homepageURL = dto.homepage.isEmpty ? nil : dto.homepage
        self.pkgInstaller = dto.url.hasSuffix("pkg")
        self.downloadsIn365days = downloadsIn365days

        // Determine warning type
        if dto.disabled {
            self.warningType = "disabled"
            self.warningDate = dto.disableDate
            self.warningReason = dto.disableReason
        } else if dto.deprecated {
            self.warningType = "deprecated"
            self.warningDate = dto.deprecationDate
            self.warningReason = dto.deprecationReason
        } else if let caveat = dto.caveats {
            self.warningType = "caveat"
            self.warningDate = nil
            self.warningReason = caveat
        } else {
            self.warningType = nil
            self.warningDate = nil
            self.warningReason = nil
        }
    }

    /// Returns a copy with updated download count
    func withDownloads(_ downloads: Int) -> CaskRecord {
        var copy = self
        copy.downloadsIn365days = downloads
        return copy
    }
}

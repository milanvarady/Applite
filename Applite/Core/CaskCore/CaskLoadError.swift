//
//  CaskLoadError.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.31.
//

import Foundation

enum CaskLoadError: LocalizedError {
    case failedToLoadCategoryJSON
    case failedToLoadAdditionalInfo
    case failedToGetUpdateFrequency

    /// Reaches the user as an alert body (catalog-load failures are surfaced through
    /// `AlertManager`), so every case is localized.
    var errorDescription: String? {
        switch self {
        case .failedToLoadCategoryJSON:
            return String(localized: "Failed to load categories",
                          comment: "Error shown when the app category list couldn't be read")
        case .failedToLoadAdditionalInfo:
            return String(localized: "Failed to load additional info",
                          comment: "Error shown when an app's extra details couldn't be fetched")
        case .failedToGetUpdateFrequency:
            return String(localized: "Failed to get update frequency",
                          comment: "Error shown when the catalog update interval couldn't be read")
        }
    }
}

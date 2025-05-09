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

    var errorDescription: String? {
        switch self {
        case .failedToLoadCategoryJSON:
            return "Failed to load categories"
        case .failedToLoadAdditionalInfo:
            return "Failed to load additional info"
        case .failedToGetUpdateFrequency:
            return "Failed to get update frequency"
        }
    }

    var failureReason: String? {
        switch self {
        case .failedToLoadCategoryJSON:
            return "Couldn't load category JSON file"
        case .failedToLoadAdditionalInfo:
            return "The response object was empty"
        case .failedToGetUpdateFrequency:
            return "Couldn't init update frequency from raw value"
        }
    }
}

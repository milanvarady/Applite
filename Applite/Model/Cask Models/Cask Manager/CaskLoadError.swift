//
//  CaskLoadError.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.31.
//

import Foundation

enum CaskLoadError: LocalizedError {
    case failedToLoadCategoryJSON
    case failedToLoadFromCache
    case failedToLoadAdditionalInfo

    var errorDescription: String? {
        switch self {
        case .failedToLoadCategoryJSON:
            return "Failed to load categories"
        case .failedToLoadFromCache:
            return "Failed to load app catalog from cache, check your internet connection"
        case .failedToLoadAdditionalInfo:
            return "Failed to load additional info"
        }
    }

    var failureReason: String? {
        switch self {
        case .failedToLoadCategoryJSON:
            return "Couldn't load category JSON file"
        case .failedToLoadFromCache:
            return "The file doesn't exist or couldn't be read"
        case .failedToLoadAdditionalInfo:
            return "The response object was empty"
        }
    }
}

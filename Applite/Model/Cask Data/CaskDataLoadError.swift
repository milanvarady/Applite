//
//  CaskDataLoadError.swift
//  Applite
//
//  Created by Milán Várady on 2023. 07. 31..
//

import Foundation

enum CaskDataLoadError: Error {
    case loadError
    case cacheError
    case decodeError
    case shellError
    case concurrencyError
}

extension CaskDataLoadError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .loadError:   return NSLocalizedString("Load error", comment: "CaskDataLoadError")
        case .cacheError: return NSLocalizedString("Failed to load cask data from cache", comment: "CaskDataLoadError")
        case .decodeError: return NSLocalizedString("Failed to decode json data from the Homebrew API", comment: "CaskDataLoadError")
        case .shellError: return NSLocalizedString("Faild to retrieve cask information from selected brew executable", comment: "CaskDataLoadError")
        case .concurrencyError: return NSLocalizedString("Concurrency error", comment: "CaskDataLoadError")
        }
    }
}


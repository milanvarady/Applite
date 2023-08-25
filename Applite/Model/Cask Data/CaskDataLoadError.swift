//
//  CaskDataLoadError.swift
//  Applite
//
//  Created by Milán Várady on 2023. 07. 31..
//

import Foundation
import SwiftUI

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
        case .loadError:   return String(localized: "Load error")
        case .cacheError: return String(localized: "Failed to load cask data from cache")
        case .decodeError: return String(localized: "Failed to decode json data from the Homebrew API")
        case .shellError: return String(localized: "Faild to retrieve cask information from selected brew executable")
        case .concurrencyError: return String(localized: "Concurrency error")
        }
    }
}


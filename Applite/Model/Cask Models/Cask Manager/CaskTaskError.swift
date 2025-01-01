//
//  CaskTaskError.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.31.
//

import Foundation

enum CaskTaskError: LocalizedError {
    case failedToUpdateProgress

    var errorDescription: String? {
        switch self {
        case .failedToUpdateProgress:
            return "Failed to update progress state"
        }
    }

    var failureReason: String? {
        switch self {
        case .failedToUpdateProgress:
            return "The cask isn't present"
        }
    }
}

//
//  AnnexBrewError.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.25.
//

import Foundation

enum AnnexBrewError: LocalizedError {
    case invalidBrewInstallation

    /// Reaches the user as an alert body, so it's localized.
    var errorDescription: String? {
        switch self {
        case .invalidBrewInstallation:
            return String(localized: "The Brew installation seems to be invalid.",
                          comment: "Error shown when Applite's Homebrew is present but unusable")
        }
    }
}

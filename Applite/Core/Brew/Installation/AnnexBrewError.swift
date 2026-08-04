//
//  AnnexBrewError.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.25.
//

import Foundation

enum AnnexBrewError: LocalizedError {
    case invalidBrewInstallation

    var errorDescription: String? {
        switch self {
        case .invalidBrewInstallation:
            return "The Brew installation seems to be invalid."
        }
    }
}

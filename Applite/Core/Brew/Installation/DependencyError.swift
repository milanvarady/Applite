//
//  DependencyError.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.25.
//

import Foundation

enum DependencyError: LocalizedError {
    case xcodeCommandLineToolsTimeout
    case invalidBrewInstallation

    var errorDescription: String? {
        switch self {
        case .xcodeCommandLineToolsTimeout:
            return "Couldn't install Xcode Command Line Tools"
        case .invalidBrewInstallation:
            return "The Brew installation seems to be invalid."
        }
    }

    var failureReason: String? {
        switch self {
        case .xcodeCommandLineToolsTimeout:
            return "Couldn't install Xcode Command Line Tools in a reasonable amount of time"
        case .invalidBrewInstallation:
            return "brew executable is missing or invalid"
        }
    }
}

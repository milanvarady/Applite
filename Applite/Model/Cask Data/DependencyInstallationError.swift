//
//  DependencyInstallationError.swift
//  Applite
//
//  Created by Milán Várady on 2023. 09. 21..
//

import Foundation

/// Installation errors
enum DependencyInstallationError: Error {
    case CommandLineToolsError
    case DirectoryError
    case BrewFetchError
    case PinentryError
}

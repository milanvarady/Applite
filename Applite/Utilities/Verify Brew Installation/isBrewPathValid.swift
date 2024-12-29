//
//  isBrewPathValid.swift
//  Applite
//
//  Created by Milán Várady on 2023. 06. 11..
//

import Foundation

/// Checks if a brew executable path is valid or not
///
/// - Parameters:
///   - path: Path to be checked
///
/// - Returns: Whether the path is valid or not
public func isBrewPathValid(path: String) async -> Bool {
    var path = path
    
    // Add " marks so shell doesn't fail on spaces
    if !path.hasPrefix("\"") && !path.hasSuffix("\"") {
        path = "\"\(path)\""
    }
    
    // Check if path ends with brew
    if !path.hasSuffix("brew") && !path.hasSuffix("brew\"") {
        return false
    }

    // Check if Homebrew is returned when checking version
    guard let output = try? await Shell.runAsync("\(path) --version") else {
        return false
    }

    return output.contains("Homebrew")
}

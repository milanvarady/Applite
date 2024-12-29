//
//  isCommandLineToolsInstalled.swift
//  Applite
//
//  Created by Milán Várady on 2023. 06. 11..
//

import Foundation

/// Checks if Xcode Command Line Tools is installed
///
/// - Returns: Whether it is installed or not
public func isCommandLineToolsInstalled() async -> Bool {
    do {
        try await Shell.runAsync("xcode-select -p")
    } catch {
        return false
    }

    return true
}

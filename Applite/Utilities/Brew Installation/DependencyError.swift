//
//  DependencyError.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.25.
//

import Foundation

enum DependencyError: Error {
    case xcodeCommandLineToolsTimeout
}

extension DependencyError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .xcodeCommandLineToolsTimeout:
            return "Xcode Command Line Tools install timeout"
        }
    }
}

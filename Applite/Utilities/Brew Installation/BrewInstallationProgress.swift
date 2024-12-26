//
//  BrewInstallationProgress.swift
//  Applite
//
//  Created by Milán Várady on 2023. 07. 31..
//

import Foundation

public enum InstallPhase: Int {
    case waitingForXcodeCommandLineTools = 0
    case fetchingHomebrew = 1
    case done = 2
}

/// Keeps track of current brew installation progress
///
/// Used by the ``DependencyManager`` struct
@MainActor
final class BrewInstallationProgress: ObservableObject {
    @Published var phase: InstallPhase = .waitingForXcodeCommandLineTools
}

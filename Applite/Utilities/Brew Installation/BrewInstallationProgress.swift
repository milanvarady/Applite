//
//  BrewInstallationProgress.swift
//  Applite
//
//  Created by Milán Várady on 2023. 07. 31..
//

import Foundation

/// Keeps track of current brew installation progress
///
/// Used by the ``BrewInstallation`` struct
public final class BrewInstallationProgress: ObservableObject {
    public enum InstallPhase {
        case waitingForXcodeCommandLineTools
        case fetchingHomebrew
        case done
    }
    
    @Published var phase: InstallPhase = .waitingForXcodeCommandLineTools
}

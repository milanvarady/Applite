//
//  MirrorEnvironment.swift
//  Applite
//
//  Created by Milán Várady on 2025.05.09.
//

import Foundation

enum MirrorEnvironment {
    static func getEnvironmentVariables() -> [String: String]? {
        let defaults = UserDefaults.standard
        let isEnabled = defaults.value(for: Preferences.mirrorEnabled)

        guard isEnabled else { return nil }

        return [
            "HOMEBREW_API_DOMAIN": defaults.value(for: Preferences.mirrorAPIDomain),
            "HOMEBREW_BREW_GIT_REMOTE": defaults.value(for: Preferences.mirrorBrewGitRemote),
            "HOMEBREW_CORE_GIT_REMOTE": defaults.value(for: Preferences.mirrorCoreGitRemote),
            "HOMEBREW_BOTTLE_DOMAIN": defaults.value(for: Preferences.mirrorBottleDomain)
        ]
    }
}

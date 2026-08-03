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

        let variables: [String: String] = [
            "HOMEBREW_API_DOMAIN": defaults.value(for: Preferences.mirrorAPIDomain),
            "HOMEBREW_BREW_GIT_REMOTE": defaults.value(for: Preferences.mirrorBrewGitRemote),
            "HOMEBREW_CORE_GIT_REMOTE": defaults.value(for: Preferences.mirrorCoreGitRemote),
            "HOMEBREW_BOTTLE_DOMAIN": defaults.value(for: Preferences.mirrorBottleDomain)
        ]

        // Drop blanks: an empty env var is "set but empty" to brew (truthy in Ruby), which defeats
        // its own default fallback. Only forward the fields the user actually filled in (P2-21).
        let nonEmpty = variables.filter { !$0.value.isEmpty }
        return nonEmpty.isEmpty ? nil : nonEmpty
    }
}

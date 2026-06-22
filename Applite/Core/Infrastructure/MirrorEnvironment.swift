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
        let isEnabled = defaults.bool(forKey: Preferences.mirrorEnabled.rawValue)

        guard isEnabled else { return nil }

        return [
            "HOMEBREW_API_DOMAIN": defaults.string(forKey: Preferences.mirrorAPIDomain.rawValue) ?? "",
            "HOMEBREW_BREW_GIT_REMOTE": defaults.string(forKey: Preferences.mirrorBrewGitRemote.rawValue) ?? "",
            "HOMEBREW_CORE_GIT_REMOTE": defaults.string(forKey: Preferences.mirrorCoreGitRemote.rawValue) ?? "",
            "HOMEBREW_BOTTLE_DOMAIN": defaults.string(forKey: Preferences.mirrorBottleDomain.rawValue) ?? ""
        ]
    }
}

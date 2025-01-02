//
//  CaskAdditionalInfo.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.02.
//

import Foundation

struct CaskAdditionalInfoResponse: Decodable {
    let casks: [CaskAdditionalInfo]
}

struct CaskAdditionalInfo: Codable, Hashable {
    let token: String
    let tap: String
    let homepage: URL
    let url: URL
    /// Installed version
    let installed: String?
    let bundle_version: String?
    let installed_time: Date?
    let outdated: Bool?
    let auto_updates: Bool?
    let deprecated: Bool
    let deprecation_date: String?
    let deprecation_reason: String?
    let deprecation_replacement: String?
    let disabled: Bool
    let disable_date: String?
    let disable_reason: String?
    let disable_replacement: String?

    static let dummy = CaskAdditionalInfo(
        token: "Applite",        tap: "homebrew/cask",
        homepage: URL(string: "https://aerolite.dev/applite")!,
        url: URL(string: "https://github.com/milanvarady/Applite/releases/download/v1.2.5/Applite.dmg")!,
        installed: "1.2.5",
        bundle_version: "1.2.5",
        installed_time: Date(timeIntervalSince1970: 1735754762),
        outdated: false,
        auto_updates: true,
        deprecated: false,
        deprecation_date: nil,
        deprecation_reason: nil,
        deprecation_replacement: nil,
        disabled: false,
        disable_date: nil,
        disable_reason: nil,
        disable_replacement: nil
    )
}

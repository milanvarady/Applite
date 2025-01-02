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
    let installed_time: Date?
    let auto_updates: Bool?
    let deprecated: Bool
    let deprection_date: Date?
    let deprecation_reason: String?
    let deprecation_replacement: String?
    let disabled: Bool
    let disabled_date: Date?
    let disabled_reason: String?
    let disabled_replacement: String?

    static let dummy = CaskAdditionalInfo(
        token: "Applite",        tap: "homebrew/cask",
        homepage: URL(string: "https://aerolite.dev/applite")!,
        url: URL(string: "https://github.com/milanvarady/Applite/releases/download/v1.2.5/Applite.dmg")!,
        installed: "1.2.5",
        installed_time: Date(timeIntervalSince1970: 1735754762),
        auto_updates: true,
        deprecated: false,
        deprection_date: nil,
        deprecation_reason: nil,
        deprecation_replacement: nil,
        disabled: false,
        disabled_date: nil,
        disabled_reason: nil,
        disabled_replacement: nil
    )
}

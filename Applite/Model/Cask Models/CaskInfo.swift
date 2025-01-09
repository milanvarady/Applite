//
//  CaskInfo.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.29.
//

import Foundation

/// Holds all static information of a cask
struct CaskInfo: Codable {
    /// Unique id of the class, this is the same name you would use to download the cask with brew
    let token: String
    let fullToken: String
    let tap: String
    /// Longer format cask name
    let name: String
    /// Short description
    let description: String
    let homepageURL: URL?
    /// Description of any caveats with the app
    let caveats: String?
    /// If true app has a .pkg installer
    let pkgInstaller: Bool

    /// Initialize from a ``CaskDTO`` data transfer object
    init(from decoder: Decoder) throws {
        let rawData = try CaskDTO(from: decoder)

        self.token = rawData.token
        self.fullToken = rawData.fullToken
        self.tap = rawData.tap
        self.name = rawData.nameArray[safeIndex: 0] ?? "N/A"
        self.description = rawData.desc ?? "N/A"
        self.homepageURL = URL(string: rawData.homepage)
        self.caveats = rawData.caveats
        self.pkgInstaller = rawData.url.hasSuffix("pkg")
    }

    init(token: String, fullToken: String, tap: String, name: String, description: String, homepageURL: URL?, caveats: String?, pkgInstaller: Bool) {
        self.token = token
        self.fullToken = fullToken
        self.tap = tap
        self.name = name
        self.description = description
        self.homepageURL = homepageURL
        self.caveats = caveats
        self.pkgInstaller = pkgInstaller
    }
}

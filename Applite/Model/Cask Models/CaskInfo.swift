//
//  CaskInfo.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.29.
//

import Foundation

/// Holds all static information of a cask
struct CaskInfo: Codable, Identifiable, Hashable {
    /// Unique id of the class, this is the same name you would use to download the cask with brew
    let id: String
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
        let rawData = try? CaskDTO(from: decoder)

        let homepage: String = rawData?.homepage ?? "https://brew.sh/"

        self.id = rawData?.token ?? "N/A"
        self.name = rawData?.nameArray[0] ?? "N/A"
        self.description = rawData?.desc ?? "N/A"
        self.homepageURL = URL(string: homepage)
        self.caveats = rawData?.caveats
        self.pkgInstaller = rawData?.url.hasSuffix("pkg") ?? false
    }

    init(id: String, name: String, description: String, homepageURL: URL?, caveats: String?, pkgInstaller: Bool) {
        self.id = id
        self.name = name
        self.description = description
        self.homepageURL = homepageURL
        self.caveats = caveats
        self.pkgInstaller = pkgInstaller
    }
}

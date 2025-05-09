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
    /// If true app has a .pkg installer
    let pkgInstaller: Bool
    let warning: CaskWarning?

    /// Initialize from a ``CaskDTO`` data transfer object
    init(fromDTO dto: CaskDTO) throws {
        self.token = dto.token
        self.fullToken = dto.fullToken
        self.tap = dto.tap
        self.name = dto.nameArray[safeIndex: 0] ?? "N/A"
        self.description = dto.desc ?? "N/A"
        self.homepageURL = URL(string: dto.homepage)
        self.pkgInstaller = dto.url.hasSuffix("pkg")

        if dto.disabled {
            self.warning = .disabled(date: dto.disableDate ?? "N/A", reason: dto.disableReason ?? "N/A")
        } else if dto.deprecated {
            self.warning = .deprecated(date: dto.deprecationDate ?? "N/A", reason: dto.deprecationReason ?? "N/A")
        } else if let caveat = dto.caveats {
            self.warning = .hasCaveat(caveat: caveat)
        } else {
            self.warning = nil
        }
    }

    init(token: String, fullToken: String, tap: String, name: String, description: String, homepageURL: URL?, pkgInstaller: Bool, warning: CaskWarning?) {
        self.token = token
        self.fullToken = fullToken
        self.tap = tap
        self.name = name
        self.description = description
        self.homepageURL = homepageURL
        self.pkgInstaller = pkgInstaller
        self.warning = warning
    }
}

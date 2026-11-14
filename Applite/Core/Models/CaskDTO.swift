//
//  CaskDTO.swift
//  Applite
//
//  Created by Milán Várady on 2022. 11. 04..
//

import Foundation

/// Intermediate Data Transfer Object (DTO) to load in cask information.
/// Data from the json file is loaded into this object first and later passed into a ``Cask`` object
struct CaskDTO: Decodable {
    let token: String
    let fullToken: String
    let tap: String
    let nameArray: Array<String>
    let desc: String?
    let homepage: String
    let caveats: String?
    let url: String
    let deprecated: Bool
    let deprecationDate: String?
    let deprecationReason: String?
    let disabled: Bool
    let disableDate: String?
    let disableReason: String?
    let artifacts: [CaskArtifact]?

    enum CodingKeys: String, CodingKey {
        case token
        case fullToken = "full_token"
        case tap
        case nameArray = "name"
        case desc
        case homepage
        case caveats
        case url
        case deprecated
        case deprecationDate = "deprecation_date"
        case deprecationReason = "deprecation_reason"
        case disabled
        case disableDate = "disable_date"
        case disableReason = "disable_reason"
        case artifacts
    }
}

/// Only `app` artifacts identify bundles; binaries, fonts and installer packages do not.
struct CaskArtifact: Decodable {
    let app: [AppValue]?

    enum AppValue: Decodable {
        case source(String)
        case target(String?)

        private struct Options: Decodable {
            let target: String?
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let source = try? container.decode(String.self) {
                self = .source(source)
            } else {
                self = .target(try container.decode(Options.self).target)
            }
        }
    }

    var bundleName: String? {
        guard let app else { return nil }
        let target = app.compactMap { value -> String? in
            if case .target(let name) = value { return name }
            return nil
        }.first
        let source = app.compactMap { value -> String? in
            if case .source(let name) = value { return name }
            return nil
        }.first
        guard let path = target ?? source.map({ ($0 as NSString).lastPathComponent }),
              Self.isSafeAppTargetPath(path) else { return nil }
        return path
    }

    nonisolated static func isSafeAppTargetPath(_ path: String) -> Bool {
        let components = path.components(separatedBy: "/")
        return !(path as NSString).isAbsolutePath
            && !path.contains("\0")
            && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
            && (path as NSString).pathExtension == "app"
    }
}

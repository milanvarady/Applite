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

    var isFontCask: Bool {
        artifacts?.contains { $0.font?.isEmpty == false } == true
    }
}

struct CaskArtifact: Decodable {
    let font: [String]?

    private enum CodingKeys: String, CodingKey {
        case font
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.font) else {
            font = nil
            return
        }
        if try container.decodeNil(forKey: .font) {
            font = nil
            return
        }

        var arguments = try container.nestedUnkeyedContainer(forKey: .font)
        var fontPaths: [String] = []
        while !arguments.isAtEnd {
            let argument = try arguments.superDecoder()
            if let path = try? argument.singleValueContainer().decode(String.self) {
                fontPaths.append(path)
            }
        }
        font = fontPaths
    }
}

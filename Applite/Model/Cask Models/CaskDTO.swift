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
    let desc: String?
    let nameArray: Array<String>
    let homepage: String
    let caveats: String?
    let url: String
    
    enum CodingKeys: String, CodingKey {
        case token
        case desc
        case nameArray = "name"
        case homepage
        case caveats
        case url
    }
}

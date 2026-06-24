//
//  Category.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 31..
//

import Foundation

typealias CategoryId = String

/// App category object
struct Category: Decodable, Identifiable {
    /// Category id
    let id: String
    /// List of cask ids
    let casks: [CaskId]
    /// SF Symbol of the category
    let sfSymbol: String
}

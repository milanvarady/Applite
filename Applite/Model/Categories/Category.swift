//
//  Category.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 31..
//

import Foundation

/// Holds the app categories
let categories: [Category] = loadLocalJson(fileName: "categories")!

/// App category object
struct Category: Decodable, Identifiable {
    /// Category id
    let id: String
    /// List of cask ids
    let casks: [String]
    /// SF Symbol of the category
    let sfSymbol: String
}

/// Loads a json from resources
fileprivate func loadLocalJson(fileName: String) -> [Category]? {
   let decoder = JSONDecoder()
   guard
        let url = Bundle.main.url(forResource: fileName, withExtension: "json"),
        let data = try? Data(contentsOf: url),
        let categories = try? decoder.decode([Category].self, from: data)
   else {
        return nil
   }

   return categories
}

//
//  Cask+Searchable.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.02.
//

import Foundation

extension Cask: FuzzySearchable {
    nonisolated var searchProperties: [FuzzySearchProperty] {
        return [
            FuzzySearchProperty(self.info.name, weight: 1),
            FuzzySearchProperty(self.info.token, weight: 1),
            FuzzySearchProperty(self.info.description, weight: 0.3)
        ]
    }
}

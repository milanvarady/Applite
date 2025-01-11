//
//  Cask+Searchable.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.02.
//

import Foundation
import Ifrit

extension Cask: Searchable {
    nonisolated var weightedSearchProperties: [FuseProp] {
        return [
            FuseProp(self.info.name, weight: 1),
            FuseProp(self.info.token, weight: 1),
            FuseProp(self.info.description, weight: 0.3)
        ]
    }
}

//
//  Cask+Comparable.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.11.
//

import Foundation

extension Cask: Comparable {
    nonisolated static func < (lhs: Cask, rhs: Cask) -> Bool {
        lhs.info.name < rhs.info.name
    }
}

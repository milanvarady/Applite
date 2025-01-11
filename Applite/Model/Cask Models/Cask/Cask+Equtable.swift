//
//  Cask+Equtable.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.11.
//

import Foundation

extension Cask: Equatable {
    nonisolated static func == (lhs: Cask, rhs: Cask) -> Bool {
        lhs.id == rhs.id
    }
}

//
//  Cask+ProtocolConformances.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.27.
//

import Foundation

extension Cask {
    // Equatable
    nonisolated static func == (lhs: Cask, rhs: Cask) -> Bool {
        lhs.id == rhs.id
    }

    // Hashable
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }
}

//
//  Cask+Hashable.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.11.
//

import Foundation

extension Cask: Hashable {
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }
}

//
//  CategoryViewModel.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.01.
//

import SwiftUI

struct CategoryViewModel: Identifiable, Equatable, Hashable, Sendable {
    let name: String
    let sfSymbol: String
    let casks: [Cask]
    let casksCoupled: [[Cask]]

    var id: String { sfSymbol }

    func hash(into hasher: inout Hasher) {
        hasher.combine(sfSymbol)
    }
}

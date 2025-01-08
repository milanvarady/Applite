//
//  CategoryViewModel.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.01.
//

import SwiftUI

struct CategoryViewModel: Identifiable, Equatable, Hashable {
    let name: LocalizedStringKey
    let sfSymbol: String
    let casks: [Cask]
    let casksCoupled: [[Cask]]

    var id: String { sfSymbol }

    func hash(into hasher: inout Hasher) {
        hasher.combine(sfSymbol)
    }
}

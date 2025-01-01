//
//  CategoryViewModel.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.01.
//

import Foundation

struct CategoryViewModel: Identifiable, Equatable, Hashable {
    let name: String
    let sfSymbol: String
    let casks: [Cask]
    let casksCoupled: [[Cask]]

    var id: String { name }
}

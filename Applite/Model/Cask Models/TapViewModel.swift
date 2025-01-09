//
//  TapViewModel.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.09.
//

import Foundation

struct TapViewModel: Identifiable, Equatable, Hashable {
    let tapId: TapId
    let caskCollection: SearchableCaskCollection

    var title: String {
        tapId.components(separatedBy: "/").last ?? "?"
    }

    var id: TapId {
        tapId
    }

    static func == (lhs: TapViewModel, rhs: TapViewModel) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

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
        // If tap name short enough or if it's ambigous (it only says tap) we show the full name
        // Otherwise if the name is too long we just show the part after the "/"
        if tapId.count < 16 || tapComponent.lowercased() == "tap" {
            return tapId
        } else {
            return tapComponent
        }
    }

    var userCompnent: String {
        tapId.components(separatedBy: "/").first ?? ""
    }

    var tapComponent: String {
        tapId.components(separatedBy: "/").last ?? ""
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

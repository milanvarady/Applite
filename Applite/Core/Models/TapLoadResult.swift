//
//  TapLoadResult.swift
//  Applite
//
//  Created by Milán Várady on 2026. 05. 10..
//

import Foundation

/// A third-party tap with its resolved view models.
///
/// Same equality contract as `CategoryLoadResult`: include `casks` for SwiftUI updates,
/// hash by `id` only.
struct TapLoadResult {
    let id: String
    let casks: [CaskViewModel]

    var title: String {
        let tapComponent = id.components(separatedBy: "/").last ?? ""
        if id.count < 16 || tapComponent.lowercased() == "tap" {
            return id
        } else {
            return tapComponent
        }
    }
}

extension TapLoadResult: Identifiable {}

extension TapLoadResult: Equatable {
    static func == (lhs: TapLoadResult, rhs: TapLoadResult) -> Bool {
        lhs.id == rhs.id && lhs.casks == rhs.casks
    }
}

extension TapLoadResult: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

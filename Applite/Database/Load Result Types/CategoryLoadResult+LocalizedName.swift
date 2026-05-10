//
//  CategoryLoadResult+LocalizedName
//  Applite
//
//  Created by Milán Várady on 2025.05.09.
//

import SwiftUI

/// A category with its resolved view models.
struct CategoryLoadResult {
    let id: String
    let sfSymbol: String
    let casks: [CaskViewModel]
}

// MARK: -  Protocol conformances

extension CategoryLoadResult: Identifiable {}

// `==` includes `casks` so SwiftUI re-renders when the placeholder state
// (empty casks at launch) is replaced with the full result after stage 1.
extension CategoryLoadResult: Equatable {
    static func == (lhs: CategoryLoadResult, rhs: CategoryLoadResult) -> Bool {
        lhs.id == rhs.id && lhs.casks == rhs.casks
    }
}

extension CategoryLoadResult: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension CategoryLoadResult {
    var localizedName: LocalizedStringKey {
        LocalizedStringKey(self.id)
    }

    var name: String { id }

    /// Casks grouped in pairs for the discover section scroll view
    var casksCoupled: [[CaskViewModel]] {
        stride(from: 0, to: casks.count, by: 2).map { i in
            Array(casks[i..<min(i + 2, casks.count)])
        }
    }
}

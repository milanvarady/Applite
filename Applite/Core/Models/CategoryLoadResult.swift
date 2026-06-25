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

    /// Casks ordered according to the global sorting preference.
    @MainActor
    func sortedCasks(by option: CategorySortingOptions) -> [CaskViewModel] {
        switch option {
        case .mostDownloaded:
            return casks.sorted { $0.downloadsIn365days > $1.downloadsIn365days }
        case .aToZ:
            return casks.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    /// Sorted casks grouped in pairs for the discover section scroll view
    @MainActor
    func casksCoupled(by option: CategorySortingOptions) -> [[CaskViewModel]] {
        let sorted = sortedCasks(by: option)
        return stride(from: 0, to: sorted.count, by: 2).map { i in
            Array(sorted[i..<min(i + 2, sorted.count)])
        }
    }
}

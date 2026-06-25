//
//  CategorySortingOptions.swift
//  Applite
//
//  Created by Milán Várady on 2026.06.25.
//

import SwiftUI

/// How apps inside a category are ordered. Applies globally across the Discover
/// and Category views (stored in `Preferences.categorySortOption`).
enum CategorySortingOptions: String, CaseIterable, Identifiable {
    case mostDownloaded
    case aToZ

    var id: CategorySortingOptions { self }

    var description: LocalizedStringKey {
        switch self {
        case .mostDownloaded: return "Most downloaded (default)"
        case .aToZ: return "A to Z"
        }
    }
}

//
//  CategorySortingToolbar.swift
//  Applite
//
//  Created by Milán Várady on 2026.06.25.
//

import SwiftUI

/// Toolbar picker that controls how apps inside categories are sorted.
/// Shared by `DiscoverView` and `CategoryView`; the choice is a global preference.
struct CategorySortingToolbar: ToolbarContent {
    @AppStorage(Preferences.categorySortOption) var sortBy

    var body: some ToolbarContent {
        ToolbarItem {
            Menu {
                Picker("Sort By", selection: $sortBy) {
                    ForEach(CategorySortingOptions.allCases) { option in
                        Text(option.description)
                            .tag(option)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Category Sorting Options", systemImage: "slider.horizontal.3")
                    .labelStyle(.titleAndIcon)
            }
        }
    }
}

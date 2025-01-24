//
//  HomeView+SortingOptions.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.12.
//

import SwiftUI

extension HomeView {
    struct SortingOptionsToolbar: ToolbarContent {
        // Sorting options
        @AppStorage(Preferences.searchSortOption.rawValue) var sortBy = SortingOptions.mostDownloaded
        @AppStorage(Preferences.hideUnpopularApps.rawValue) var hideUnpopularApps = false
        @AppStorage(Preferences.hideDisabledApps.rawValue) var hideDisabledApps = false

        var body: some ToolbarContent {
            ToolbarItem {
                Menu {
                    Picker("Sort By", selection: $sortBy) {
                        ForEach(SortingOptions.allCases) { option in
                            Text(option.description)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.inline)

                    Toggle(isOn: $hideUnpopularApps) {
                        Text("Hide apps with few downloads", comment: "Few downloads search filter")
                    }

                    Toggle(isOn: $hideDisabledApps) {
                        Text("Hide disabled apps", comment: "Disabled apps search filter")
                    }
                } label: {
                    Label("Search Sorting Options", systemImage: "slider.horizontal.3")
                        .labelStyle(.titleAndIcon)
                }
            }
        }
    }
}

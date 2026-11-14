//
//  SortingOptionsToolbar.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.12.
//

import SwiftUI

struct SortingOptionsToolbar: ToolbarContent {
    @Binding var externalOnly: Bool
    var externalCount: Int
    @AppStorage(Preferences.detectExternallyInstalledApps) private var detectExternallyInstalledApps
    @AppStorage(Preferences.searchSortOption) var sortBy
    @AppStorage(Preferences.hideUnpopularApps) var hideUnpopularApps
    @AppStorage(Preferences.hideDisabledApps) var hideDisabledApps

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

                if detectExternallyInstalledApps {
                    Toggle(isOn: $externalOnly) {
                        HStack {
                            Text("Installed externally")
                            Spacer()
                            Text(externalCount, format: .number)
                        }
                    }
                }

                Divider()

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

//
//  DownloadView+SortingOptions.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension DownloadView {
    var sortingOptions: some ToolbarContent {
        ToolbarItem {
            Menu {
                Picker("Sort by", selection: $sortBy) {
                    ForEach(SortingOptions.allCases) { option in
                        Text(option.description)
                            .tag(option)
                    }
                }
                .pickerStyle(.inline)
                
                Toggle(isOn: $hideUnpopularApps) {
                    Text("Hide apps with few downloads", comment: "Few downloads search filter")
                }
            } label: {
                Label("Search Sorting Options", systemImage: "slider.horizontal.3")
                    .labelStyle(.titleAndIcon)
            }
        }
    }
}

//
//  InstalledView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 14..
//

import SwiftUI

/// Shows installed apps, where the user can open and uninstall them
struct InstalledView: View {
    var casks: [CaskViewModel]

    @Environment(CaskManager.self) private var caskManager

    @State private var searchText = ""
    @AppStorage(Preferences.installedSortOption) private var sortBy
    @AppStorage(Preferences.installedSourceFilter) private var source
    @AppStorage(Preferences.installedUpdatesOnly) private var updatesOnly

    var body: some View {
        let options = InstalledListOptions(sortOrder: sortBy, source: source, updatesOnly: updatesOnly)
        let displayed = options.apply(to: casks, query: searchText)
        return VStack {
            if casks.isEmpty && caskManager.isResolvingInstalledState {
                ProgressView()
            } else if casks.isEmpty {
                ContentUnavailableView(
                    "No installed apps found.",
                    systemImage: "app.badge.checkmark"
                )
            } else if displayed.isEmpty {
                ContentUnavailableView {
                    Label("No matching installed apps", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Try another search or reset your filters.")
                } actions: {
                    Button("Show All Installed Apps") {
                        searchText = ""
                        source = .all
                        updatesOnly = false
                    }
                }
            } else {
                AppGridView(casks: displayed, appRole: .installed)
            }
        }
        .navigationTitle("Installed")
        .searchable(text: $searchText, placement: .toolbar)
        .toolbar {
            ToolbarItem {
                Menu {
                    Text("Showing \(displayed.count) of \(casks.count) apps")

                    Picker("Sort By", selection: $sortBy) {
                        ForEach(InstalledListOptions.SortOrder.allCases) { option in
                            Text(option.description)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.inline)

                    Divider()

                    Picker("App Source", selection: $source) {
                        ForEach(InstalledListOptions.Source.allCases) { option in
                            Text(option.description)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.inline)

                    Toggle("Updates available only", isOn: $updatesOnly)

                    Divider()

                    Button("Reset Sorting and Filters") {
                        sortBy = Preferences.installedSortOption.defaultValue
                        source = Preferences.installedSourceFilter.defaultValue
                        updatesOnly = Preferences.installedUpdatesOnly.defaultValue
                    }
                    .disabled(!options.hasFilters && sortBy == .aToZ)
                } label: {
                    Label("Sort & Filter", systemImage: "slider.horizontal.3")
                        .labelStyle(.titleAndIcon)
                }
                .help("Sort and filter installed apps")
            }
        }
    }
}

#Preview {
    InstalledView(casks: Array(repeating: .dummy, count: 8))
}

//
//  DownloadView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 14..
//

import SwiftUI
import DebouncedOnChange

/// Download section. Either dispays the `DiscoverView` or search results
struct DownloadView: View {
    @Binding var navigationSelection: SidebarItem
    @Binding var searchText: String
    @ObservedObject var caskCollection: SearchableCaskCollection

    @State var searchInProgress = false

    // Sorting options
    @AppStorage("searchSortOption") var sortBy = SortingOptions.mostDownloaded
    @AppStorage("hideUnpopularApps") var hideUnpopularApps = false

    enum SortingOptions: String, CaseIterable, Identifiable {
        case mostDownloaded
        case bestMatch
        case aToZ

        var id: SortingOptions { self }

        var description: String {
            switch self {
            case .mostDownloaded: return "Most downloaded (default)"
            case .bestMatch: return "Best match"
            case .aToZ: return "A to Z"
            }
        }
    }
    
    var body: some View {
        ScrollView {
            if searchText.isEmpty {
                DiscoverView(navigationSelection: $navigationSelection)
            } else {
                if searchInProgress {
                    ProgressView("Searching...")
                        .padding(.top, 60)
                } else {
                    AppGridView(casks: caskCollection.casksMatchingSearch, appRole: .installAndManage)
                        .padding()

                    // If search result is empty
                    if caskCollection.casksMatchingSearch.isEmpty {
                        noSearchResults
                            .frame(maxWidth: 800)
                            .padding()
                    }
                }
            }
        }
        .task {
            if !searchText.isEmpty {
                await searchAndSort()
            }
        }
        .task(id: searchText) {
            await searchAndSort()
        }
        // Apply sorting options
        .task(id: sortBy) {
            // Refilter if sorting options change
            await sortCasks(ignoreBestMatch: false)
        }
        // Apply filter option
        .task(id: hideUnpopularApps) {
            if hideUnpopularApps {
                await filterUnpopular()
            } else {
                await caskCollection.search(query: searchText)
            }
        }
        .toolbar {
            sortingOptions
        }
    }

    private func searchAndSort() async {
        searchInProgress = true

        await caskCollection.search(query: searchText, diffScroreThreshold: 0.3, limitResults: 25)
        if hideUnpopularApps { await filterUnpopular() }
        await sortCasks(ignoreBestMatch: true)

        searchInProgress = false
    }

    private func filterUnpopular(threshold: Int = 500) async {
        caskCollection.filterSearch { casks in
            casks.filter { $0.downloadsIn365days > threshold }
        }
    }

    private func sortCasks(ignoreBestMatch: Bool) async {
        switch sortBy {
        case .bestMatch:
            if !ignoreBestMatch {
                await caskCollection.search(query: searchText)
            }
        case .aToZ:
            caskCollection.filterSearch { casks in
                casks.sorted { $0.info.name < $1.info.name }
            }
        case .mostDownloaded:
            caskCollection.filterSearch { casks in
                casks.sorted { $0.downloadsIn365days > $1.downloadsIn365days }
            }
        }
    }
}

struct DownloadView_Previews: PreviewProvider {
    static var previews: some View {
        DownloadView(
            navigationSelection: .constant(.home),
            searchText: .constant(""),
            caskCollection: .init(casks: Array(repeating: .dummy, count: 8))
        )
    }
}

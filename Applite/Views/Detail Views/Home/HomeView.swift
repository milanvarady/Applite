//
//  HomeView.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.12.
//

import SwiftUI

struct HomeView: View {
    @Binding var navigationSelection: SidebarItem
    @Binding var searchText: String
    @Binding var showSearchResults: Bool
    var searchResults: [CaskViewModel]

    var body: some View {
        VStack {
            if showSearchResults {
                if searchResults.isEmpty {
                    NoSearchResults(searchText: $searchText)
                } else {
                    AppGridView(casks: searchResults, appRole: .installAndManage)
                }
            } else {
                DiscoverView(navigationSelection: $navigationSelection)
            }
        }
        .toolbar {
            SortingOptionsToolbar()
        }
    }
}

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
    @ObservedObject var caskCollection: SearchableCaskCollection

    var body: some View {
        VStack {
            if showSearchResults {
                if caskCollection.casksMatchingSearch.isEmpty {
                    NoSearchResults(searchText: $searchText)
                } else {
                    AppGridView(casks: caskCollection.casksMatchingSearch, appRole: .installAndManage)
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

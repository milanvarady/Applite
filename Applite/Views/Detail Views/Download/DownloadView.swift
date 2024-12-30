//
//  DownloadView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 14..
//

import SwiftUI
import Fuse

/// Download section. Either dispays the `DiscoverView` or search results
struct DownloadView: View {
    @Binding var navigationSelection: SidebarItem
    @Binding var searchText: String
    
    @EnvironmentObject var caskData: CaskData
    
    @State var searchResults: [Cask] = []
    
    // Sorting options
    @State var hideUnpopularApps = false
    @State var sortBy = SortingOptions.mostDownloaded
    
    enum SortingOptions: String, CaseIterable, Identifiable {
        case mostDownloaded = "Most downloaded (default)"
        case aToZ = "A-Z"
        
        var id: SortingOptions { self }
    }
    
    let fuseSearch = Fuse()
    
    var body: some View {
        ScrollView {
            if searchText.isEmpty {
                DiscoverView(navigationSelection: $navigationSelection)
            } else {
                AppGridView(casks: searchResults, appRole: .installAndManage)
                    .padding()
                
                // If search result is empty
                if searchResults.isEmpty {
                    noSearchResults
                        .frame(maxWidth: 800)
                        .padding()
                }
            }
        }
        .onChange(of: searchText) { newSearchText in
            // Filter apps
            searchResults = fuzzyFilter(casks: caskData.casks, searchText: newSearchText)
        }
        .onChange(of: sortBy) { _newValue in
            // Refilter if sorting options change
            search()
        }
        .onChange(of: hideUnpopularApps) { _newValue in
            // Refilter if sorting options change
            search()
        }
        .onAppear { search() }
        .toolbar {
            sortingOptions
        }
    }
}

struct DownloadView_Previews: PreviewProvider {
    static var previews: some View {
        DownloadView(navigationSelection: .constant(.home), searchText: .constant(""))
            .environmentObject(CaskData())
    }
}

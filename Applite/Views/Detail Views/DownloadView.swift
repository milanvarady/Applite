//
//  DownloadView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 14..
//

import SwiftUI
import Fuse
import Combine

/// Download section. Either dispays the `DiscoverView` or search results
struct DownloadView: View {
    @Binding var navigationSelection: String
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
                    VStack {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.red)
                                .font(.system(size: 32))

                            Text("\"\(searchText)\" didn't match any app. Either it's not available in the Homebrew catalog or you misspelled it.")
                                .font(.system(size: 20))
                        }

                        .padding(.bottom)
                        
                        // Turn of filtering
                        if hideUnpopularApps {
                            Button {
                                hideUnpopularApps = false
                            } label: {
                                Label("Turn off few downloads filter", systemImage: "slider.horizontal.2.square.on.square")
                            }
                            .bigButton()
                            .help("Apps with few downloads are hidden, consider turning off this filter")
                        }
                    }
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
            // Sorting options
            ToolbarItem {
                Menu {
                    Picker("Sort by", selection: $sortBy) {
                        ForEach(SortingOptions.allCases) { option in
                            Text(LocalizedStringKey(option.rawValue)).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    
                    Toggle(isOn: $hideUnpopularApps) {
                        Text("Hide apps with few downloads")
                    }
                } label: {
                    Label("Sorting Options", systemImage: "slider.horizontal.3")
                        .labelStyle(.titleAndIcon)
                }
            }
        }
    }
    
    /// Filters a list of casks
    ///
    /// - Parameters:
    ///   - casks: List of ``Cask`` objects to filter
    ///   - searchText: Search query
    /// - Returns: List of filtered casks
    func fuzzyFilter(casks: [Cask], searchText: String) -> [Cask] {
        var casks = casks
        
        if searchText.isEmpty {
            casks = caskData.casks
        } else {
            // A score of 0 means a perfect match, a score of one matches everything
            casks = caskData.casks.filter {
                ($0.name.lowercased().contains(searchText.lowercased()) || $0.description.lowercased().contains(searchText.lowercased())) ||
                (fuseSearch.search(searchText.lowercased(), in: $0.name.lowercased())?.score ?? 1) < 0.25 ||
                (fuseSearch.search(searchText.lowercased(), in: $0.description.lowercased())?.score ?? 1) < 0.25
            }
        }
        
        // Filters
        if sortBy == .mostDownloaded {
            casks = casks.sorted(by: { $0.downloadsIn365days > $1.downloadsIn365days })
        }
        
        if hideUnpopularApps {
            casks = casks.filter {
                $0.downloadsIn365days > 500
            }
        }
        
        return casks
    }
    
    public func search() {
        self.searchResults = fuzzyFilter(casks: caskData.casks, searchText: searchText)
    }
}

struct DownloadView_Previews: PreviewProvider {
    static var previews: some View {
        DownloadView(navigationSelection: .constant(""), searchText: .constant(""))
            .environmentObject(CaskData())
    }
}

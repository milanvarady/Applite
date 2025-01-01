//
//  DownloadView+Search.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension DownloadView {
    /// Filters a list of casks
    ///
    /// - Parameters:
    ///   - casks: List of ``Cask`` objects to filter
    ///   - searchText: Search query
    /// - Returns: List of filtered casks
    func fuzzyFilter(casks: [Cask], searchText: String) -> [Cask] {
        var filteredCasks = casks

        if searchText.isEmpty {
            filteredCasks = casks
        } else {
            // A score of 0 means a perfect match, a score of one matches everything
            filteredCasks = casks.filter {
                ($0.info.name.lowercased().contains(searchText.lowercased()) || $0.info.description.lowercased().contains(searchText.lowercased())) ||
                (fuseSearch.search(searchText.lowercased(), in: $0.info.name.lowercased())?.score ?? 1) < 0.25 ||
                (fuseSearch.search(searchText.lowercased(), in: $0.info.description.lowercased())?.score ?? 1) < 0.25
            }
        }

        // Filters
        if sortBy == .mostDownloaded {
            filteredCasks = casks.sorted(by: { $0.downloadsIn365days > $1.downloadsIn365days })
        }

        if hideUnpopularApps {
            filteredCasks = casks.filter {
                $0.downloadsIn365days > 500
            }
        }

        return filteredCasks
    }

    func search() {
        self.searchResults = fuzzyFilter(casks: Array(caskManager.casks.values), searchText: searchText)
    }
}

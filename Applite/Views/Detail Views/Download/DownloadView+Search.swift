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

    func search() {
        self.searchResults = fuzzyFilter(casks: caskData.casks, searchText: searchText)
    }
}

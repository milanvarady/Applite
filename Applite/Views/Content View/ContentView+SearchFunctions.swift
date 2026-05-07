//
//  ContentView+SearchFunctions.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.12.
//

import SwiftUI

extension ContentView {
    func searchAndSort() {
        guard !searchInput.isEmpty else {
            searchResults = []
            return
        }

        do {
            searchResults = try caskManager.search(query: searchInput)
        } catch {
            logger.error("Search failed: \(error.localizedDescription)")
            searchResults = []
        }

        applyFilters()
        sortCasks(ignoreBestMatch: true)
    }

    func reapplyFilters() {
        // Re-run search to get fresh results, then filter
        if !searchInput.isEmpty {
            do {
                searchResults = try caskManager.search(query: searchInput)
            } catch {
                logger.error("Search failed: \(error.localizedDescription)")
            }
        }
        applyFilters()
    }

    private func applyFilters() {
        if hideUnpopularApps {
            searchResults = searchResults.filter { $0.downloadsIn365days > 500 }
        }
        if hideDisabledApps {
            searchResults = searchResults.filter { !($0.warning?.isDisabled ?? false) }
        }
    }

    func sortCasks(ignoreBestMatch: Bool) {
        switch sortBy {
        case .bestMatch:
            if !ignoreBestMatch {
                // Re-run search to get FTS5 ranking order
                searchAndSort()
            }
        case .aToZ:
            searchResults.sort { $0.name < $1.name }
        case .mostDownloaded:
            searchResults.sort { $0.downloadsIn365days > $1.downloadsIn365days }
        }
    }
}

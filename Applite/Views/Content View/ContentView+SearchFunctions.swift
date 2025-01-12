//
//  ContentView+SearchFunctions.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.12.
//

import SwiftUI

extension ContentView {
    func searchAndSort() async {
        await caskManager.allCasks.search(query: searchInput, diffScroreThreshold: 0.3, limitResults: 25)
        if hideUnpopularApps { await filterUnpopular() }
        await sortCasks(ignoreBestMatch: true)
    }

    func filterUnpopular(threshold: Int = 500) async {
        caskManager.allCasks.filterSearch { casks in
            casks.filter { $0.downloadsIn365days > threshold }
        }
    }

    func sortCasks(ignoreBestMatch: Bool) async {
        switch sortBy {
        case .bestMatch:
            if !ignoreBestMatch {
                await caskManager.allCasks.search(query: searchInput)
            }
        case .aToZ:
            caskManager.allCasks.filterSearch { casks in
                casks.sorted { $0.info.name < $1.info.name }
            }
        case .mostDownloaded:
            caskManager.allCasks.filterSearch { casks in
                casks.sorted { $0.downloadsIn365days > $1.downloadsIn365days }
            }
        }
    }
}

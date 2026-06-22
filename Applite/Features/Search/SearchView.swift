//
//  SearchView.swift
//  Applite
//
//  Created by Milán Várady on 2026.05.07.
//

import SwiftUI
import OSLog

/// Detail view that shows FTS5 search results, debounced live as the user types.
/// Not associated with any sidebar tab — `ContentView` swaps to it whenever
/// `searchInput` is non-empty, and back to the previous tab when cleared.
struct SearchView: View {
    @Binding var query: String

    @Environment(CaskManager.self) private var caskManager

    @State private var results: [CaskViewModel] = []
    @State private var isSearching = false

    @AppStorage(Preferences.searchSortOption.rawValue) private var sortBy = SortingOptions.mostDownloaded
    @AppStorage(Preferences.hideUnpopularApps.rawValue) private var hideUnpopularApps = false
    @AppStorage(Preferences.hideDisabledApps.rawValue) private var hideDisabledApps = false

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: SearchView.self)
    )

    var body: some View {
        Group {
            if displayedResults.isEmpty && !isSearching {
                ContentUnavailableView.search(text: query)
            } else {
                AppGridView(casks: displayedResults, appRole: .installAndManage)
            }
        }
        .overlay(alignment: .top) {
            if isSearching {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 8)
            }
        }
        .toolbar { SortingOptionsToolbar() }
        .task(id: query) {
            // Debounce: wait for the user to stop typing before hitting FTS5.
            // .task(id:) cancels the previous task on each query change, so the
            // sleep is the debounce window.
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }

            isSearching = true
            defer { isSearching = false }

            do {
                results = try await caskManager.search(query: query)
            } catch is CancellationError {
                return
            } catch {
                Self.logger.error("Search failed: \(error.localizedDescription)")
                results = []
            }
        }
    }

    private var displayedResults: [CaskViewModel] {
        var filtered = results
        if hideUnpopularApps {
            filtered.removeAll { $0.downloadsIn365days <= 500 }
        }
        if hideDisabledApps {
            filtered.removeAll { $0.warning?.isDisabled ?? false }
        }
        switch sortBy {
        case .bestMatch:
            // FTS5 already returns rows in BM25 order — preserve it.
            break
        case .aToZ:
            filtered.sort { $0.name < $1.name }
        case .mostDownloaded:
            filtered.sort { $0.downloadsIn365days > $1.downloadsIn365days }
        }
        return filtered
    }
}

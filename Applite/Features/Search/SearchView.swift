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
    @State private var installedOnly = false

    @AppStorage(Preferences.searchSortOption) private var sortBy
    @AppStorage(Preferences.hideUnpopularApps) private var hideUnpopularApps
    @AppStorage(Preferences.hideDisabledApps) private var hideDisabledApps

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: SearchView.self)
    )

    var body: some View {
        // Filter + sort once per body pass instead of twice (empty-check and grid) (D4).
        let displayed = displayedResults
        return Group {
            if displayed.isEmpty && !isSearching {
                if installedOnly && caskManager.locallyInstalledCount == 0 {
                    ContentUnavailableView(
                        "No installed apps found.",
                        systemImage: "app.badge.checkmark"
                    )
                } else {
                    ContentUnavailableView.search(text: query)
                }
            } else {
                AppGridView(casks: displayed, appRole: .installAndManage)
            }
        }
        .overlay(alignment: .top) {
            if isSearching {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 8)
            }
        }
        .toolbar {
            SortingOptionsToolbar(
                installedOnly: $installedOnly,
                installedCount: caskManager.locallyInstalledCount
            )
        }
        .task(id: [query, installedOnly ? "installed" : "all"]) {
            // Debounce: wait for the user to stop typing before hitting FTS5.
            // .task(id:) cancels the previous task on each query change, so the
            // sleep is the debounce window.
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }

            isSearching = true
            defer { isSearching = false }

            do {
                results = try await caskManager.search(query: query, installedOnly: installedOnly)
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
        if installedOnly {
            let installed = Dictionary(grouping: caskManager.locallyInstalledViewModels, by: \.fullToken)
            filtered = filtered.flatMap { installed[$0.fullToken] ?? [] }
        }
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

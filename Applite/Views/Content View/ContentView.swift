//
//  ContentView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 09. 24..
//

import SwiftUI
import OSLog

struct ContentView: View {
    @EnvironmentObject var caskManager: CaskManager
    
    /// Currently selected tab in the sidebar
    @State var selection: SidebarItem = .home

    @StateObject var loadAlert = AlertManager()

    @State var brokenInstall = false
    
    /// If true the sidebar is disabled
    @State var modifyingBrew = false

    /// App search query
    @State var searchInput = ""
    @State var showSearchResults = false

    // Sorting options
    @AppStorage("searchSortOption") var sortBy = SortingOptions.mostDownloaded
    @AppStorage("hideUnpopularApps") var hideUnpopularApps = false

    let logger = Logger()

    var body: some View {
        NavigationSplitView {
            sidebarViews
                .disabled(modifyingBrew)
        } detail: {
            detailView
        }
        // Load all cask releated data
        .task {
            await loadCasks()
        }
        // MARK: - Search
        .searchable(text: $searchInput, placement: .sidebar)
        // Submit search
        .onSubmit(of: .search) {
            Task {
                await searchAndSort()

                if !searchInput.isEmpty {
                    showSearchResults = true

                    if selection != .home {
                        selection = .home
                    }
                }
            }
        }
        // Clear search
        .onChange(of: searchInput) { newValue in
            // Limit search characters
            searchInput = String(searchInput.prefix(30))

            if searchInput.isEmpty {
                showSearchResults = false
            }
        }
        // Apply sorting options
        .task(id: sortBy) {
            // Refilter if sorting options change
            await sortCasks(ignoreBestMatch: false)
        }
        // Apply filter option
        .task(id: hideUnpopularApps) {
            if hideUnpopularApps {
                await filterUnpopular()
            } else {
                await caskManager.allCasks.search(query: searchInput)
            }
        }
        // Load failure alert
        .alert(loadAlert.title, isPresented: $loadAlert.isPresented) {
            Button {
                Task { @MainActor in
                    await loadCasks()
                }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }

            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(self)
            }

            Button("OK", role: .cancel) { }
        } message: {
            Text(loadAlert.message)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

//
//  ContentView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 09. 24..
//

import SwiftUI
import ButtonKit

struct ContentView: View {
    @Environment(CaskManager.self) var caskManager

    /// Currently selected sidebar item. Optional so the selection can be cleared
    /// while a search is active, so a sidebar tap can interrupt the search instead
    /// of being swallowed by the SearchView in the detail pane.
    @State var selection: SidebarItem? = .home

    /// Remembers the last non-nil selection so that clearing the search field
    /// (e.g. via Esc) can restore the user to the screen they were on.
    @State var lastSelection: SidebarItem = .home

    /// If true the sidebar is disabled
    @State var modifyingBrew = false

    /// App search query
    @State var searchInput = ""

    var body: some View {
        @Bindable var caskManager = caskManager

        NavigationSplitView {
            SidebarViews(selection: $selection)
                .disabled(modifyingBrew)
        } detail: {
            if caskManager.hasBrokenInstall {
                BrokenInstallView()
            } else if !searchInput.isEmpty {
                SearchView(query: $searchInput)
            } else if selection != nil {
                DetailViews(
                    selection: $selection,
                    modifyingBrew: $modifyingBrew
                )
            }
        }
        .task {
            await caskManager.loadData()
        }
        // MARK: - Search
        .searchable(text: $searchInput, placement: .sidebar)
        .onChange(of: searchInput) { _, newValue in
            // Limit search characters
            if newValue.count > 30 {
                searchInput = String(newValue.prefix(30))
                return
            }

            if !newValue.isEmpty {
                // Typing starts a search — remember where we were and clear the selection.
                if let current = selection {
                    lastSelection = current
                    selection = nil
                }
            } else if selection == nil {
                // Search cleared without a sidebar tap (Esc / clear button) — restore.
                selection = lastSelection
            }
        }
        .onChange(of: selection) { _, newValue in
            // Sidebar tap during a search wins: clear the query so the detail
            // switches from SearchView to the tapped destination.
            if newValue != nil, !searchInput.isEmpty {
                searchInput = ""
            }
        }
        // Load failure alert
        .alert(caskManager.loadAlert.title, isPresented: $caskManager.loadAlert.isPresented) {
            AsyncButton {
                await caskManager.loadData()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }

            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(self)
            }

            Button("OK", role: .cancel) { }
        } message: {
            Text(caskManager.loadAlert.message)
        }
    }
}

#Preview {
    ContentView()
}

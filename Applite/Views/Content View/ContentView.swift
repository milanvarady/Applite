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

    /// Currently selected tab in the sidebar
    @State var selection: SidebarItem = .home

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
            } else if searchInput.isEmpty {
                DetailViews(
                    selection: $selection,
                    modifyingBrew: $modifyingBrew
                )
            } else {
                SearchView(query: $searchInput)
            }
        }
        .task {
            await caskManager.loadData()
        }
        // MARK: - Search
        .searchable(text: $searchInput, placement: .sidebar)
        // Limit search characters
        .onChange(of: searchInput) {
            if searchInput.count > 30 {
                searchInput = String(searchInput.prefix(30))
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

//
//  ContentView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 09. 24..
//

import SwiftUI
import OSLog
import ButtonKit

struct ContentView: View {
    @Environment(CaskManager.self) var caskManager

    /// Currently selected tab in the sidebar
    @State var selection: SidebarItem = .home

    @State var loadAlert = AlertManager()

    @State var brokenInstall = false

    /// If true the sidebar is disabled
    @State var modifyingBrew = false

    /// App search query
    @State var searchInput = ""

    let logger = Logger()

    var body: some View {
        NavigationSplitView {
            sidebarViews
                .disabled(modifyingBrew)
        } detail: {
            if searchInput.isEmpty {
                detailView
            } else {
                SearchView(query: $searchInput)
            }
        }
        // Load all cask releated data
        .task {
            await loadCasks()
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
        .alert(loadAlert.title, isPresented: $loadAlert.isPresented) {
            AsyncButton {
                await loadCasks()
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

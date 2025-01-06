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

    /// App search query
    @State var searchText = ""
    @State var searchInput = ""

    @StateObject var loadAlert = AlertManager()

    @State var brokenInstall = false
    
    /// If true the sidebar is disabled
    @State var modifyingBrew = false
    
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
        // App search
        .searchable(text: $searchInput, placement: .sidebar)
        // Submit search
        .onSubmit(of: .search) {
            if !searchInput.isEmpty && selection != .home {
                selection = .home
            }

            searchText = searchInput
        }
        // Clear search
        .onChange(of: searchInput) { newValue in
            if newValue.isEmpty {
                searchText.removeAll()
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

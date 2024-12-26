//
//  ContentView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 09. 24..
//

import SwiftUI
import os

struct ContentView: View {
    @EnvironmentObject var caskData: CaskData
    
    /// Currently selected tab in the sidebar
    @State var selection: String = "home"
    
    /// App search query
    @State var searchText = ""
    /// This variable is set to the value of searchText whenever the user submits the search quiery
    @State var searchTextSubmitted = ""
    
    @StateObject var loadAlert = AlertManager()

    @State var brokenInstall = false
    
    /// If true the sidebar is disabled
    @State var modifyingBrew = false
    
    let logger = Logger()
    
    var body: some View {
        NavigationSplitView {
            sidebarItems
                .disabled(modifyingBrew)
        } detail: {
            detailView
        }
        // Load casks
        .task {
            await loadCasks()
        }
        // App search
        .searchable(text: $searchText, placement: .sidebar)
        .onSubmit(of: .search) {
            searchTextSubmitted = searchText

            if !searchText.isEmpty && selection != "home" {
                selection = "home"
            }
        }
        .onChange(of: searchText) { newSearchText in
            if newSearchText.isEmpty {
                searchTextSubmitted = ""
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

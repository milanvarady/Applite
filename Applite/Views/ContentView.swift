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
            List(selection: $selection) {
                Divider()

                Label("Discover", systemImage: "house.fill")
                    .tag("home")

                Label("Updates", systemImage: "arrow.clockwise.circle.fill")
                    .badge(caskData.outdatedCasks.count)
                    .tag("updates")

                Label("Installed", systemImage: "externaldrive.fill.badge.checkmark")
                    .tag("installed")

                Label("Active Tasks", systemImage: "gearshape.arrow.triangle.2.circlepath")
                    .badge(caskData.busyCasks.count)
                    .tag("activeTasks")

                Section("Categories") {
                    ForEach(categories) { category in
                        Label(LocalizedStringKey(category.id), systemImage: category.sfSymbol)
                            .tag(category.id)
                    }
                }

                Section("Homebrew") {
                    NavigationLink(value: "brew", label: {
                        Label("Manage Homebrew", systemImage: "mug")
                    })
                }
            }
            .disabled(modifyingBrew)
        } detail: {
            switch selection {
            case "home":
                if !brokenInstall {
                    DownloadView(navigationSelection: $selection, searchText: $searchTextSubmitted)
                } else {
                    // Broken install
                    VStack(alignment: .center) {
                        Text(DependencyManager.brokenPathOrIstallMessage)

                        Button {
                            Task {
                                await loadCasks()
                            }
                        } label: {
                            Label("Retry load", systemImage: "arrow.clockwise.circle")
                        }
                        .bigButton()
                        .disabled(false)
                    }
                    .frame(maxWidth: 600)
                }

            case "updates":
                UpdateView()

            case "installed":
                InstalledView()

            case "activeTasks":
                ActiveTasksView()

            case "brew":
                BrewManagementView(modifyingBrew: $modifyingBrew)

            default:
                if let category = categories.first(where: { $0.id == selection }) {
                    CategoryView(category: category)
                } else {
                    Text("No Selection")
                }
            }
        }
        .task {
            await loadCasks()
        }
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
    
    private func loadCasks() async {
        guard BrewPaths.isSelectedBrewPathValid() else {
            loadAlert.show(title: "Couldn't load app catalog", message: DependencyManager.brokenPathOrIstallMessage)
            brokenInstall = true

            let output = (try? await Shell.runAsync("\(BrewPaths.currentBrewExecutable) --version")) ?? "n/a"

            logger.error(
                """
                Initial cask load failure. Reason: selected brew path seems invalid.
                Brew executable path path: \(BrewPaths.currentBrewExecutable)
                brew --version output: \(output)
                """
            )

            return
        }
        
        do {
            try await caskData.loadData()
            brokenInstall = false
        } catch {
            loadAlert.show(title: "Couldn't load app catalog", message: error.localizedDescription)
            logger.error("Initial cask load failure. Reason: \(error.localizedDescription)")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

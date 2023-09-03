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
    
    @State var loadAlertShowing = false
    @State var errorMessage = ""
    
    @State var pinentryErrorShowing = false
    
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
                let category = categories.first(where: { $0.id == selection })
                
                if category == nil {
                    Text("No Selection")
                } else {
                    CategoryView(category: category!)
                }
            }
        }
        .task {
            await loadCasks()
            await checkPinentry()
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
        .alert("App load error", isPresented: $loadAlertShowing) {
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
            Text(errorMessage)
        }
        .alert("PINEntry not installed correctly", isPresented: $pinentryErrorShowing) {
            Button("I Understand", role: .cancel) { }
        } message: {
            Text("Applications that require an admin password to install will fail to install.")
        }
    }
    
    private func loadCasks() async {
        if !BrewPaths.isSelectedBrewPathValid() {
            errorMessage = DependencyManager.brokenPathOrIstallMessage
            loadAlertShowing = true
            brokenInstall = true
            
            let output = await shell("\(BrewPaths.currentBrewExecutable) --version").output
            
            logger.error("""
Initial cask load failure. Reason: selected brew path seems invalid.
Brew executable path path: \(BrewPaths.currentBrewExecutable)
brew --version output: \(output)
""")
            
            return
        }
        
        do {
            try await caskData.loadData()
            brokenInstall = false
        } catch {
            errorMessage = "Couldn't load app catalog. Check internet your connection, or try restarting the app."
            
            loadAlertShowing = true
            
            logger.error("Initial cask load failure. Reason: \(error.localizedDescription)")
        }
    }
    
    /// Checks if pinentry-mac is correctly installed, if not it installes it
    private func checkPinentry() async {
        // Return if installed
        if await BrewPaths.isPinentryInstalled() { return }
        
        logger.notice("pinentry-mac is not installed. Installing now...")
        
        do {
            try await DependencyManager.installPinentry(forceInstall: true)
        } catch {
            pinentryErrorShowing = true
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

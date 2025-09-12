//
//  PackageManagerView.swift
//  Applite
//
// Created by Subham mahesh 
 licensed under the MIT 
//

import SwiftUI

struct PackageManagerView: View {
    @StateObject private var coordinator = PackageManagerCoordinator()
    @StateObject private var updater: PackageUpdater
    @State private var selectedManager: PackageManagerType?
    @State private var searchText = ""
    @State private var showingSettings = false
    
    init() {
        let coordinator = PackageManagerCoordinator()
        self._coordinator = StateObject(wrappedValue: coordinator)
        self._updater = StateObject(wrappedValue: PackageUpdater(coordinator: coordinator))
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            PackageManagerSidebar(
                coordinator: coordinator,
                selectedManager: $selectedManager
            )
        } detail: {
            // Main content
            PackageManagerDetailView(
                coordinator: coordinator,
                updater: updater,
                selectedManager: selectedManager,
                searchText: $searchText
            )
        }
        .navigationTitle("Package Managers")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape")
                }
                
                Button(action: refreshAll) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(coordinator.isLoading)
                
                if !coordinator.outdatedPackages.isEmpty {
                    Button(action: updateAll) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .disabled(updater.isUpdating)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search packages...")
        .sheet(isPresented: $showingSettings) {
            PackageManagerSettingsView(updater: updater)
        }
        .task {
            await coordinator.refreshAllData()
        }
    }
    
    private func refreshAll() {
        Task {
            await coordinator.refreshAllData()
        }
    }
    
    private func updateAll() {
        Task {
            await updater.updateAllPackages()
        }
    }
}

struct PackageManagerSidebar: View {
    @ObservedObject var coordinator: PackageManagerCoordinator
    @Binding var selectedManager: PackageManagerType?
    
    var body: some View {
        List(selection: $selectedManager) {
            Section("Overview") {
                NavigationLink(value: nil as PackageManagerType?) {
                    Label("All Packages", systemImage: "square.grid.2x2")
                }
                .tag(nil as PackageManagerType?)
                
                if !coordinator.outdatedPackages.isEmpty {
                    NavigationLink(value: PackageManagerType.homebrew) {
                        Label("Updates Available", systemImage: "arrow.down.circle")
                            .badge(coordinator.outdatedPackages.count)
                    }
                }
            }
            
            Section("Package Managers") {
                ForEach(coordinator.availableManagers) { manager in
                    NavigationLink(value: manager) {
                        HStack {
                            Image(systemName: manager.iconName)
                                .foregroundColor(.accentColor)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(manager.displayName)
                                    .font(.headline)
                                
                                let installedCount = coordinator.getPackagesByManager(manager).count
                                let outdatedCount = coordinator.getOutdatedPackagesByManager(manager).count
                                
                                Text("\(installedCount) installed" + (outdatedCount > 0 ? ", \(outdatedCount) outdated" : ""))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                    }
                    .tag(manager)
                }
            }
        }
        .navigationTitle("Packages")
        .refreshable {
            await coordinator.refreshAllData()
        }
    }
}

struct PackageManagerDetailView: View {
    @ObservedObject var coordinator: PackageManagerCoordinator
    @ObservedObject var updater: PackageUpdater
    let selectedManager: PackageManagerType?
    @Binding var searchText: String
    
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            Picker("View", selection: $selectedTab) {
                Text("Installed").tag(0)
                if !filteredOutdatedPackages.isEmpty {
                    Text("Updates").tag(1)
                }
                Text("Search").tag(2)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            // Content
            TabView(selection: $selectedTab) {
                // Installed packages
                PackageListView(
                    packages: filteredInstalledPackages,
                    coordinator: coordinator,
                    emptyMessage: "No installed packages"
                )
                .tag(0)
                
                // Outdated packages
                if !filteredOutdatedPackages.isEmpty {
                    VStack(spacing: 16) {
                        // Update all button
                        HStack {
                            Spacer()
                            
                            Button(action: updateSelectedPackages) {
                                HStack {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text("Update All")
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(updater.isUpdating)
                        }
                        .padding(.horizontal)
                        
                        PackageListView(
                            packages: filteredOutdatedPackages,
                            coordinator: coordinator,
                            emptyMessage: "No packages to update"
                        )
                    }
                    .tag(1)
                }
                
                // Search
                PackageSearchView(
                    coordinator: coordinator,
                    searchText: $searchText,
                    selectedManager: selectedManager
                )
                .tag(2)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        }
        .navigationTitle(selectedManager?.displayName ?? "All Packages")
        .overlay {
            if coordinator.isLoading {
                ProgressView("Loading packages...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
            }
        }
    }
    
    private var filteredInstalledPackages: [GenericPackage] {
        let packages = selectedManager.map { coordinator.getPackagesByManager($0) } ?? coordinator.installedPackages
        
        if searchText.isEmpty {
            return packages
        }
        
        return packages.filter { package in
            package.name.localizedCaseInsensitiveContains(searchText) ||
            package.description?.localizedCaseInsensitiveContains(searchText) == true
        }
    }
    
    private var filteredOutdatedPackages: [GenericPackage] {
        let packages = selectedManager.map { coordinator.getOutdatedPackagesByManager($0) } ?? coordinator.outdatedPackages
        
        if searchText.isEmpty {
            return packages
        }
        
        return packages.filter { package in
            package.name.localizedCaseInsensitiveContains(searchText) ||
            package.description?.localizedCaseInsensitiveContains(searchText) == true
        }
    }
    
    private func updateSelectedPackages() {
        Task {
            if let manager = selectedManager {
                await updater.updatePackagesFor(manager: manager)
            } else {
                await updater.updateAllPackages()
            }
        }
    }
}

#Preview {
    PackageManagerView()
}
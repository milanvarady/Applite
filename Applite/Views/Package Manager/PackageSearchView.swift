//
//  PackageSearchView.swift
//  Applite
//
//  Created by Subham mahesh 
 licensed under the MIT  
//

import SwiftUI

struct PackageSearchView: View {
    @ObservedObject var coordinator: PackageManagerCoordinator
    @Binding var searchText: String
    let selectedManager: PackageManagerType?
    
    @State private var searchResults: [GenericPackage] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    
    var body: some View {
        VStack(spacing: 0) {
            if searchText.isEmpty {
                // Empty search state
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("Search for packages")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Enter a package name or description to find new packages to install")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Search results
                VStack(alignment: .leading, spacing: 0) {
                    // Search status
                    HStack {
                        if isSearching {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Searching...")
                            }
                        } else {
                            Text("Found \(searchResults.count) packages")
                        }
                        
                        Spacer()
                        
                        if !searchResults.isEmpty {
                            // Manager filter
                            Menu {
                                Button("All Managers") {
                                    // Search in all managers
                                    performSearch()
                                }
                                
                                Divider()
                                
                                ForEach(coordinator.availableManagers) { manager in
                                    Button(manager.displayName) {
                                        performSearch(in: [manager])
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Filter")
                                    Image(systemName: "chevron.down")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .menuStyle(BorderlessButtonMenuStyle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    
                    Divider()
                    
                    // Results list
                    if searchResults.isEmpty && !isSearching {
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            
                            Text("No packages found")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text("Try a different search term or check your spelling")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(searchResults) { package in
                            SearchResultRow(package: package, coordinator: coordinator)
                        }
                        .listStyle(PlainListStyle())
                    }
                }
            }
        }
        .onChange(of: searchText) { newValue in
            // Debounce search
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                
                if !Task.isCancelled && !newValue.isEmpty {
                    await performSearch()
                } else if newValue.isEmpty {
                    await MainActor.run {
                        searchResults = []
                    }
                }
            }
        }
    }
    
    @MainActor
    private func performSearch(in managers: [PackageManagerType] = []) {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        Task {
            let managersToSearch = managers.isEmpty ? (selectedManager.map { [$0] } ?? []) : managers
            let results = await coordinator.searchPackages(searchText, in: managersToSearch)
            
            await MainActor.run {
                searchResults = results
                isSearching = false
            }
        }
    }
}

struct SearchResultRow: View {
    let package: GenericPackage
    @ObservedObject var coordinator: PackageManagerCoordinator
    
    @State private var showingDetail = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Package manager icon
            Image(systemName: package.manager.iconName)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            
            // Package info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(package.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if package.isInstalled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
                
                HStack(spacing: 8) {
                    Text(package.manager.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let version = package.version {
                        Text("v\(version)")
                            .font(.caption)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                
                if let description = package.description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Spacer()
            
            // Actions
            VStack(spacing: 4) {
                PackageActionView(package: package, coordinator: coordinator)
                
                Button(action: { showingDetail = true }) {
                    Text("Info")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingDetail) {
            PackageDetailView(package: package, coordinator: coordinator)
        }
    }
}

#Preview {
    let coordinator = PackageManagerCoordinator()
    
    return PackageSearchView(
        coordinator: coordinator,
        searchText: .constant("git"),
        selectedManager: nil
    )
}
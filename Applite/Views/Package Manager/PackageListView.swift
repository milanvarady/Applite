//
//  PackageListView.swift
//  Applite
//
// Created by Subham mahesh
// licensed under the MIT
//

import SwiftUI

struct PackageListView: View {
    let packages: [GenericPackage]
    @ObservedObject var coordinator: PackageManagerCoordinator
    let emptyMessage: String
    
    @State private var selectedPackage: GenericPackage?
    @State private var sortOption: SortOption = .name
    @State private var sortOrder: SortOrder = .ascending
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sort controls
            HStack {
                Text("\(sortedPackages.count) packages")
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Menu {
                    Picker("Sort by", selection: $sortOption) {
                        ForEach(SortOption.allCases) { option in
                            Label(option.displayName, systemImage: option.iconName)
                                .tag(option)
                        }
                    }
                    
                    Divider()
                    
                    Picker("Order", selection: $sortOrder) {
                        Label("Ascending", systemImage: "arrow.up").tag(SortOrder.ascending)
                        Label("Descending", systemImage: "arrow.down").tag(SortOrder.descending)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: sortOption.iconName)
                        Image(systemName: sortOrder == .ascending ? "arrow.up" : "arrow.down")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .menuStyle(BorderlessButtonMenuStyle())
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            // Package list
            if sortedPackages.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "cube.box")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text(emptyMessage)
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(sortedPackages, selection: $selectedPackage) { package in
                    PackageRowView(
                        package: package,
                        coordinator: coordinator
                    )
                    .tag(package)
                }
                .listStyle(PlainListStyle())
            }
        }
        .sheet(item: $selectedPackage) { package in
            PackageDetailView(package: package, coordinator: coordinator)
        }
    }
    
    private var sortedPackages: [GenericPackage] {
        packages.sorted { lhs, rhs in
            let ascending = sortOrder == .ascending
            
            switch sortOption {
            case .name:
                return ascending ? lhs.name < rhs.name : lhs.name > rhs.name
            case .manager:
                let lhsManager = lhs.manager.displayName
                let rhsManager = rhs.manager.displayName
                return ascending ? lhsManager < rhsManager : lhsManager > rhsManager
            case .version:
                let lhsVersion = lhs.version ?? ""
                let rhsVersion = rhs.version ?? ""
                return ascending ? lhsVersion < rhsVersion : lhsVersion > rhsVersion
            case .installSize:
                let lhsSize = lhs.installSize ?? ""
                let rhsSize = rhs.installSize ?? ""
                return ascending ? lhsSize < rhsSize : lhsSize > rhsSize
            }
        }
    }
}

struct PackageRowView: View {
    let package: GenericPackage
    @ObservedObject var coordinator: PackageManagerCoordinator
    
    @State private var showingActions = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Package manager icon
            Image(systemName: package.manager.iconName)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            
            // Package info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(package.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if package.isOutdated {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
                
                HStack(spacing: 8) {
                    if let version = package.version {
                        Text("v\(version)")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    
                    Text(package.manager.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                
                if let description = package.description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            // Operation state or actions
            PackageActionView(package: package, coordinator: coordinator)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct PackageActionView: View {
    let package: GenericPackage
    @ObservedObject var coordinator: PackageManagerCoordinator
    
    var body: some View {
        let operationState = coordinator.getOperationState(for: package.id)
        
        HStack(spacing: 8) {
            if operationState.isActive {
                // Show progress
                HStack(spacing: 4) {
                    SmallProgressView()
                    Text(operationState.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                // Show action buttons
                if package.isInstalled {
                    if package.isOutdated {
                        Button(action: updatePackage) {
                            Image(systemName: "arrow.up.circle")
                                .foregroundColor(.orange)
                        }
                        .help("Update package")
                    }
                    
                    Button(action: uninstallPackage) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .help("Uninstall package")
                } else {
                    Button(action: installPackage) {
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(.blue)
                    }
                    .help("Install package")
                }
            }
        }
    }
    
    private func installPackage() {
        Task {
            await coordinator.installPackage(package)
        }
    }
    
    private func uninstallPackage() {
        Task {
            await coordinator.uninstallPackage(package)
        }
    }
    
    private func updatePackage() {
        Task {
            await coordinator.updatePackage(package)
        }
    }
}

// MARK: - Supporting Types

enum SortOption: String, CaseIterable, Identifiable {
    case name = "name"
    case manager = "manager"
    case version = "version"
    case installSize = "installSize"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .name: return "Name"
        case .manager: return "Manager"
        case .version: return "Version"
        case .installSize: return "Size"
        }
    }
    
    var iconName: String {
        switch self {
        case .name: return "textformat"
        case .manager: return "cube.box"
        case .version: return "number"
        case .installSize: return "externaldrive"
        }
    }
}

enum SortOrder {
    case ascending
    case descending
}

#Preview {
    let coordinator = PackageManagerCoordinator()
    let samplePackages = [
        GenericPackage(
            id: "git",
            name: "Git",
            version: "2.42.0",
            description: "Distributed version control system",
            manager: .homebrew,
            isInstalled: true
        ),
        GenericPackage(
            id: "node",
            name: "Node.js",
            version: "18.17.0",
            description: "JavaScript runtime",
            manager: .homebrew,
            isInstalled: true,
            isOutdated: true,
            latestVersion: "20.5.0"
        )
    ]
    
    return PackageListView(
        packages: samplePackages,
        coordinator: coordinator,
        emptyMessage: "No packages found"
    )
    .frame(height: 400)
}
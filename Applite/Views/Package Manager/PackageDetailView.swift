//
//  PackageDetailView.swift
//  Applite
//
//  Created by Subham mahesh
//  licensed under the MIT
//

import SwiftUI

struct PackageDetailView: View {
    let package: GenericPackage
    @ObservedObject var coordinator: PackageManagerCoordinator
    
    @Environment(\.dismiss) private var dismiss
    @State private var detailedPackage: GenericPackage?
    @State private var isLoadingDetails = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    PackageHeaderView(package: displayPackage)
                    
                    // Actions
                    PackageActionsView(package: displayPackage, coordinator: coordinator)
                    
                    // Information sections
                    VStack(alignment: .leading, spacing: 16) {
                        if let description = displayPackage.description {
                            PackageInfoSection(title: "Description", content: description)
                        }
                        
                        PackageDetailsSection(package: displayPackage)
                        
                        if !displayPackage.dependencies.isEmpty {
                            PackageDependenciesSection(dependencies: displayPackage.dependencies)
                        }
                        
                        PackageLinksSection(package: displayPackage)
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle(package.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 600, height: 700)
        .task {
            await loadDetailedPackageInfo()
        }
    }
    
    private var displayPackage: GenericPackage {
        detailedPackage ?? package
    }
    
    private func loadDetailedPackageInfo() {
        guard !isLoadingDetails else { return }
        
        isLoadingDetails = true
        
        Task {
            if let detailed = await coordinator.getPackageInfo(package.id, manager: package.manager) {
                await MainActor.run {
                    detailedPackage = detailed
                }
            }
            
            await MainActor.run {
                isLoadingDetails = false
            }
        }
    }
}

struct PackageHeaderView: View {
    let package: GenericPackage
    
    var body: some View {
        HStack(spacing: 16) {
            // Package manager icon
            Image(systemName: package.manager.iconName)
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
                .frame(width: 64, height: 64)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(package.name)
                    .font(.title)
                    .fontWeight(.bold)
                
                HStack(spacing: 12) {
                    // Version badge
                    if let version = package.version {
                        Text("v\(version)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    
                    // Status badge
                    StatusBadge(package: package)
                    
                    // Manager badge
                    Text(package.manager.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.2))
                        .foregroundColor(.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            
            Spacer()
        }
    }
}

struct StatusBadge: View {
    let package: GenericPackage
    
    var body: some View {
        if package.isInstalled {
            if package.isOutdated {
                Text("Update Available")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2))
                    .foregroundColor(.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text("Installed")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        } else {
            Text("Not Installed")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.2))
                .foregroundColor(.gray)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

struct PackageActionsView: View {
    let package: GenericPackage
    @ObservedObject var coordinator: PackageManagerCoordinator
    
    var body: some View {
        let operationState = coordinator.getOperationState(for: package.id)
        
        HStack(spacing: 12) {
            if operationState.isActive {
                // Progress view
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    
                    Text(operationState.localizedDescription)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                // Action buttons
                if package.isInstalled {
                    if package.isOutdated {
                        Button(action: updatePackage) {
                            HStack {
                                Image(systemName: "arrow.up.circle.fill")
                                Text("Update to \(package.latestVersion ?? "latest")")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    
                    Button(action: uninstallPackage) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Uninstall")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .foregroundColor(.red)
                } else {
                    Button(action: installPackage) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Install")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
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

struct PackageInfoSection: View {
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(content)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PackageDetailsSection: View {
    let package: GenericPackage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                DetailRow(label: "Package ID", value: package.id)
                DetailRow(label: "Manager", value: package.manager.displayName)
                
                if let version = package.version {
                    DetailRow(label: "Version", value: version)
                }
                
                if let latestVersion = package.latestVersion, package.isOutdated {
                    DetailRow(label: "Latest Version", value: latestVersion)
                }
                
                if let installSize = package.installSize {
                    DetailRow(label: "Install Size", value: installSize)
                }
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .fontWeight(.medium)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct PackageDependenciesSection: View {
    let dependencies: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dependencies (\(dependencies.count))")
                .font(.headline)
                .foregroundColor(.primary)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                ForEach(dependencies, id: \.self) { dependency in
                    Text(dependency)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }
}

struct PackageLinksSection: View {
    let package: GenericPackage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Links")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                if let homepage = package.homepage, let url = URL(string: homepage) {
                    LinkRow(title: "Homepage", url: url, icon: "house")
                }
                
                // Add more links as available
            }
        }
    }
}

struct LinkRow: View {
    let title: String
    let url: URL
    let icon: String
    
    var body: some View {
        Button(action: { NSWorkspace.shared.open(url) }) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                
                Text(title)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let coordinator = PackageManagerCoordinator()
    let samplePackage = GenericPackage(
        id: "git",
        name: "Git",
        version: "2.42.0",
        description: "Git is a free and open source distributed version control system designed to handle everything from small to very large projects with speed and efficiency.",
        manager: .homebrew,
        isInstalled: true,
        isOutdated: true,
        latestVersion: "2.42.1",
        homepage: "https://git-scm.com",
        installSize: "45.2 MB",
        dependencies: ["gettext", "pcre2"]
    )
    
    return PackageDetailView(package: samplePackage, coordinator: coordinator)
}
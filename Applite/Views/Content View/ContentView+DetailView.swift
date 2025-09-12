//
//  ContentView+DetailView.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
 //MODIFIED by Subham mahesh EVERY MODIFICATION MADE BY SUBHAM MAHESH LICENSE UNDER THE MIT

//

import SwiftUI
import ButtonKit
import Foundation

extension ContentView {
    @ViewBuilder
    var detailView: some View {
        switch selection {
        case .home:
            HomeView(
                navigationSelection: $selection,
                searchText: $searchInput,
                showSearchResults: $showSearchResults,
                caskCollection: caskManager.allCasks
            )
            
        case .installed:
            InstalledView(caskCollection: caskManager.installedCasks)
            
        case .updates:
            UpdateView(caskCollection: caskManager.outdatedCasks)
            
        case .activeTasks:
            ActiveTasksView()
            
        case .brew:
            BrewManagementView(modifyingBrew: $modifyingBrew)
            
        case .appMigration:
            AppMigrationView()
            
        case .packageManager:
            PackageManagerView()
            
        case .appCategory(let category):
            CategoryView(category: category)
            
        case .tap(let tap):
            TapView(tap: tap)
        }
    }
}

// MARK: - Package Manager Implementation

struct PackageManagerView: View {
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchResults: [PackageInfo] = []
    @State private var installedPackages: [PackageInfo] = []
    @State private var isLoading = false
    @State private var selectedTab = 0
    @State private var selectedPackage: PackageInfo?
    @State private var operationStates: [String: PackageOperationStatus] = [:]
    @State private var searchTask: Task<Void, Never>?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Tab Buttons
            VStack(spacing: 16) {
                HStack {
                    Text(String(localized: "Package Manager", comment: "Package manager title"))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Spacer()
                }
                
                // Custom Tab Buttons
                HStack(spacing: 12) {
                    // Installed Tab Button
                    Button(action: { selectedTab = 0 }) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                            Text(String(localized: "Installed", comment: "Installed tab"))
                                .font(.headline)
                                .fontWeight(.medium)
                            
                            if !installedPackages.isEmpty {
                                Text("\(installedPackages.count)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(selectedTab == 0 ? Color.green.opacity(0.2) : Color.secondary.opacity(0.1))
                        .foregroundColor(selectedTab == 0 ? .green : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedTab == 0 ? Color.green : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Search Tab Button
                    Button(action: { selectedTab = 1 }) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16))
                            Text(String(localized: "Search", comment: "Search tab"))
                                .font(.headline)
                                .fontWeight(.medium)
                                
                            if !searchResults.isEmpty && !searchText.isEmpty {
                                Text("\(searchResults.count)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(selectedTab == 1 ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1))
                        .foregroundColor(selectedTab == 1 ? .blue : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedTab == 1 ? Color.blue : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                    
                    // Loading indicator
                    if isLoading || isSearching {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(isLoading ? String(localized: "Loading...", comment: "Loading indicator") : String(localized: "Searching...", comment: "Search in progress"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
            
            Divider()
            
            // Content based on selected tab
            if selectedTab == 0 {
                // Installed Packages Content
                if installedPackages.isEmpty && !isLoading {
                    VStack(spacing: 16) {
                        Image(systemName: "cube.box")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text(String(localized: "No packages installed", comment: "No packages message"))
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text(String(localized: "Install packages using the Search tab", comment: "Install packages instruction"))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        Button(action: { selectedTab = 1 }) {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                Text(String(localized: "Search Packages", comment: "Search packages button"))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    PackageListView(
                        packages: installedPackages,
                        isLoading: isLoading,
                        selectedPackage: $selectedPackage,
                        operationStates: $operationStates
                    )
                }
            } else {
                // Search Content
                VStack(spacing: 16) {
                    // Search Bar
                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            
                            TextField(String(localized: "Search packages...", comment: "Search placeholder"), text: $searchText)
                                .textFieldStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                                searchResults = []
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                    
                    // Search Results
                    if searchText.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            
                            Text(String(localized: "Search for packages", comment: "Search empty state title"))
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text(String(localized: "Enter a package name to search the Homebrew catalog", comment: "Search empty state description"))
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if searchResults.isEmpty && !isSearching {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.magnifyingglass")
                                .font(.system(size: 32))
                                .foregroundColor(.orange)
                            
                            Text(String(localized: "No packages found", comment: "No search results"))
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text(String(localized: "Try a different search term", comment: "Search suggestion"))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        PackageListView(
                            packages: searchResults,
                            isLoading: isSearching,
                            selectedPackage: $selectedPackage,
                            operationStates: $operationStates
                        )
                    }
                }
            }
        }
        .task {
            await loadInstalledPackages()
        }
        .onChange(of: searchText) { newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                
                if !Task.isCancelled && !newValue.isEmpty {
                    await performSearch(query: newValue)
                } else if newValue.isEmpty {
                    searchResults = []
                }
            }
        }
        .sheet(item: $selectedPackage) { package in
            PackageDetailView(
                package: package,
                operationStates: $operationStates
            )
        }
    }
    
    private func loadInstalledPackages() async {
        isLoading = true
        
        do {
            let output = try await Shell.runBrewCommand(["list", "--formula", "--versions"])
            let packages = output.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .compactMap { line -> PackageInfo? in
                    let components = line.components(separatedBy: " ")
                    guard let name = components.first else { return nil }
                    let version = components.count > 1 ? components[1] : nil
                    return PackageInfo(name: name, version: version, isInstalled: true)
                }
                .sorted { $0.name < $1.name }
            
            installedPackages = packages
        } catch {
            installedPackages = []
        }
        
        isLoading = false
    }
    
    private func performSearch(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        do {
            let output = try await Shell.runBrewCommand(["search", query])
            let installedSet = Set(installedPackages.map { $0.name })
            let packages = output.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("==>") }
                .prefix(50)
                .map { packageName in
                    PackageInfo(name: packageName, isInstalled: installedSet.contains(packageName))
                }
            
            searchResults = Array(packages)
        } catch {
            searchResults = []
        }
        
        isSearching = false
    }
}

// MARK: - Supporting Views

struct PackageListView: View {
    let packages: [PackageInfo]
    let isLoading: Bool
    @Binding var selectedPackage: PackageInfo?
    @Binding var operationStates: [String: PackageOperationStatus]
    
    var body: some View {
        if isLoading {
            VStack {
                ProgressView()
                Text(String(localized: "Loading packages...", comment: "Loading packages"))
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(packages, id: \.name) { package in
                        PackageRowView(
                            package: package,
                            selectedPackage: $selectedPackage,
                            operationStates: $operationStates
                        )
                        
                        if package != packages.last {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

struct PackageRowView: View {
    @State private var package: PackageInfo
    @Binding var selectedPackage: PackageInfo?
    @Binding var operationStates: [String: PackageOperationStatus]
    
    init(package: PackageInfo, selectedPackage: Binding<PackageInfo?>, operationStates: Binding<[String: PackageOperationStatus]>) {
        self._package = State(initialValue: package)
        self._selectedPackage = selectedPackage
        self._operationStates = operationStates
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Status Icon - Larger
            Image(systemName: package.isInstalled ? "checkmark.circle.fill" : "circle")
                .foregroundColor(package.isInstalled ? .green : .secondary)
                .font(.system(size: 24))
            
            // Package Information - More detailed
            VStack(alignment: .leading, spacing: 6) {
                // Package Name
                Text(package.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                // Version and Status Row
                HStack(spacing: 12) {
                    if let version = package.version {
                        HStack(spacing: 4) {
                            Image(systemName: "number")
                                .foregroundColor(.blue)
                                .font(.caption2)
                            Text("v\(version)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    
                    // Installation status badge
                    HStack(spacing: 4) {
                        Image(systemName: package.isInstalled ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundColor(package.isInstalled ? .green : .orange)
                            .font(.caption2)
                        Text(package.isInstalled ? String(localized: "Installed", comment: "Installed badge") : String(localized: "Available", comment: "Available badge"))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(package.isInstalled ? .green : .orange)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((package.isInstalled ? Color.green : Color.orange).opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    
                    Spacer()
                }
                
                // Package Description
                if let description = package.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(String(localized: "No description available", comment: "No description placeholder"))
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.7))
                        .italic()
                }
                
                // Dependencies info (if available)
                if !package.dependencies.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .foregroundColor(.purple)
                            .font(.caption2)
                        Text("\(package.dependencies.count) dependencies")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                    .padding(.top, 2)
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                if let operationState = operationStates[package.name], operationState.isActive {
                    HStack(spacing: 6) {
                        // Progress indicator based on operation type
                        switch operationState {
                        case .installing(let progress), .uninstalling(let progress):
                            PackageCircularProgressView(progress: progress)
                        case .installed:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 14))
                        case .uninstalled:
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 14))
                        case .failed:
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 14))
                        default:
                            ProgressView()
                                .scaleEffect(0.5)
                        }
                        
                        Text(operationState.displayText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 80, alignment: .leading)
                } else {
                    Button(action: { selectedPackage = package }) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.borderless)
                    .help("Package information")
                    
                    if package.isInstalled {
                        Button(action: { uninstallPackage() }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("Uninstall package")
                    } else {
                        Button(action: { installPackage() }) {
                            Image(systemName: "arrow.down.circle")
                                .foregroundColor(.green)
                        }
                        .buttonStyle(.borderless)
                        .help("Install package")
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 80)
        .background(Color.primary.opacity(0.02))
        .contentShape(Rectangle())
    }
    
    private func installPackage() {
        operationStates[package.name] = .installing(progress: 0.0)
        
        Task {
            do {
                // Simulate progress updates during installation
                await updateProgress(for: package.name, isInstalling: true)
                
                _ = try await Shell.runBrewCommand(["install", package.name])
                
                _ = await MainActor.run {
                    operationStates[package.name] = .installed
                    // Update package state immediately
                    package.isInstalled = true
                }
                
                // Show success state briefly, then clear
                try await Task.sleep(nanoseconds: 2_000_000_000)
                _ = await MainActor.run {
                    operationStates.removeValue(forKey: package.name)
                }
            } catch {
                _ = await MainActor.run {
                    operationStates[package.name] = .failed(error: "Install failed")
                }
                
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                _ = await MainActor.run {
                    operationStates.removeValue(forKey: package.name)
                }
            }
        }
    }
    
    private func uninstallPackage() {
        operationStates[package.name] = .uninstalling(progress: 0.0)
        
        Task {
            do {
                // Simulate progress updates during uninstallation
                await updateProgress(for: package.name, isInstalling: false)
                
                _ = try await Shell.runBrewCommand(["uninstall", package.name])
                
                _ = await MainActor.run {
                    operationStates[package.name] = .uninstalled
                    // Update package state immediately
                    package.isInstalled = false
                }
                
                // Show success state briefly, then clear
                try await Task.sleep(nanoseconds: 2_000_000_000)
                _ = await MainActor.run {
                    operationStates.removeValue(forKey: package.name)
                }
            } catch {
                _ = await MainActor.run {
                    operationStates[package.name] = .failed(error: "Uninstall failed")
                }
                
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                _ = await MainActor.run {
                    operationStates.removeValue(forKey: package.name)
                }
            }
        }
    }
    
    private func updateProgress(for packageName: String, isInstalling: Bool) async {
        let steps = 10
        for i in 1...steps {
            let progress = Double(i) / Double(steps)
            _ = await MainActor.run {
                if isInstalling {
                    operationStates[packageName] = .installing(progress: progress)
                } else {
                    operationStates[packageName] = .uninstalling(progress: progress)
                }
            }
            // Faster progress updates for more responsive feel
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms between updates
        }
    }
}

struct PackageDetailView: View {
    let package: PackageInfo
    @Binding var operationStates: [String: PackageOperationStatus]
    @Environment(\.dismiss) private var dismiss
    @State private var detailedInfo: PackageInfo?
    @State private var isLoadingDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: package.isInstalled ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(package.isInstalled ? .green : .secondary)
                    .font(.title)
                
                VStack(alignment: .leading) {
                    Text(package.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if let version = package.version {
                        Text("Version: \(version)")
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button(String(localized: "Close", comment: "Close button")) {
                    dismiss()
                }
            }
            .padding()
            
            if isLoadingDetails {
                VStack {
                    ProgressView()
                    Text(String(localized: "Loading details...", comment: "Loading details"))
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let info = detailedInfo {
                            if let description = info.description, !description.isEmpty {
                                DetailRow(label: "Description", value: description)
                            }
                            
                            if let homepage = info.homepage, !homepage.isEmpty {
                                DetailRow(label: "Homepage", value: homepage)
                            }
                            
                            if !info.dependencies.isEmpty {
                                DetailRow(
                                    label: "Dependencies",
                                    value: info.dependencies.joined(separator: ", ")
                                )
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 600, height: 400)
        .task {
            await loadDetailedInfo()
        }
    }
    
    private func loadDetailedInfo() async {
        isLoadingDetails = true
        
        do {
            let output = try await Shell.runBrewCommand(["info", "--json", package.name])
            
            // Parse JSON response (simplified)
            if let data = output.data(using: .utf8),
               let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let packageInfo = json.first {
                
                let description = packageInfo["desc"] as? String
                let homepage = packageInfo["homepage"] as? String
                let dependencies = packageInfo["dependencies"] as? [String] ?? []
                
                let detailed = PackageInfo(
                    name: package.name,
                    description: description,
                    version: package.version,
                    isInstalled: package.isInstalled,
                    homepage: homepage,
                    dependencies: dependencies
                )
                
                detailedInfo = detailed
            }
        } catch {
            // Handle error silently for now
        }
        
        isLoadingDetails = false
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

// MARK: - Progress Views

struct PackageCircularProgressView: View {
    let progress: Double
    
    private var displayText: String {
        let percentage = Int(progress * 100)
        if percentage >= 100 {
            return "✓"  // Checkmark for 100%
        } else {
            return "\(percentage)%"
        }
    }
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1.5)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.2), value: progress)
            
            Text(displayText)
                .font(.system(size: progress >= 1.0 ? 8 : 5, weight: .bold))
                .foregroundColor(progress >= 1.0 ? .green : .primary)
        }
        .frame(width: 18, height: 18)
    }
}

// MARK: - Supporting Types

struct PackageInfo: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let description: String?
    let version: String?
    var isInstalled: Bool
    let homepage: String?
    let dependencies: [String]
    
    init(name: String, description: String? = nil, version: String? = nil, isInstalled: Bool = false, homepage: String? = nil, dependencies: [String] = []) {
        self.name = name
        self.description = description
        self.version = version
        self.isInstalled = isInstalled
        self.homepage = homepage
        self.dependencies = dependencies
    }
}

enum PackageOperationStatus {
    case idle
    case installing(progress: Double)
    case uninstalling(progress: Double)
    case installed
    case uninstalled
    case failed(error: String)
    
    var displayText: String {
        switch self {
        case .idle:
            return ""
        case .installing(let progress):
            return String(localized: "Installing", comment: "Installing status") + " \(Int(progress * 100))%"
        case .uninstalling(let progress):
            return String(localized: "Uninstalling", comment: "Uninstalling status") + " \(Int(progress * 100))%"
        case .installed:
            return String(localized: "Installed", comment: "Installed status")
        case .uninstalled:
            return String(localized: "Uninstalled", comment: "Uninstalled status")
        case .failed(let error):
            return error.contains("install") ? String(localized: "Install Failed", comment: "Install failed status") : String(localized: "Uninstall Failed", comment: "Uninstall failed status")
        }
    }
    
    var isActive: Bool {
        switch self {
        case .idle:
            return false
        case .installing, .uninstalling:
            return true
        case .installed, .uninstalled, .failed:
            return true
        }
    }
}

//
//  PackageManagerIntegrated.swift
//  Applite
//
//  Created by Subham mahesh
//  licensed under the MIT
//

import Foundation
import SwiftUI
import OSLog
import UserNotifications

// MARK: - Package Manager Types

enum PackageManagerType: String, CaseIterable, Identifiable, Codable {
    case homebrew = "homebrew"
    case macports = "macports"
    case npm = "npm"
    case pip = "pip"
    case gem = "gem"
    case cargo = "cargo"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .homebrew: return "Homebrew"
        case .macports: return "MacPorts"
        case .npm: return "npm"
        case .pip: return "pip"
        case .gem: return "RubyGems"
        case .cargo: return "Cargo"
        }
    }
    
    var iconName: String {
        switch self {
        case .homebrew: return "mug"
        case .macports: return "port"
        case .npm: return "cube.box"
        case .pip: return "snake"
        case .gem: return "diamond"
        case .cargo: return "shippingbox"
        }
    }
}

// MARK: - Generic Package Model

struct GenericPackage: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let version: String?
    let description: String?
    let manager: PackageManagerType
    let isInstalled: Bool
    let isOutdated: Bool
    let latestVersion: String?
    let homepage: String?
    let installSize: String?
    let dependencies: [String]
    
    init(
        id: String,
        name: String,
        version: String? = nil,
        description: String? = nil,
        manager: PackageManagerType,
        isInstalled: Bool = false,
        isOutdated: Bool = false,
        latestVersion: String? = nil,
        homepage: String? = nil,
        installSize: String? = nil,
        dependencies: [String] = []
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.manager = manager
        self.isInstalled = isInstalled
        self.isOutdated = isOutdated
        self.latestVersion = latestVersion
        self.homepage = homepage
        self.installSize = installSize
        self.dependencies = dependencies
    }
}

// MARK: - Package Operation State

enum PackageOperationState: Equatable {
    case idle
    case installing
    case uninstalling
    case updating
    case downloading(progress: Double)
    case success
    case failed(error: String)
    
    var isActive: Bool {
        switch self {
        case .idle, .success, .failed:
            return false
        default:
            return true
        }
    }
    
    var localizedDescription: String {
        switch self {
        case .idle:
            return ""
        case .installing:
            return String(localized: "Installing", comment: "Package installing state")
        case .uninstalling:
            return String(localized: "Uninstalling", comment: "Package uninstalling state")
        case .updating:
            return String(localized: "Updating", comment: "Package updating state")
        case .downloading(let progress):
            return String(localized: "Downloading \(Int(progress * 100))%", comment: "Package downloading state")
        case .success:
            return String(localized: "Success", comment: "Package operation success state")
        case .failed(let error):
            return String(localized: "Failed: \(error)", comment: "Package operation failed state")
        }
    }
}

// MARK: - Package Manager Errors

enum PackageManagerError: LocalizedError {
    case managerNotAvailable(String)
    case packageNotFound(String)
    case installationFailed(String, String)
    case uninstallationFailed(String, String)
    case updateFailed(String, String)
    case commandExecutionFailed(String)
    case parseError(String)
    
    var errorDescription: String? {
        switch self {
        case .managerNotAvailable(let manager):
            return "Package manager '\(manager)' is not available"
        case .packageNotFound(let package):
            return "Package '\(package)' not found"
        case .installationFailed(let package, let error):
            return "Failed to install '\(package)': \(error)"
        case .uninstallationFailed(let package, let error):
            return "Failed to uninstall '\(package)': \(error)"
        case .updateFailed(let package, let error):
            return "Failed to update '\(package)': \(error)"
        case .commandExecutionFailed(let command):
            return "Failed to execute command: \(command)"
        case .parseError(let details):
            return "Failed to parse output: \(details)"
        }
    }
}

// MARK: - Brew Package Manager

@MainActor
class BrewPackageManager: ObservableObject {
    let name = "Homebrew"
    
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: BrewPackageManager.self)
    )
    
    var isAvailable: Bool {
        get async {
            do {
                _ = try await Shell.runBrewCommand(["--version"])
                return true
            } catch {
                return false
            }
        }
    }
    
    func install(_ package: GenericPackage) async throws {
        Self.logger.info("Installing package: \(package.id)")
        let arguments = ["install", package.id]
        
        do {
            _ = try await Shell.runBrewCommand(arguments)
            Self.logger.info("Successfully installed package: \(package.id)")
        } catch {
            Self.logger.error("Failed to install package \(package.id): \(error.localizedDescription)")
            throw PackageManagerError.installationFailed(package.id, error.localizedDescription)
        }
    }
    
    func uninstall(_ package: GenericPackage) async throws {
        Self.logger.info("Uninstalling package: \(package.id)")
        let arguments = ["uninstall", package.id]
        
        do {
            _ = try await Shell.runBrewCommand(arguments)
            Self.logger.info("Successfully uninstalled package: \(package.id)")
        } catch {
            Self.logger.error("Failed to uninstall package \(package.id): \(error.localizedDescription)")
            throw PackageManagerError.uninstallationFailed(package.id, error.localizedDescription)
        }
    }
    
    func update(_ package: GenericPackage) async throws {
        Self.logger.info("Updating package: \(package.id)")
        let arguments = ["upgrade", package.id]
        
        do {
            _ = try await Shell.runBrewCommand(arguments)
            Self.logger.info("Successfully updated package: \(package.id)")
        } catch {
            Self.logger.error("Failed to update package \(package.id): \(error.localizedDescription)")
            throw PackageManagerError.updateFailed(package.id, error.localizedDescription)
        }
    }
    
    func getInstalledPackages() async throws -> [GenericPackage] {
        do {
            let output = try await Shell.runBrewCommand(["list", "--formula", "--versions"])
            return parseInstalledPackages(output)
        } catch {
            throw PackageManagerError.commandExecutionFailed(error.localizedDescription)
        }
    }
    
    func getOutdatedPackages() async throws -> [GenericPackage] {
        do {
            let output = try await Shell.runBrewCommand(["outdated", "--formula"])
            return parseOutdatedPackages(output)
        } catch {
            throw PackageManagerError.commandExecutionFailed(error.localizedDescription)
        }
    }
    
    func searchPackages(_ query: String) async throws -> [GenericPackage] {
        guard !query.isEmpty else { return [] }
        
        do {
            let output = try await Shell.runBrewCommand(["search", query])
            return parseSearchResults(output)
        } catch {
            throw PackageManagerError.commandExecutionFailed(error.localizedDescription)
        }
    }
    
    private func parseInstalledPackages(_ output: String) -> [GenericPackage] {
        let lines = output.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        return lines.compactMap { line in
            let components = line.components(separatedBy: " ")
            guard let packageName = components.first else { return nil }
            let version = components.count > 1 ? components[1] : nil
            
            return GenericPackage(
                id: packageName,
                name: packageName,
                version: version,
                manager: .homebrew,
                isInstalled: true
            )
        }
    }
    
    private func parseOutdatedPackages(_ output: String) -> [GenericPackage] {
        let lines = output.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        return lines.compactMap { line in
            let components = line.components(separatedBy: " ")
            guard let packageName = components.first else { return nil }
            
            return GenericPackage(
                id: packageName,
                name: packageName,
                manager: .homebrew,
                isInstalled: true,
                isOutdated: true
            )
        }
    }
    
    private func parseSearchResults(_ output: String) -> [GenericPackage] {
        let lines = output.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .filter { !$0.hasPrefix("==>") }
        
        return lines.compactMap { line in
            let packageName = line.trimmingCharacters(in: .whitespaces)
            guard !packageName.isEmpty else { return nil }
            
            return GenericPackage(
                id: packageName,
                name: packageName,
                manager: .homebrew,
                isInstalled: false
            )
        }
    }
}

// MARK: - Package Manager Coordinator

@MainActor
final class SimplePackageManagerCoordinator: ObservableObject {
    
    @Published var installedPackages: [GenericPackage] = []
    @Published var outdatedPackages: [GenericPackage] = []
    @Published var isLoading = false
    @Published var operationStates: [String: PackageOperationState] = [:]
    
    private let brewManager = BrewPackageManager()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: SimplePackageManagerCoordinator.self)
    )
    
    init() {
        Task {
            await loadInstalledPackages()
        }
    }
    
    func loadInstalledPackages() async {
        guard !isLoading else { return }
        
        isLoading = true
        logger.info("Loading installed packages")
        
        do {
            let packages = try await brewManager.getInstalledPackages()
            installedPackages = packages
            logger.info("Loaded \(packages.count) packages")
        } catch {
            logger.error("Failed to load packages: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    func loadOutdatedPackages() async {
        logger.info("Loading outdated packages")
        
        do {
            let packages = try await brewManager.getOutdatedPackages()
            outdatedPackages = packages
            logger.info("Found \(packages.count) outdated packages")
        } catch {
            logger.error("Failed to get outdated packages: \(error.localizedDescription)")
        }
    }
    
    func searchPackages(_ query: String) async -> [GenericPackage] {
        guard !query.isEmpty else { return [] }
        
        do {
            return try await brewManager.searchPackages(query)
        } catch {
            logger.error("Failed to search packages: \(error.localizedDescription)")
            return []
        }
    }
    
    func installPackage(_ package: GenericPackage) async {
        setOperationState(.installing, for: package.id)
        
        do {
            try await brewManager.install(package)
            setOperationState(.success, for: package.id)
            await loadInstalledPackages()
            logger.info("Successfully installed package: \(package.id)")
        } catch {
            logger.error("Failed to install package \(package.id): \(error.localizedDescription)")
            setOperationState(.failed(error: error.localizedDescription), for: package.id)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.setOperationState(.idle, for: package.id)
        }
    }
    
    func uninstallPackage(_ package: GenericPackage) async {
        setOperationState(.uninstalling, for: package.id)
        
        do {
            try await brewManager.uninstall(package)
            setOperationState(.success, for: package.id)
            await loadInstalledPackages()
            logger.info("Successfully uninstalled package: \(package.id)")
        } catch {
            logger.error("Failed to uninstall package \(package.id): \(error.localizedDescription)")
            setOperationState(.failed(error: error.localizedDescription), for: package.id)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.setOperationState(.idle, for: package.id)
        }
    }
    
    func updatePackage(_ package: GenericPackage) async {
        setOperationState(.updating, for: package.id)
        
        do {
            try await brewManager.update(package)
            setOperationState(.success, for: package.id)
            await loadInstalledPackages()
            await loadOutdatedPackages()
            logger.info("Successfully updated package: \(package.id)")
        } catch {
            logger.error("Failed to update package \(package.id): \(error.localizedDescription)")
            setOperationState(.failed(error: error.localizedDescription), for: package.id)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.setOperationState(.idle, for: package.id)
        }
    }
    
    private func setOperationState(_ state: PackageOperationState, for packageId: String) {
        operationStates[packageId] = state
    }
    
    func getOperationState(for packageId: String) -> PackageOperationState {
        return operationStates[packageId] ?? .idle
    }
    
    func refreshAllData() async {
        await loadInstalledPackages()
        await loadOutdatedPackages()
    }
}

// MARK: - Package Manager View

struct PackageManagerIntegratedView: View {
    @StateObject private var coordinator = SimplePackageManagerCoordinator()
    @State private var searchText = ""
    @State private var selectedTab = 0
    @State private var searchResults: [GenericPackage] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            Picker("View", selection: $selectedTab) {
                Text("Installed").tag(0)
                if !coordinator.outdatedPackages.isEmpty {
                    Text("Updates (\(coordinator.outdatedPackages.count))").tag(1)
                }
                Text("Search").tag(2)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            // Content
            TabView(selection: $selectedTab) {
                // Installed packages
                PackageListTab(
                    packages: filteredInstalledPackages,
                    coordinator: coordinator,
                    emptyMessage: "No packages installed"
                )
                .tag(0)
                
                // Outdated packages
                if !coordinator.outdatedPackages.isEmpty {
                    PackageListTab(
                        packages: coordinator.outdatedPackages,
                        coordinator: coordinator,
                        emptyMessage: "All packages up to date"
                    )
                    .tag(1)
                }
                
                // Search
                SearchTab(
                    searchText: $searchText,
                    searchResults: $searchResults,
                    isSearching: $isSearching,
                    coordinator: coordinator
                )
                .tag(2)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        }
        .navigationTitle("Package Manager")
        .searchable(text: $searchText, prompt: "Search packages...")
        .onChange(of: searchText) { newValue in
            if selectedTab != 2 && !newValue.isEmpty {
                selectedTab = 2
            }
        }
        .task {
            await coordinator.refreshAllData()
        }
    }
    
    private var filteredInstalledPackages: [GenericPackage] {
        if searchText.isEmpty {
            return coordinator.installedPackages
        }
        
        return coordinator.installedPackages.filter { package in
            package.name.localizedCaseInsensitiveContains(searchText) ||
            package.description?.localizedCaseInsensitiveContains(searchText) == true
        }
    }
}

// MARK: - Supporting Views

struct PackageListTab: View {
    let packages: [GenericPackage]
    @ObservedObject var coordinator: SimplePackageManagerCoordinator
    let emptyMessage: String
    
    var body: some View {
        VStack(spacing: 0) {
            if coordinator.isLoading {
                ProgressView("Loading packages...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if packages.isEmpty {
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
                List(packages) { package in
                    PackageRowView(package: package, coordinator: coordinator)
                }
                .listStyle(PlainListStyle())
            }
        }
    }
}

struct SearchTab: View {
    @Binding var searchText: String
    @Binding var searchResults: [GenericPackage]
    @Binding var isSearching: Bool
    @ObservedObject var coordinator: SimplePackageManagerCoordinator
    @State private var searchTask: Task<Void, Never>?
    
    var body: some View {
        VStack(spacing: 0) {
            if searchText.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("Search for packages")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Enter a package name to find new packages to install")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
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
                    }
                    .padding()
                    
                    Divider()
                    
                    if searchResults.isEmpty && !isSearching {
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            
                            Text("No packages found")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text("Try a different search term")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(searchResults) { package in
                            PackageRowView(package: package, coordinator: coordinator)
                        }
                        .listStyle(PlainListStyle())
                    }
                }
            }
        }
        .onChange(of: searchText) { newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                
                if !Task.isCancelled && !newValue.isEmpty {
                    await performSearch(query: newValue)
                } else if newValue.isEmpty {
                    await MainActor.run {
                        searchResults = []
                    }
                }
            }
        }
    }
    
    @MainActor
    private func performSearch(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        let results = await coordinator.searchPackages(query)
        searchResults = results
        isSearching = false
    }
}

struct PackageRowView: View {
    let package: GenericPackage
    @ObservedObject var coordinator: SimplePackageManagerCoordinator
    @State private var showingDetail = false
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: { showingDetail = true }) {
                Image(systemName: package.manager.iconName)
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 24)
            }
            .buttonStyle(.plain)
            
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
            
            PackageActionView(package: package, coordinator: coordinator)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingDetail) {
            SimplePackageDetailView(package: package)
        }
    }
}

struct PackageActionView: View {
    let package: GenericPackage
    @ObservedObject var coordinator: SimplePackageManagerCoordinator
    
    var body: some View {
        let operationState = coordinator.getOperationState(for: package.id)
        
        HStack(spacing: 8) {
            if operationState.isActive {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text(operationState.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
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

struct SimplePackageDetailView: View {
    let package: GenericPackage
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack(spacing: 16) {
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
                                
                                if package.isInstalled {
                                    Text("Installed")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.2))
                                        .foregroundColor(.green)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
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
                    
                    // Description
                    if let description = package.description {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text(description)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("No description available.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                    
                    // Package Details
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Details")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        VStack(spacing: 8) {
                            HStack {
                                Text("Package ID")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(package.id)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            
                            HStack {
                                Text("Manager")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(package.manager.displayName)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            
                            if let version = package.version {
                                HStack {
                                    Text("Version")
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(version)
                                        .fontWeight(.medium)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(Color.secondary.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    
                    // Homepage Link
                    if let homepage = package.homepage, let url = URL(string: homepage) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Links")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Button(action: { NSWorkspace.shared.open(url) }) {
                                HStack {
                                    Image(systemName: "house")
                                        .foregroundColor(.blue)
                                    
                                    Text("Homepage")
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
        .frame(width: 500, height: 600)
    }
}

#Preview {
    PackageManagerIntegratedView()
}
//
//  PackageManagerCoordinator.swift
//  Applite
//
// Created by Subham mahesh
// licensed under the MIT
//

import Foundation
import SwiftUI
import OSLog

/// Coordinates multiple package managers and provides a unified interface
@MainActor
final class PackageManagerCoordinator: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var availableManagers: [PackageManagerType] = []
    @Published var allPackages: [GenericPackage] = []
    @Published var installedPackages: [GenericPackage] = []
    @Published var outdatedPackages: [GenericPackage] = []
    @Published var isLoading = false
    @Published var isUpdating = false
    @Published var operationStates: [String: PackageOperationState] = [:]
    
    // MARK: - Private Properties
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: PackageManagerCoordinator.self)
    )
    
    private var managers: [PackageManagerType: AnyPackageManager] = [:]
    
    // MARK: - Initialization
    
    init() {
        setupManagers()
        Task {
            await detectAvailableManagers()
            await loadInstalledPackages()
        }
    }
    
    private func setupManagers() {
        // Initialize Homebrew manager
        let brewManager = BrewPackageManager()
        managers[.homebrew] = AnyPackageManager(brewManager)
        
        // TODO: Add other package managers as needed
        // managers[.npm] = AnyPackageManager(NPMPackageManager())
        // managers[.pip] = AnyPackageManager(PipPackageManager())
    }
    
    // MARK: - Manager Detection
    
    func detectAvailableManagers() async {
        logger.info("Detecting available package managers")
        
        var available: [PackageManagerType] = []
        
        for (type, manager) in managers {
            if await manager.isAvailable {
                available.append(type)
                logger.info("Package manager available: \(type.displayName)")
            }
        }
        
        availableManagers = available
    }
    
    // MARK: - Package Loading
    
    func loadInstalledPackages() async {
        guard !isLoading else { return }
        
        isLoading = true
        logger.info("Loading installed packages from all managers")
        
        var allInstalled: [GenericPackage] = []
        
        for managerType in availableManagers {
            guard let manager = managers[managerType] else { continue }
            
            do {
                let packages = try await manager.getInstalledPackages()
                allInstalled.append(contentsOf: packages)
                logger.info("Loaded \(packages.count) packages from \(managerType.displayName)")
            } catch {
                logger.error("Failed to load packages from \(managerType.displayName): \(error.localizedDescription)")
            }
        }
        
        installedPackages = allInstalled
        isLoading = false
    }
    
    func loadOutdatedPackages() async {
        logger.info("Loading outdated packages from all managers")
        
        var allOutdated: [GenericPackage] = []
        
        for managerType in availableManagers {
            guard let manager = managers[managerType] else { continue }
            
            do {
                let packages = try await manager.getOutdatedPackages()
                allOutdated.append(contentsOf: packages)
                logger.info("Found \(packages.count) outdated packages from \(managerType.displayName)")
            } catch {
                logger.error("Failed to get outdated packages from \(managerType.displayName): \(error.localizedDescription)")
            }
        }
        
        outdatedPackages = allOutdated
    }
    
    func searchPackages(_ query: String, in managerTypes: [PackageManagerType] = []) async -> [GenericPackage] {
        guard !query.isEmpty else { return [] }
        
        let searchManagers = managerTypes.isEmpty ? availableManagers : managerTypes
        var results: [GenericPackage] = []
        
        for managerType in searchManagers {
            guard let manager = managers[managerType] else { continue }
            
            do {
                let packages = try await manager.searchPackages(query)
                results.append(contentsOf: packages)
            } catch {
                logger.error("Failed to search in \(managerType.displayName): \(error.localizedDescription)")
            }
        }
        
        return results
    }
    
    // MARK: - Package Operations
    
    func installPackage(_ package: GenericPackage) async {
        guard let manager = managers[package.manager] else {
            logger.error("Manager not available for package: \(package.id)")
            return
        }
        
        setOperationState(.installing, for: package.id)
        
        do {
            try await manager.install(package)
            setOperationState(.success, for: package.id)
            
            // Update installed packages
            await loadInstalledPackages()
            
            logger.info("Successfully installed package: \(package.id)")
        } catch {
            logger.error("Failed to install package \(package.id): \(error.localizedDescription)")
            setOperationState(.failed(error: error.localizedDescription), for: package.id)
        }
        
        // Reset state after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.setOperationState(.idle, for: package.id)
        }
    }
    
    func uninstallPackage(_ package: GenericPackage) async {
        guard let manager = managers[package.manager] else {
            logger.error("Manager not available for package: \(package.id)")
            return
        }
        
        setOperationState(.uninstalling, for: package.id)
        
        do {
            try await manager.uninstall(package)
            setOperationState(.success, for: package.id)
            
            // Update installed packages
            await loadInstalledPackages()
            
            logger.info("Successfully uninstalled package: \(package.id)")
        } catch {
            logger.error("Failed to uninstall package \(package.id): \(error.localizedDescription)")
            setOperationState(.failed(error: error.localizedDescription), for: package.id)
        }
        
        // Reset state after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.setOperationState(.idle, for: package.id)
        }
    }
    
    func updatePackage(_ package: GenericPackage) async {
        guard let manager = managers[package.manager] else {
            logger.error("Manager not available for package: \(package.id)")
            return
        }
        
        setOperationState(.updating, for: package.id)
        
        do {
            try await manager.update(package)
            setOperationState(.success, for: package.id)
            
            // Update packages
            await loadInstalledPackages()
            await loadOutdatedPackages()
            
            logger.info("Successfully updated package: \(package.id)")
        } catch {
            logger.error("Failed to update package \(package.id): \(error.localizedDescription)")
            setOperationState(.failed(error: error.localizedDescription), for: package.id)
        }
        
        // Reset state after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.setOperationState(.idle, for: package.id)
        }
    }
    
    func updateAllPackages(for managerType: PackageManagerType? = nil) async {
        guard !isUpdating else { return }
        
        isUpdating = true
        logger.info("Starting update all packages operation")
        
        let managersToUpdate = managerType.map { [$0] } ?? availableManagers
        
        for type in managersToUpdate {
            guard let manager = managers[type] else { continue }
            
            do {
                try await manager.updateAll()
                logger.info("Successfully updated all packages for \(type.displayName)")
            } catch {
                logger.error("Failed to update all packages for \(type.displayName): \(error.localizedDescription)")
            }
        }
        
        // Refresh package lists
        await loadInstalledPackages()
        await loadOutdatedPackages()
        
        isUpdating = false
        logger.info("Completed update all packages operation")
    }
    
    // MARK: - Package Information
    
    func getPackageInfo(_ packageId: String, manager: PackageManagerType) async -> GenericPackage? {
        guard let packageManager = managers[manager] else { return nil }
        
        do {
            return try await packageManager.getPackageInfo(packageId)
        } catch {
            logger.error("Failed to get package info for \(packageId): \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Operation State Management
    
    private func setOperationState(_ state: PackageOperationState, for packageId: String) {
        operationStates[packageId] = state
    }
    
    func getOperationState(for packageId: String) -> PackageOperationState {
        return operationStates[packageId] ?? .idle
    }
    
    // MARK: - Utility Methods
    
    func getPackagesByManager(_ managerType: PackageManagerType) -> [GenericPackage] {
        return installedPackages.filter { $0.manager == managerType }
    }
    
    func getOutdatedPackagesByManager(_ managerType: PackageManagerType) -> [GenericPackage] {
        return outdatedPackages.filter { $0.manager == managerType }
    }
    
    func refreshAllData() async {
        await detectAvailableManagers()
        await loadInstalledPackages()
        await loadOutdatedPackages()
    }
}

// MARK: - Type Erasing Wrapper

/// Type-erasing wrapper for package managers
private class AnyPackageManager {
    private let _install: (GenericPackage) async throws -> Void
    private let _uninstall: (GenericPackage) async throws -> Void
    private let _update: (GenericPackage) async throws -> Void
    private let _updateAll: () async throws -> Void
    private let _getInstalledPackages: () async throws -> [GenericPackage]
    private let _getOutdatedPackages: () async throws -> [GenericPackage]
    private let _searchPackages: (String) async throws -> [GenericPackage]
    private let _getPackageInfo: (String) async throws -> GenericPackage
    private let _isAvailable: () async -> Bool
    
    init<T: PackageManagerProtocol>(_ manager: T) where T.Package == GenericPackage {
        _install = manager.install
        _uninstall = manager.uninstall
        _update = manager.update
        _updateAll = manager.updateAll
        _getInstalledPackages = manager.getInstalledPackages
        _getOutdatedPackages = manager.getOutdatedPackages
        _searchPackages = manager.searchPackages
        _getPackageInfo = manager.getPackageInfo
        _isAvailable = { await manager.isAvailable }
    }
    
    var isAvailable: Bool {
        get async { await _isAvailable() }
    }
    
    func install(_ package: GenericPackage) async throws {
        try await _install(package)
    }
    
    func uninstall(_ package: GenericPackage) async throws {
        try await _uninstall(package)
    }
    
    func update(_ package: GenericPackage) async throws {
        try await _update(package)
    }
    
    func updateAll() async throws {
        try await _updateAll()
    }
    
    func getInstalledPackages() async throws -> [GenericPackage] {
        try await _getInstalledPackages()
    }
    
    func getOutdatedPackages() async throws -> [GenericPackage] {
        try await _getOutdatedPackages()
    }
    
    func searchPackages(_ query: String) async throws -> [GenericPackage] {
        try await _searchPackages(query)
    }
    
    func getPackageInfo(_ packageId: String) async throws -> GenericPackage {
        try await _getPackageInfo(packageId)
    }
}
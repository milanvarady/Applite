//
//  PackageManager.swift
//  Applite
//
//   Created by Subham mahesh
//   licensed under the MIT
//

import Foundation
import SwiftUI
import OSLog

// MARK: - Package Manager Protocol

/// Protocol defining the interface for package managers
protocol PackageManagerProtocol: AnyObject {
    /// The type of packages this manager handles
    associatedtype Package
    
    /// The name of this package manager
    var name: String { get }
    
    /// Whether this package manager is available on the system
    var isAvailable: Bool { get async }
    
    /// Install a package
    func install(_ package: Package) async throws
    
    /// Uninstall a package
    func uninstall(_ package: Package) async throws
    
    /// Update a package
    func update(_ package: Package) async throws
    
    /// Update all packages managed by this package manager
    func updateAll() async throws
    
    /// Get list of installed packages
    func getInstalledPackages() async throws -> [Package]
    
    /// Get list of outdated packages
    func getOutdatedPackages() async throws -> [Package]
    
    /// Search for packages
    func searchPackages(_ query: String) async throws -> [Package]
    
    /// Get package information
    func getPackageInfo(_ packageId: String) async throws -> Package
}

// MARK: - Package Manager Types

/// Enum representing different package manager types
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

/// Generic package model that can represent packages from different managers
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

// MARK: - Package Operation Progress

/// Represents the progress state of a package operation
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
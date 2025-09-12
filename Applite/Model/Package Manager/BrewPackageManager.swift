//
//  BrewPackageManager.swift
//  Applite
//
//   Created by Subham mahesh
//   licensed under the MIT
//

import Foundation
import OSLog

/// Package manager implementation for Homebrew
@MainActor
final class BrewPackageManager: PackageManagerProtocol {
    typealias Package = GenericPackage
    
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
    
    // MARK: - Package Operations
    
    func install(_ package: Package) async throws {
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
    
    func uninstall(_ package: Package) async throws {
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
    
    func update(_ package: Package) async throws {
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
    
    func updateAll() async throws {
        Self.logger.info("Updating all Homebrew packages")
        
        do {
            // First update homebrew itself
            _ = try await Shell.runBrewCommand(["update"])
            
            // Then upgrade all packages
            _ = try await Shell.runBrewCommand(["upgrade"])
            
            Self.logger.info("Successfully updated all Homebrew packages")
        } catch {
            Self.logger.error("Failed to update all packages: \(error.localizedDescription)")
            throw PackageManagerError.commandExecutionFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Package Information
    
    func getInstalledPackages() async throws -> [Package] {
        Self.logger.info("Fetching installed Homebrew packages")
        
        do {
            let output = try await Shell.runBrewCommand(["list", "--formula", "--versions"])
            return parseInstalledPackages(output)
        } catch {
            Self.logger.error("Failed to get installed packages: \(error.localizedDescription)")
            throw PackageManagerError.commandExecutionFailed(error.localizedDescription)
        }
    }
    
    func getOutdatedPackages() async throws -> [Package] {
        Self.logger.info("Fetching outdated Homebrew packages")
        
        do {
            let output = try await Shell.runBrewCommand(["outdated", "--formula"])
            return parseOutdatedPackages(output)
        } catch {
            Self.logger.error("Failed to get outdated packages: \(error.localizedDescription)")
            throw PackageManagerError.commandExecutionFailed(error.localizedDescription)
        }
    }
    
    func searchPackages(_ query: String) async throws -> [Package] {
        Self.logger.info("Searching for packages with query: \(query)")
        
        guard !query.isEmpty else {
            return []
        }
        
        do {
            let output = try await Shell.runBrewCommand(["search", query])
            return parseSearchResults(output, query: query)
        } catch {
            Self.logger.error("Failed to search packages: \(error.localizedDescription)")
            throw PackageManagerError.commandExecutionFailed(error.localizedDescription)
        }
    }
    
    func getPackageInfo(_ packageId: String) async throws -> Package {
        Self.logger.info("Getting info for package: \(packageId)")
        
        do {
            let output = try await Shell.runBrewCommand(["info", "--json", packageId])
            return try parsePackageInfo(output, packageId: packageId)
        } catch {
            Self.logger.error("Failed to get package info for \(packageId): \(error.localizedDescription)")
            throw PackageManagerError.packageNotFound(packageId)
        }
    }
    
    // MARK: - Parsing Methods
    
    private func parseInstalledPackages(_ output: String) -> [Package] {
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
    
    private func parseOutdatedPackages(_ output: String) -> [Package] {
        let lines = output.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        return lines.compactMap { line in
            // Format: package (current_version) < latest_version
            let components = line.components(separatedBy: " ")
            guard let packageName = components.first else { return nil }
            
            // Extract versions if present
            var currentVersion: String?
            var latestVersion: String?
            
            if let currentVersionMatch = line.range(of: #"\([^)]+\)"#, options: .regularExpression) {
                currentVersion = String(line[currentVersionMatch])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            }
            
            if let latestVersionIndex = components.lastIndex(of: "<"),
               latestVersionIndex + 1 < components.count {
                latestVersion = components[latestVersionIndex + 1]
            }
            
            return GenericPackage(
                id: packageName,
                name: packageName,
                version: currentVersion,
                manager: .homebrew,
                isInstalled: true,
                isOutdated: true,
                latestVersion: latestVersion
            )
        }
    }
    
    private func parseSearchResults(_ output: String, query: String) -> [Package] {
        let lines = output.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .filter { !$0.hasPrefix("==>") } // Remove section headers
        
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
    
    private func parsePackageInfo(_ jsonOutput: String, packageId: String) throws -> Package {
        guard let data = jsonOutput.data(using: .utf8) else {
            throw PackageManagerError.parseError("Invalid JSON data")
        }
        
        do {
            if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let packageInfo = jsonArray.first {
                
                let name = packageInfo["name"] as? String ?? packageId
                let description = packageInfo["desc"] as? String
                let homepage = packageInfo["homepage"] as? String
                let version = packageInfo["versions"] as? [String: String]
                let currentVersion = version?["stable"]
                
                // Check if package is installed
                let installedVersions = packageInfo["installed"] as? [[String: Any]]
                let isInstalled = !(installedVersions?.isEmpty ?? true)
                
                // Get dependencies
                let dependencies = packageInfo["dependencies"] as? [String] ?? []
                
                return GenericPackage(
                    id: packageId,
                    name: name,
                    version: currentVersion,
                    description: description,
                    manager: .homebrew,
                    isInstalled: isInstalled,
                    homepage: homepage,
                    dependencies: dependencies
                )
            }
        } catch {
            throw PackageManagerError.parseError("Failed to parse package info JSON: \(error.localizedDescription)")
        }
        
        throw PackageManagerError.packageNotFound(packageId)
    }
}
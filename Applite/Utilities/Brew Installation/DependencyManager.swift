//
//  DependencyManager.swift
//  Applite
//
//  Created by Milán Várady on 2023. 01. 14..
//

import Foundation
import OSLog

/// Installs app dependecies: Homebrew and Xcode Command Line Tools
///
/// Reports the current progress of the installation through a ``BrewInstallationProgress`` observable object
struct DependencyManager {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: DependencyManager.self)
    )

    /// Message shown when brew path is broken
    static let brokenPathOrIstallMessage = "Error. Broken brew path, or damaged installation. Check brew path in settings, or try reinstalling Homebrew (Manage Homebrew->Reinstall)"

    /// Installs dependencies to `~/Library/Application Support/Applite/homebrew/`
    ///
    /// - Parameters:
    ///   - progressObject: Progress will be reported here
    ///   - keepCurrentInstall: (default: `false`) If `true`, then if a  brew installation already exists it won't be deleted and reinstalled
    ///
    /// - Returns: `Void`
    static func install(progressObject: BrewInstallationProgress, keepCurrentInstall: Bool = false) async throws {
        Self.logger.info("Brew installation started")
        
        // Install command line tools
        if await !BrewPaths.isCommandLineToolsInstalled() {
            Self.logger.info("Prompting user to install Xcode Command Line Tools")

            try await Shell.runAsync("xcode-select --install")
            
            // Wait for command line tools installation with a 30 minute timeout
            var didBreak = false
            
            for _ in 0...360 {
                if await BrewPaths.isCommandLineToolsInstalled() {
                    didBreak = true
                    break
                }
                
                try await Task.sleep(for: .seconds(5))
            }
            
            if !didBreak {
                Self.logger.error("Command Line Tools Install timeout")
                throw DependencyError.xcodeCommandLineToolsTimeout
            }
        } else {
            Self.logger.info("Xcode Command Line Tool are already installed. Skipping...")
        }
        
        // Skip Homebrew installation if keepCurrentInstall is set to true
        let brewPathValid = await BrewPaths.isBrewPathValid(path: BrewPaths.appBrewExetutable.path)

        guard keepCurrentInstall && !brewPathValid else {
            Self.logger.notice("Brew is already installed, skipping installation")
            await MainActor.run { progressObject.phase = .done }
            return
        }

        await MainActor.run { progressObject.phase = .fetchingHomebrew }

        // Install brew
        try await Self.installHomebrew()
        
        await MainActor.run { progressObject.phase = .done }
        Self.logger.notice("Brew installed successfully!")
    }
    
    /// Installs Homebrew
    static func installHomebrew() async throws -> Void {
        Self.logger.info("Brew installation started")

        var isDirectory: ObjCBool = true

        // Delete Homebrew directory (~/Library/Application Support/Applite/homebrew) if exists so we have a clean install
        if FileManager.default.fileExists(atPath: BrewPaths.appBrewDirectory.path, isDirectory: &isDirectory) {
            Self.logger.info("Homebrew directory already exists, attempting to delete it")
            try FileManager.default.removeItem(at: BrewPaths.appBrewDirectory)
        }

        // Create Homebrew directory
        if !FileManager.default.fileExists(atPath: BrewPaths.appBrewDirectory.path, isDirectory: &isDirectory) {
            Self.logger.info("Attempting to create Homebrew directory")
            try FileManager.default.createDirectory(at: BrewPaths.appBrewDirectory, withIntermediateDirectories: true)
        }
        
        // Fetch Homebrew tarball
        Self.logger.info("Fetching tarball and unpacking")
        
        try await Shell.runAsync("curl -L https://github.com/Homebrew/brew/tarball/master | tar xz --strip 1 -C \"\(BrewPaths.appBrewDirectory.path)\"")

        Self.logger.info("Brew install done")
    }

    static func detectHomebrew() async -> BrewPaths.PathOption? {
        async let appleSilicon = BrewPaths.isBrewPathValid(path: BrewPaths.getBrewExectuablePath(for: .defaultAppleSilicon))
        async let intel = BrewPaths.isBrewPathValid(path: BrewPaths.getBrewExectuablePath(for: .defaultIntel))

        if await appleSilicon {
            return .defaultAppleSilicon
        }

        if await intel {
            return .defaultIntel
        }

        return nil
    }
}

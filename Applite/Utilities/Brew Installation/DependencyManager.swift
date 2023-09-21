//
//  DependencyManager.swift
//  Applite
//
//  Created by Milán Várady on 2023. 01. 14..
//

import Foundation
import os

/// Installs app dependecies: Homebrew, Xcode Command Line Tools and PINEntry
///
/// Reports the current progress of the installation through a ``BrewInstallationProgress`` observable object
public struct DependencyManager {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: DependencyManager.self)
    )
    
    /// Extracts percentage from shell output when installing brew
    static let percentageRegex = try! NSRegularExpression(pattern: #"(Receiving|Resolving).+:\s+(\d{1,3})%"#)
    
    /// Message shown when brew path is broken
    static public var brokenPathOrIstallMessage = "Error. Broken brew path, or damaged installation. Check brew path in settings, or try reinstalling Homebrew (Manage Homebrew->Reinstall)"
    
    /// Installs dependencies to `~/Library/Application Support/Applite/homebrew/`
    ///
    /// - Parameters:
    ///   - progressObject: Progress will be reported here
    ///   - keepCurrentInstall: (default: `false`) If `true`, then if a  brew installation already exists it won't be deleted and reinstalled
    ///
    /// - Returns: `Void`
    @MainActor
    static func install(progressObject: BrewInstallationProgress, keepCurrentInstall: Bool = false) async throws -> Void {
        Self.logger.info("Brew installation started")
        
        // Install command line tools
        if !isCommandLineToolsInstalled() {
            Self.logger.info("Prompting user to install Xcode Command Line Tools")
            
            let result = await shell("xcode-select --install")
            
            if result.didFail {
                Self.logger.error("Failed to request Xcode Command Line Tools install")
                Self.logger.error("\(result.output)")
                throw DependencyInstallationError.CommandLineToolsError
            }
            
            // Wait for command line tools installation with a 30 minute timeout
            var didBreak = false
            
            for _ in 0...360 {
                if isCommandLineToolsInstalled() {
                    didBreak = true
                    break
                }
                
                try await Task.sleep(for: Duration(secondsComponent: 5, attosecondsComponent: 0))
            }
            
            if !didBreak {
                Self.logger.error("Command Line Tools Install timeout")
                throw DependencyInstallationError.CommandLineToolsError
            }
        } else {
            Self.logger.info("Xcode Command Line Tool are already installed. Skipping...")
        }
        
        // Skip Homebrew installation if keepCurrentInstall is set to true
        if isBrewPathValid(path: BrewPaths.appBrewExetutable.path) && keepCurrentInstall {
            Self.logger.notice("Brew is already installed, skipping installation")
            progressObject.phase = .done
            return
        }
        
        progressObject.phase = .fetchingHomebrew
        
        // Install brew
        try await Self.installHomebrew()
        
        // Install Pinentry
        progressObject.phase = .installingPinentry
        try await Self.installPinentry()
        
        progressObject.phase = .done
        Self.logger.notice("Dependencies installed successfully!")
    }
    
    /// Installs Homebrew
    static func installHomebrew() async throws -> Void {
        Self.logger.info("Brew installation started")
        
        do {
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
        } catch {
            Self.logger.error("Couldn't create or remove Homebrew directory in Application Support")
            throw DependencyInstallationError.DirectoryError
        }
        
        // Fetch Homebrew tarball
        Self.logger.info("Fetching tarball and unpacking")
        
        let brewFetchResult = await shell("curl -L https://github.com/Homebrew/brew/tarball/master | tar xz --strip 1 -C \"\(BrewPaths.appBrewDirectory.path)\"")
        
        if brewFetchResult.didFail {
            Self.logger.error("Failed to fetch and unpack tarball")
            Self.logger.error("\(brewFetchResult.output)")
            throw DependencyInstallationError.BrewFetchError
        } else {
            Self.logger.info("Brew install done")
        }
    }
    
    /// Installs the `pinentry-mac` package for sudo askpass
    static func installPinentry(forceInstall: Bool = false) async throws {
        Self.logger.info("Installing pinentry-mac\(forceInstall ? " with --force flag" : "")")
        
        if await BrewPaths.isPinentryInstalled() {
            Self.logger.notice("pinentry-mac already installed. Skipping...")
            return
        }
        
        // Install gettext and libgpg-error first with the --force-bottle flag
        // gettext and libgpg-error are dependencies for pinentry-mac but if we do a normal install
        // it will fail when clang tries to find the cellar folder, because the path may have spaces in it. (e.g. Application Support)
        // So we can bypass bulding from source with the --force-bottle to download only the binraies
        Self.logger.info("Installing gettext and libgpg-error with --force-bottle flag")
        let dependencyResult = await shell("\(BrewPaths.currentBrewExecutable) install --force-bottle \(forceInstall ? "--force" : "") gettext libgpg-error")
        
        if dependencyResult.didFail {
            Self.logger.error("Failed to install gettext and libgpg-error with --force-bottle flag. Output: \(dependencyResult.output)")
            throw DependencyInstallationError.PinentryError
        }
        
        // Install pinentry-mac
        Self.logger.info("Installing pinentry-mac")
        let pinentryResult = await shell("\(BrewPaths.currentBrewExecutable) install \(forceInstall ? "--force" : "") pinentry-mac")
        
        if pinentryResult.didFail {
            Self.logger.error("Failed to install pinentry-mac. Output: \(pinentryResult.output)")
            throw DependencyInstallationError.PinentryError
        }
        
        Self.logger.info("pinentry-mac installation successfull")
    }
}

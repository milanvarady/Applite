//
//  BrewInstallation.swift
//  Applite
//
//  Created by Milán Várady on 2023. 01. 14..
//

import Foundation
import os

/// Installs Homebrew and Xcode command line tools
///
/// Reports the current progress of the installation through a ``BrewInstallationProgress`` observable object
public struct BrewInstallation {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: BrewInstallation.self)
    )
    
    /// Installation errors
    enum BrewInstallationError: Error {
        case CommandLineToolsError
        case DirectoryError
        case BrewFetchError
    }
    
    /// Extracts percentage from shell output when installing brew
    static let percentageRegex = try! NSRegularExpression(pattern: #"(Receiving|Resolving).+:\s+(\d{1,3})%"#)
    
    /// Message shown when brew path is broken
    static public var brokenPathOrIstallMessage = "Error. Broken brew path, or damaged installation. Check brew path in settings, or try reinstalling Homebrew (Manage Homebrew->Reinstall)"
    
    /// Installs Xcode Command Line Tools and Homebrew and  to `~/Library/Application Support/Applite/homebrew/`
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
                throw BrewInstallationError.CommandLineToolsError
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
                throw BrewInstallationError.CommandLineToolsError
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
        
        progressObject.phase = .done
        Self.logger.info("Brew installed successfully!")
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
            throw BrewInstallationError.DirectoryError
        }
        
        // Fetch Homebrew tarball
        Self.logger.info("Fetching tarball and unpacking")
        
        let brewFetchResult = await shell("curl -L https://github.com/Homebrew/brew/tarball/master | tar xz --strip 1 -C \"\(BrewPaths.appBrewDirectory.path)\"")
        
        if brewFetchResult.didFail {
            Self.logger.error("Failed to fetch and unpack tarball")
            Self.logger.error("\(brewFetchResult.output)")
            throw BrewInstallationError.BrewFetchError
        } else {
            Self.logger.info("Brew install done")
        }
    }
}

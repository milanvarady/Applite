//
//  UninstallSelf.swift
//  Applite
//
//  Created by Milán Várady on 2023. 06. 14..
//

import Foundation
import OSLog

/// This function will uninstall Applite and all it's related files
func uninstallSelf(deleteBrewCache: Bool, uninstallHomebrew: Bool = false) async throws {
    let logger = Logger()
    
    logger.notice("Applite uninstallation stated. deleteBrewCache: \(deleteBrewCache), uninstallHomebrew: \(uninstallHomebrew)")

    logger.notice("Clearing image cache")
    await ImageLoader.shared.clearCache()
    logger.notice("Image cache cleared")

    logger.notice("Deleting library files")

    // Delete related files and cache (using -rf to ignore missing files)
    let command = """
    rm -rf "$HOME/Library/Application Support/Applite";
    rm -rf "$HOME/Library/Application Support/\(Bundle.main.bundleIdentifier!)";
    rm -rf $HOME/Library/Containers/\(Bundle.main.bundleIdentifier!);
    rm -rf $HOME/Library/Caches/Applite;
    rm -rf $HOME/Library/Caches/\(Bundle.main.bundleIdentifier!);
    rm -rf $HOME/Library/Applite;
    rm -rf $HOME/Library/Preferences/*\(Bundle.main.bundleIdentifier!)*.plist;
    rm -rf "$HOME/Library/Saved Application State/\(Bundle.main.bundleIdentifier!).savedState";
    rm -rf $HOME/Library/SyncedPreferences/\(Bundle.main.bundleIdentifier!)*.plist;
    rm -rf $HOME/Library/WebKit/\(Bundle.main.bundleIdentifier!);
    rm -rf $HOME/Library/HTTPStorages/dev.aerolite.Applite
    """
    
    logger.notice("Running command: \(command)")
    
    let output = try await Shell.runAsync(command)

    logger.notice("Uninstall result: \(output)")
    
    // If uninstalling Homebrew, delete cache first and then uninstall Homebrew
    if uninstallHomebrew {
        logger.notice("Deleting Homebrew cache before uninstalling Homebrew")
        try await Shell.runAsync("rm -rf $HOME/Library/Caches/Homebrew")
        
        logger.notice("Uninstalling Homebrew")
        try await uninstallHomebrewCompletely()
    } else if deleteBrewCache {
        // Only delete cache if not uninstalling Homebrew (since it would be redundant)
        logger.notice("Deleting Homebrew cache")
        try await Shell.runAsync("rm -rf $HOME/Library/Caches/Homebrew")
    }
    
    logger.notice("Self destructing. Goodbye world! o7")
    
    // Quit the app and remove it
    let process = Process()
    process.launchPath = "/bin/bash"
    process.arguments = ["-c", "osascript -e 'tell application \"Applite\" to quit' && sleep 2 && rm -rf \"\(Bundle.main.bundlePath)\" && defaults write \(Bundle.main.bundleIdentifier!) setupComplete 0"]
    process.launch()
}

/// Uninstalls Homebrew completely using the official uninstaller script
private func uninstallHomebrewCompletely() async throws {
    let logger = Logger()
    
    logger.notice("Starting Homebrew uninstallation using official uninstaller script")
    
    // First try to run the uninstaller non-interactively
    let uninstallCommand = """
    export NONINTERACTIVE=1; \
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
    """
    
    do {
        let output = try await Shell.runAsync(uninstallCommand)
        logger.notice("Homebrew uninstall output: \(output)")
    } catch {
        logger.error("Failed to uninstall Homebrew: \(error.localizedDescription)")
        
        // Check if it's a ShellError and provide better error message
        if case .nonZeroExit(_, let exitCode, let output) = error as? ShellError {
            // Handle case where Homebrew is not found (this is not really an error)
            if output.contains("Failed to locate Homebrew") || 
               output.contains("Homebrew is not installed") ||
               output.contains("No such file or directory") && output.contains("brew") {
                logger.notice("Homebrew not found - it may already be uninstalled or never installed")
                return // Exit successfully since there's nothing to uninstall
            }
            
            if exitCode == 127 || output.contains("Permission denied") || output.contains("sudo") || output.contains("administrator") {
                throw NSError(
                    domain: "HomebrewUninstallError",
                    code: Int(exitCode),
                    userInfo: [
                        NSLocalizedDescriptionKey: "Homebrew uninstallation requires administrator privileges",
                        NSLocalizedRecoverySuggestionErrorKey: "The Homebrew uninstaller requires admin privileges to remove system files. Please run this operation as an administrator or manually uninstall Homebrew using Terminal with 'sudo' privileges."
                    ]
                )
            }
        }
        
        throw error
    }
}

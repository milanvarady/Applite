//
//  UninstallSelf.swift
//  Applite
//
//  Created by Milán Várady on 2023. 06. 14..
//

import Foundation
import OSLog
import Kingfisher

/// This function will uninstall Applite and all it's related files
func uninstallSelf(deleteBrewCache: Bool, uninstallHomebrew: Bool = false) async throws {
    let logger = Logger()
    let bundleID = Bundle.main.bundleIdentifier ?? "dev.aerolite.Applite"

    logger.notice("Applite uninstallation started. deleteBrewCache: \(deleteBrewCache), uninstallHomebrew: \(uninstallHomebrew)")

    // Clear Kingfisher image cache (disk cache is also covered by the rm below)
    logger.notice("Clearing Kingfisher image cache")
    let cache = ImageCache.default
    cache.clearMemoryCache()
    await cache.clearDiskCache()

    // Delete related files and cache.
    // Paths containing spaces are quoted; the Preferences/SyncedPreferences
    // entries are left unquoted on purpose so the shell expands their globs.
    let paths = [
        "\"$HOME/Library/Application Support/Applite\"",
        "\"$HOME/Library/Application Support/\(bundleID)\"",
        "$HOME/Library/Containers/\(bundleID)",
        "$HOME/Library/Caches/Applite",
        "$HOME/Library/Caches/\(bundleID)",
        "$HOME/Library/Applite",
        "$HOME/Library/Preferences/*\(bundleID)*.plist",
        "\"$HOME/Library/Saved Application State/\(bundleID).savedState\"",
        "$HOME/Library/SyncedPreferences/\(bundleID)*.plist",
        "$HOME/Library/WebKit/\(bundleID)",
        "$HOME/Library/HTTPStorages/\(bundleID)"
    ]

    // Do the step that can fail on permissions (Homebrew uninstall) BEFORE any irreversible wipe of
    // Applite's own data. Otherwise a no-admin failure throws *after* the data is already gone,
    // leaving the user with wiped settings, a failed uninstall, and a still-installed app (P2-12).
    if uninstallHomebrew {
        logger.notice("Uninstalling Homebrew")
        try await uninstallHomebrewCompletely()

        logger.notice("Deleting Homebrew cache")
        try await Shell.runShellScript("rm -rf $HOME/Library/Caches/Homebrew")
    } else if deleteBrewCache {
        // Only delete cache if not uninstalling Homebrew (since it would be redundant)
        logger.notice("Deleting Homebrew cache")
        try await Shell.runShellScript("rm -rf $HOME/Library/Caches/Homebrew")
    }

    // Everything below is irreversible — only reached once the throwing Homebrew uninstall succeeded.
    // -rf so missing files are ignored; each path on its own line runs independently
    let deleteCommand = paths
        .map { "rm -rf \($0)" }
        .joined(separator: "\n")

    logger.notice("Deleting library files:\n\(deleteCommand)")

    let output = try await Shell.runShellScript(deleteCommand)
    logger.notice("Uninstall result: \(output)")

    logger.notice("Self destructing. Goodbye world! o7")

    // Quit the app and remove the bundle.
    // Steps are newline-separated (not &&) so a slow/failed quit still
    // lets the cleanup run.
    let selfDestruct = """
    osascript -e 'tell application "Applite" to quit'
    sleep 2
    rm -rf "\(Bundle.main.bundlePath)"
    """

    let process = Process()
    process.launchPath = "/bin/bash"
    process.arguments = ["-c", selfDestruct]
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
        let output = try await Shell.runShellScript(uninstallCommand)
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

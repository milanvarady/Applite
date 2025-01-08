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
func uninstallSelf(deleteBrewCache: Bool) async throws {
    let logger = Logger()
    
    logger.notice("Applite uninstallation stated. deleteBrewCache: \(deleteBrewCache)")

    logger.notice("Clearing Kingfisher image cache")

    let cache = ImageCache.default
    cache.clearMemoryCache()
    cache.clearDiskCache {
        logger.notice("Kingfisher disk image cache cleared")
    }

    logger.notice("Deleting library files")

    // Delete related files and cache
    let command = """
    rm -r "$HOME/Library/Application Support/Applite";
    rm -r "$HOME/Library/Application Support/\(Bundle.main.bundleIdentifier!)";
    rm -r $HOME/Library/Containers/\(Bundle.main.bundleIdentifier!);
    rm -r $HOME/Library/Caches/Applite;
    rm -r $HOME/Library/Caches/\(Bundle.main.bundleIdentifier!);
    rm -r $HOME/Library/Applite;
    rm -r $HOME/Library/Preferences/*\(Bundle.main.bundleIdentifier!)*.plist;
    rm -r "$HOME/Library/Saved Application State/\(Bundle.main.bundleIdentifier!).savedState";
    rm -r $HOME/Library/SyncedPreferences/\(Bundle.main.bundleIdentifier!)*.plist;
    rm -r $HOME/Library/WebKit/\(Bundle.main.bundleIdentifier!);
    rm -r $HOME/Library/HTTPStorages/dev.aerolite.Applite
    """
    
    logger.notice("Running command: \(command)")
    
    let output = try await Shell.runAsync(command)

    logger.notice("Uninstall result: \(output)")
    
    // Homebrew cache
    if deleteBrewCache {
        try await Shell.runAsync("rm -rf $HOME/Library/Caches/Homebrew")
    }
    
    logger.notice("Self destructing. Goodbye world! o7")
    
    // Quit the app and remove it
    let process = Process()
    process.launchPath = "/bin/bash"
    process.arguments = ["-c", "osascript -e 'tell application \"Applite\" to quit' && sleep 2 && rm -rf \"\(Bundle.main.bundlePath)\" && defaults write \(Bundle.main.bundleIdentifier!) setupComplete 0"]
    process.launch()
}

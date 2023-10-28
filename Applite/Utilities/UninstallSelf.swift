//
//  UninstallSelf.swift
//  Applite
//
//  Created by Milán Várady on 2023. 06. 14..
//

import Foundation
import os

enum UninstallError: Error {
    case fileError
}

/// This function will uninstall Applite and all it's related files
func uninstallSelf(deleteBrewCache: Bool) {
    let logger = Logger()
    
    logger.notice("Applite uninstallation stated. deleteBrewCache: \(deleteBrewCache)")
    
    // Delete related files and cache
    let command = """
    rm -r "$HOME/Library/Application Support/\(Bundle.main.appName)";
    rm -r "$HOME/Library/Application Support/\(Bundle.main.bundleIdentifier!)";
    rm -r $HOME/Library/Containers/\(Bundle.main.bundleIdentifier!);
    rm -r $HOME/Library/Caches/\(Bundle.main.appName);
    rm -r $HOME/Library/Caches/\(Bundle.main.bundleIdentifier!);
    rm -r $HOME/Library/\(Bundle.main.appName);
    rm -r $HOME/Library/Preferences/*\(Bundle.main.bundleIdentifier!)*.plist;
    rm -r "$HOME/Library/Saved Application State/\(Bundle.main.bundleIdentifier!).savedState";
    rm -r $HOME/Library/SyncedPreferences/\(Bundle.main.bundleIdentifier!)*.plist;
    rm -r $HOME/Library/WebKit/\(Bundle.main.bundleIdentifier!);
    rm -r $HOME/Library/HTTPStorages/dev.aerolite.Applite
    """
    
    logger.notice("Running command: \(command)")
    
    let result = shell(command)
    
    
    logger.notice("Uninstall result: \(result.output)")
    
    // Homebrew cache
    if deleteBrewCache {
        shell("rm -rf $HOME/Library/Caches/Homebrew")
    }
    
    logger.notice("Self destructing. Goodbye world!")
    
    // Quit the app and remove it
    let process = Process()
    process.launchPath = "/bin/bash"
    process.arguments = ["-c", "osascript -e 'tell application \"\(Bundle.main.appName)\" to quit' && sleep 2 && rm -rf \"\(Bundle.main.bundlePath)\" && defaults write \(Bundle.main.bundleIdentifier!) setupComplete 0"]
    process.launch()
}

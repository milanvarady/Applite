//
//  UninstallSelf.swift
//  Applite
//
//  Created by Milán Várady on 2023. 06. 14..
//

import Foundation

enum UninstallError: Error {
    case fileError
}

/// This function will uninstall Applite and all it's related files
func uninstallSelf(deleteBrewCache: Bool) {
    // Delete related files and cache
    let command = """
    rm -rf "~/Library/Application Support/\(Bundle.main.appName)";
    rm -rf "~/Library/Application Support/\(Bundle.main.bundleIdentifier!)";
    rm -rf ~/Library/Containers/\(Bundle.main.bundleIdentifier!);
    rm -rf ~/Library/Caches/\(Bundle.main.appName);
    rm -rf ~/Library/Caches/\(Bundle.main.bundleIdentifier!);
    rm -rf ~/Library/\(Bundle.main.appName);
    rm -rf ~/Library/Preferences/*\(Bundle.main.bundleIdentifier!)*.plist;
    rm -rf "~/Library/Saved Application State/\(Bundle.main.bundleIdentifier!).savedState";
    rm -rf ~/Library/SyncedPreferences/\(Bundle.main.bundleIdentifier!)*.plist;
    rm -rf ~/Library/WebKit/\(Bundle.main.bundleIdentifier!);
    """
    
    shell(command)
    
    // Homebrew cache
    if deleteBrewCache {
        shell("rm -rf ~/Library/Caches/Homebrew")
    }
    
    // Quit the app and remove it
    let process = Process()
    process.launchPath = "/bin/bash"
    process.arguments = ["-c", "osascript -e 'tell application \"\(Bundle.main.appName)\" to quit' && sleep 2 && rm -rf \"/Applications/\(Bundle.main.appName).app\" && defaults write \(Bundle.main.bundleIdentifier!) setupComplete 0"]
    process.launch()
}

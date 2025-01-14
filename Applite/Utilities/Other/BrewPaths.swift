//
//  BrewPaths.swift
//  Applite
//
//  Created by Milán Várady on 2023. 06. 12..
//

import Foundation

/// Holds the different brew directory and executable paths, provides methods to retrieve and verify the currently selected path
struct BrewPaths {
    /// Brew executable path options
    enum PathOption: Int, CaseIterable, Identifiable {
        /// Applite's own brew in Application Support folder
        case appPath = 0
        /// Default path for Apple Silicon macs
        case defaultAppleSilicon = 1
        /// Default path for Intel based macs
        case defaultIntel = 2
        /// User selected custom path
        case custom = 3
        
        var id: Int {
            return self.rawValue
        }
    }
    
    /// Retrieves and sets the currently selected ``PathOption`` from user defaults
    static var selectedBrewOption: PathOption {
        set {
            UserDefaults.standard.setValue(newValue.rawValue, forKey: "brewPathOption")
        }
        get {
            return PathOption(rawValue: UserDefaults.standard.integer(forKey: "brewPathOption")) ?? .appPath
        }
    }
    
    /// Returns the brew executable path for the specified option
    ///
    /// - Parameters:
    ///   - for: Brew path to return
    ///   - shellFriendly: If true the path will be enclosed in " marks so shell doesn't fail on spaces
    ///
    /// - Returns: `String`
    static func getBrewExectuablePath(for option: PathOption) -> URL {
        switch option {
        case .appPath:
            return appBrewExetutable

        case .defaultAppleSilicon:
            return URL(fileURLWithPath: "/opt/homebrew/bin/brew")

        case .defaultIntel:
            return URL(fileURLWithPath: "/usr/local/bin/brew")

        case .custom:
            return URL(fileURLWithPath: UserDefaults.standard.string(forKey: "customUserBrewPath") ?? "")
        }
    }
    
    /// Brew directory when installing brew separately into Application Support
    static let appBrewDirectory = URL.applicationSupportDirectory
        .appendingPathComponent("Applite", isDirectory: true)
        .appendingPathComponent("homebrew", isDirectory: true)
    
    /// Brew exectuable path when installing brew separately into Application Support
    static let appBrewExetutable = URL.applicationSupportDirectory
        .appendingPathComponent("Applite", isDirectory: true)
        .appendingPathComponent("homebrew", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("brew")
    
    /// Dynamically returns the current brew directory in use
    static var currentBrewDirectory: URL {
        switch Self.selectedBrewOption {
        case .appPath:
            return appBrewDirectory

        case .defaultAppleSilicon:
            return URL(fileURLWithPath: "/opt/homebrew")

        case .defaultIntel:
            return URL(fileURLWithPath: "/usr/local")

        case .custom:
            let path = UserDefaults.standard.string(forKey: "customUserBrewPath")?.replacing("/bin/brew", with: "") ?? ""
            return URL(fileURLWithPath: path)
        }
    }
    
    /// Returns the brew path currently in use (selected in settings), as a `String` enclosed in " marks so shell scripts don't fail beacuse of spaces
    static var currentBrewExecutable: URL {
        return getBrewExectuablePath(for: selectedBrewOption)
    }

    /// Checks if a brew executable path is valid or not
    ///
    /// - Parameters:
    ///   - path: Path to be checked
    ///
    /// - Returns: Whether the path is valid or not
    static func isBrewPathValid(at url: URL) async -> Bool {
        // Check if Homebrew is returned when checking version
        guard let output = try? await Shell.runAsync("\(url.quotedPath()) --version") else {
            return false
        }

        return output.contains("Homebrew")
    }

    /// Checks if currently selected brew executable path is valid
    static func isSelectedBrewPathValid() async -> Bool {
        return await isBrewPathValid(at: Self.currentBrewExecutable)
    }

    /// Checks if Xcode Command Line Tools is installed
    ///
    /// - Returns: Whether it is installed or not
    static func isCommandLineToolsInstalled() async -> Bool {
        do {
            try await Shell.runAsync("xcode-select -p")
        } catch {
            return false
        }

        return true
    }

}

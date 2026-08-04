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
        /// Applite's own ("annex") brew in the Application Support folder
        case annex = 0
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
            UserDefaults.standard.setValue(newValue.rawValue, for: Preferences.brewPathOption)
        }
        get {
            return PathOption(rawValue: UserDefaults.standard.value(for: Preferences.brewPathOption)) ?? .annex
        }
    }
    
    /// Returns the `brew` executable URL for the specified option.
    static func brewExecutable(for option: PathOption) -> URL {
        switch option {
        case .annex:
            return annexBrewExecutable

        case .defaultAppleSilicon:
            return URL(fileURLWithPath: "/opt/homebrew/bin/brew")

        case .defaultIntel:
            return URL(fileURLWithPath: "/usr/local/bin/brew")

        case .custom:
            return URL(fileURLWithPath: UserDefaults.standard.value(for: Preferences.customUserBrewPath))
        }
    }
    
    /// Directory of Applite's own ("annex") brew, installed into Application Support
    static let annexBrewDirectory = AppPaths.applicationSupport
        .appending(path: "Homebrew", directoryHint: .isDirectory)

    /// Executable path of Applite's own ("annex") brew, installed into Application Support
    static let annexBrewExecutable = Self.annexBrewDirectory
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("brew")

    /// The prefix (Homebrew root) of the currently selected brew. Every option's executable is
    /// `<prefix>/bin/brew`, so the directory is that path with the two trailing components dropped.
    static var currentBrewDirectory: URL {
        currentBrewExecutable
            .deletingLastPathComponent()  // drop "brew"
            .deletingLastPathComponent()  // drop "bin"
    }

    /// The `brew` executable currently in use (selected in settings).
    static var currentBrewExecutable: URL {
        return brewExecutable(for: selectedBrewOption)
    }

    /// Checks if a brew executable path is valid or not
    ///
    /// - Parameters:
    ///   - path: Path to be checked
    ///
    /// - Returns: Whether the path is valid or not
    static func isBrewPathValid(at url: URL) async -> Bool {
        // Check if Homebrew is returned when checking version. Argv-based (the path is never
        // spliced into a shell) and time-boxed so a hung/locked/network-mounted brew can't stall
        // app launch — the whole bootstrap awaits this before it can leave `.checking`.
        guard let output = try? await Shell.run(url, ["--version"], timeout: .seconds(10)) else {
            return false
        }

        return output.contains("Homebrew")
    }

    /// Checks if currently selected brew executable path is valid
    static func isSelectedBrewPathValid() async -> Bool {
        return await isBrewPathValid(at: Self.currentBrewExecutable)
    }

    // MARK: - Detection

    /// Attempts to locate a working Homebrew installation, fail-safe: the two arch-default
    /// prefixes are probed concurrently, then any brew on the user's `PATH` (covering
    /// non-standard prefixes). Every candidate is validated by actually running `brew --version`.
    ///
    /// - Parameter setPathOption: When `true`, the first match is written to
    ///   ``selectedBrewOption`` (and, for a non-standard location, `customUserBrewPath`).
    /// - Returns: The matched ``PathOption``, or `nil` if no working brew was found.
    static func detectHomebrew(setPathOption: Bool) async -> PathOption? {
        async let appleSilicon = isBrewPathValid(at: brewExecutable(for: .defaultAppleSilicon))
        async let intel = isBrewPathValid(at: brewExecutable(for: .defaultIntel))

        if await appleSilicon {
            if setPathOption { selectedBrewOption = .defaultAppleSilicon }
            return .defaultAppleSilicon
        }

        if await intel {
            if setPathOption { selectedBrewOption = .defaultIntel }
            return .defaultIntel
        }

        // Last resort: a brew installed at a non-standard prefix, resolved via the login shell's PATH.
        if let resolved = await resolveBrewOnPath(), await isBrewPathValid(at: resolved) {
            return adopt(resolvedBrewExecutable: resolved, setPathOption: setPathOption)
        }

        return nil
    }

    /// Maps a resolved brew executable to a ``PathOption``. Standard prefixes map to their arch
    /// default; anything else is stored as the custom path so the rest of the app (which switches
    /// on `PathOption`) keeps working.
    private static func adopt(resolvedBrewExecutable url: URL, setPathOption: Bool) -> PathOption {
        let path = url.path(percentEncoded: false)
        let option: PathOption

        switch path {
        case "/opt/homebrew/bin/brew":
            option = .defaultAppleSilicon
        case "/usr/local/bin/brew":
            option = .defaultIntel
        default:
            UserDefaults.standard.setValue(path, for: Preferences.customUserBrewPath)
            option = .custom
        }

        if setPathOption { selectedBrewOption = option }
        return option
    }

    /// Resolves a `brew` executable from the environment: `$HOMEBREW_PREFIX/bin/brew` if set,
    /// otherwise the login shell's `PATH`. The login-shell probe uses a timeout so a hung shell
    /// (e.g. a broken `.zshrc`) can never stall app launch.
    private static func resolveBrewOnPath() async -> URL? {
        if let prefix = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"], !prefix.isEmpty {
            let candidate = URL(fileURLWithPath: prefix)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("brew")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        // A login shell (`-l`) sources the user's profile, so `command -v brew` sees the PATH they
        // actually use — this is what finds brew at a non-standard prefix.
        guard let output = try? await Shell.run(URL(fileURLWithPath: "/bin/zsh"), ["-lc", "command -v brew"], timeout: .seconds(5)) else {
            return nil
        }

        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
}

//
//  InstalledAppLocator.swift
//  Applite
//
//  Created by Claude on 2026. 07. 24..
//

import Foundation
import AppKit
import OSLog

/// Resolves the on-disk location of an installed cask's primary `.app` bundle.
///
/// Opening an app used to be a single string-glob handed to the shell `open`, which broke whenever
/// the installed bundle filename differed from Homebrew's display name (common for `.pkg` casks).
/// This locator instead tries a few strategies in priority order and returns the first URL that
/// actually exists on disk, so the launch path degrades gracefully instead of failing outright.
///
/// Every strategy reads files Homebrew already wrote (the Caskroom and its `.metadata`) or queries
/// LaunchServices — no `brew` subprocess on the launch path.
enum InstalledAppLocator {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "InstalledAppLocator")

    /// Resolves the URL of the installed app for a cask.
    ///
    /// - Parameters:
    ///   - token: The cask token (e.g. `"firefox"`), used to locate its Caskroom entry.
    ///   - displayName: Homebrew's display name, used only as a last-resort filename guess.
    /// - Returns: The URL of an existing `.app` bundle, or `nil` if none of the strategies located it.
    ///
    /// Pure disk/LaunchServices lookups — safe to call off the main actor.
    nonisolated static func appURL(token: String, displayName: String) -> URL? {
        let caskroom = BrewPaths.currentBrewDirectory
            .appending(path: "Caskroom", directoryHint: .isDirectory)
            .appending(path: token, directoryHint: .isDirectory)

        let artifacts = artifacts(caskDirectory: caskroom, token: token)

        // 1. The Caskroom app symlink brew created — points at the real install regardless of appdir.
        if let url = caskroomSymlinkTarget(caskroom: caskroom) {
            return url
        }

        // 2. The exact bundle name from the cask's `app` artifact, resolved against the appdir.
        if let name = appBundleName(fromArtifacts: artifacts) {
            let url = appDirectory.appending(path: name, directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        // 3. Last-resort guess: the display name as a bundle filename in the appdir.
        let guess = appDirectory.appending(path: "\(displayName).app", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: guess.path) {
            return guess
        }

        // 4. Ask LaunchServices by bundle identifier (from the cask's uninstall/zap `quit`).
        if let bundleID = bundleIdentifier(fromArtifacts: artifacts),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url
        }

        logger.warning("Could not locate installed app for cask \(token, privacy: .public)")
        return nil
    }

    // MARK: - Strategy 1: Caskroom symlink

    /// Finds the newest version directory under the Caskroom entry and resolves the `.app` symlink
    /// brew placed there to its real target.
    private nonisolated static func caskroomSymlinkTarget(caskroom: URL) -> URL? {
        let fm = FileManager.default

        guard let versionDirs = try? fm.contentsOfDirectory(
            at: caskroom,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]   // skips `.metadata`
        ) else {
            return nil
        }

        // Newest version first — brew usually keeps only one, but be defensive.
        let sorted = versionDirs.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l > r
        }

        for versionDir in sorted {
            guard let contents = try? fm.contentsOfDirectory(
                at: versionDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            if let app = contents.first(where: { $0.pathExtension == "app" }) {
                // Resolve the symlink to its real target and confirm it still exists.
                let resolved = app.resolvingSymlinksInPath()
                if fm.fileExists(atPath: resolved.path) {
                    return resolved
                }
            }
        }

        return nil
    }

    // MARK: - Strategy 2 & 4: cask metadata

    /// Reads and parses the `artifacts` array from the newest on-disk cask metadata JSON that brew
    /// wrote at install time (`<caskroom>/.metadata/<version>/<ts>/Casks/<token>.json`).
    private nonisolated static func artifacts(caskDirectory: URL, token: String) -> [[String: Any]] {
        let fm = FileManager.default
        let metadataDir = caskDirectory.appending(path: ".metadata", directoryHint: .isDirectory)

        guard let enumerator = fm.enumerator(
            at: metadataDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return []
        }

        // Collect every `<token>.json` and pick the most recently written one.
        var newest: (url: URL, date: Date)?
        for case let url as URL in enumerator where url.lastPathComponent == "\(token).json" {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if newest == nil || date > newest!.date {
                newest = (url, date)
            }
        }

        guard let jsonURL = newest?.url,
              let data = try? Data(contentsOf: jsonURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let artifacts = object["artifacts"] as? [[String: Any]] else {
            return []
        }

        return artifacts
    }

    /// Extracts the installed `.app` bundle filename from an `app` artifact.
    ///
    /// An `app` entry is `["Source.app"]` or `["Source.app", {"target": "Renamed.app"}]`; the
    /// `target` (when present) is what actually lands in the appdir, so it wins.
    private nonisolated static func appBundleName(fromArtifacts artifacts: [[String: Any]]) -> String? {
        for entry in artifacts {
            guard let app = entry["app"] as? [Any] else { continue }

            var sourceName: String?
            for element in app {
                if let string = element as? String {
                    sourceName = string
                } else if let options = element as? [String: Any],
                          let target = options["target"] as? String {
                    return (target as NSString).lastPathComponent
                }
            }

            if let sourceName {
                return (sourceName as NSString).lastPathComponent
            }
        }

        return nil
    }

    /// Extracts the app's bundle identifier from the cask's `uninstall`/`zap` `quit` directive
    /// (e.g. `{"quit": "com.1password.1password"}`). This is the id LaunchServices can resolve.
    private nonisolated static func bundleIdentifier(fromArtifacts artifacts: [[String: Any]]) -> String? {
        for entry in artifacts {
            for key in ["uninstall", "zap"] {
                guard let directives = entry[key] as? [[String: Any]] else { continue }

                for directive in directives {
                    if let quit = directive["quit"] {
                        if let id = quit as? String {
                            return id
                        }
                        if let ids = quit as? [String], let first = ids.first {
                            return first
                        }
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Appdir

    /// The directory installed apps live in: the user's appdir override when enabled, else `/Applications`.
    private nonisolated static var appDirectory: URL {
        let custom = UserDefaults.standard.value(for: Preferences.appdirPath)
        if UserDefaults.standard.value(for: Preferences.appdirOn), !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return URL.applicationDirectory
    }
}

// MARK: - Launch error

enum AppLaunchError: LocalizedError {
    case appNotFound(name: String)

    var errorDescription: String? {
        switch self {
        case .appNotFound(let name):
            return String(localized: "Applite couldn't locate \(name) on disk")
        }
    }
}

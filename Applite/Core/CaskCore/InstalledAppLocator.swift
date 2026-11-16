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

    private struct RecordedCask: Decodable {
        struct URLSpecs: Decodable {
            let only_path: String?
        }
        let artifacts: [CaskArtifact]?
        let url_specs: URLSpecs?
    }

    private struct InstalledReceipt: Decodable {
        let uninstall_artifacts: [CaskArtifact]?
    }

    nonisolated static func recordedAppURLs(token: String, executable: URL) throws -> [URL] {
        guard !token.isEmpty, token != ".", token != "..",
              (token as NSString).lastPathComponent == token else {
            throw CaskAdoptionError.installationTargetsUnavailable
        }
        let caskroom = executable.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Caskroom").appendingPathComponent(token)
        let fm = FileManager.default
        let versions: [URL]
        do {
            versions = try fm.contentsOfDirectory(
                at: caskroom, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            )
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            throw CaskAdoptionError.installationTargetsUnavailable
        }
        guard !versions.isEmpty else { throw CaskAdoptionError.installationTargetsUnavailable }
        let metadata = caskroom.appendingPathComponent(".metadata")
        let receipt: InstalledReceipt?
        do {
            receipt = try JSONDecoder().decode(
                InstalledReceipt.self, from: Data(contentsOf: metadata.appendingPathComponent("INSTALL_RECEIPT.json"))
            )
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            receipt = nil
        }
        var result: Set<URL> = []
        for version in versions.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            let values = try version.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let timestamps: [URL]
            do {
                timestamps = try fm.contentsOfDirectory(
                    at: metadata.appendingPathComponent(version.lastPathComponent),
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]
                ).sorted { $0.lastPathComponent > $1.lastPathComponent }
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                timestamps = []
            }
            var installed: RecordedCask?
            for timestamp in timestamps {
                let values = try timestamp.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
                let json = timestamp.appendingPathComponent("Casks").appendingPathComponent("\(token).json")
                do {
                    installed = try JSONDecoder().decode(RecordedCask.self, from: Data(contentsOf: json))
                    break
                } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                    let ruby = timestamp.appendingPathComponent("Casks").appendingPathComponent("\(token).rb")
                    do {
                        let values = try ruby.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                        guard values.isRegularFile == true, values.isSymbolicLink != true,
                              let artifacts = receipt?.uninstall_artifacts else {
                            throw CaskAdoptionError.installationTargetsUnavailable
                        }
                        installed = RecordedCask(artifacts: artifacts, url_specs: nil)
                        break
                    } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                        continue
                    }
                }
            }
            guard let artifacts = installed?.artifacts ?? receipt?.uninstall_artifacts else {
                throw CaskAdoptionError.installationTargetsUnavailable
            }
            var staged = version
            if let onlyPath = installed?.url_specs?.only_path {
                guard isSafeRelativePath(onlyPath) else { throw CaskAdoptionError.installationTargetsUnavailable }
                staged.appendPathComponent(onlyPath)
            }
            guard isInside(staged.resolvingSymlinksInPath(), directory: version.resolvingSymlinksInPath()) else {
                throw CaskAdoptionError.installationTargetsUnavailable
            }
            for artifact in artifacts {
                guard let app = artifact.app else { continue }
                guard artifact.bundleName != nil,
                      let source = app.compactMap({ value -> String? in
                          if case .source(let path) = value { return path }
                          return nil
                      }).first,
                      CaskArtifact.isSafeAppTargetPath(source) else {
                    throw CaskAdoptionError.installationTargetsUnavailable
                }
                let entry = staged.appendingPathComponent(source)
                guard isInside(entry.deletingLastPathComponent().resolvingSymlinksInPath(),
                               directory: version.resolvingSymlinksInPath()) else {
                    throw CaskAdoptionError.installationTargetsUnavailable
                }
                do {
                    guard try entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true else {
                        throw CaskAdoptionError.installationTargetsUnavailable
                    }
                    let resolved = entry.resolvingSymlinksInPath().standardizedFileURL
                    guard try resolved.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                        throw CaskAdoptionError.installationTargetsUnavailable
                    }
                    result.insert(resolved)
                } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                    throw CaskAdoptionError.installationTargetsUnavailable
                }
            }
        }
        return result.sorted { $0.path < $1.path }
    }

    private nonisolated static func isSafeRelativePath(_ path: String) -> Bool {
        !(path as NSString).isAbsolutePath && !path.contains("\0")
            && path.components(separatedBy: "/").allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private nonisolated static func isInside(_ url: URL, directory: URL) -> Bool {
        let parent = directory.standardizedFileURL.path
        let child = url.standardizedFileURL.path
        return child == parent || child.hasPrefix(parent.hasSuffix("/") ? parent : parent + "/")
    }

    nonisolated static var applicationDirectories: [URL] {
        let configured = appDirectory
        return [configured] + [
            URL.applicationDirectory,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ].filter { $0 != configured }
    }

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
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }
        return URL.applicationDirectory
    }
}

// MARK: - Launch error

enum AppLaunchError: LocalizedError {
    case appNotFound(name: String)

    /// Reaches the user as an alert body, so it's localized.
    var errorDescription: String? {
        switch self {
        case .appNotFound(let name):
            return String(localized: "Applite couldn't locate \(name) on disk",
                          comment: "Error shown when an installed app's bundle can't be found to launch it (app name)")
        }
    }
}

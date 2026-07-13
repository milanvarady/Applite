//
//  GitShim.swift
//  Applite
//
//  Created by Milán Várady on 2025.07.06.
//

import Foundation
import OSLog

/// A stand-in `git` for the CLT-free annex brew.
///
/// Homebrew refuses to install a cask until `git --version` succeeds (`Utils::Git.ensure_installed!`),
/// even though it never actually clones for normal curl-download casks. On a Mac without the Xcode
/// Command Line Tools there is no usable git, so brew tries to *build* one and fails with
/// "No developer tools installed."
///
/// This shim answers `git --version` with a valid version so brew's availability check passes; brew
/// then downloads the cask with curl as usual. Any real git operation exits non-zero — the same
/// outcome as the annex's missing `.git` repo, which brew already tolerates. It is only used for the
/// annex (see `Shell`); a user's own brew keeps its real git.
///
/// Trade-off: the rare casks that fetch from a git repository (`using: :git`) won't work under the
/// annex. Those users can point Applite at a full Homebrew install in Settings.
enum GitShim {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: GitShim.self)
    )

    static let directory = AppPaths.applicationSupport
        .appending(path: "git-shim", directoryHint: .isDirectory)

    /// Path Homebrew is pointed at via `HOMEBREW_GIT_PATH`.
    static let executable = directory.appendingPathComponent("git")

    /// Homebrew parses the version from the trailing token of `git --version`, and requires
    /// >= 2.14.3 on macOS — so the line must end in a plain, high-enough version number.
    private static let script = """
    #!/bin/sh
    if [ "$1" = "--version" ]; then
      echo "git version 2.45.0"
      exit 0
    fi
    exit 1
    """

    /// Writes the shim (once) and marks it executable. Cheap to call repeatedly — it no-ops when the
    /// script is already present and up to date.
    static func ensureInstalled() {
        if FileManager.default.isExecutableFile(atPath: executable.path),
           let existing = try? String(contentsOf: executable, encoding: .utf8),
           existing == script {
            return
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try script.write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            logger.info("git shim installed at \(executable.path, privacy: .public)")
        } catch {
            logger.error("Failed to install git shim: \(error.localizedDescription)")
        }
    }
}

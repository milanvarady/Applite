//
//  AppMigration.swift
//  Applite
//
//  Created by Milán Várady on 2023. 08. 11..
//

import Foundation
import OSLog

enum CaskImportError: Error {
    case EmptyFile
}

enum AppMigration {
    /// Builds Brewfile-syntax text from the selected view models: a `tap "user/repo"` line for each
    /// distinct non-default tap present, then a `cask "<fullToken>"` line per app. Output is sorted
    /// so exports are deterministic. Uses `fullToken` so cross-tap setups re-import cleanly.
    ///
    /// `@MainActor` because `CaskViewModel`'s `tap`/`fullToken` are main-actor isolated.
    @MainActor
    static func makeBrewfile(from casks: [CaskViewModel]) -> String {
        let taps = Set(casks.map(\.tap))
            .subtracting(["homebrew/cask"])
            .sorted()

        let tapLines = taps.map { "tap \"\($0)\"" }
        let caskLines = casks
            .map(\.fullToken)
            .sorted()
            .map { "cask \"\($0)\"" }

        return (tapLines + caskLines).joined(separator: "\n") + "\n"
    }

    static func readCaskFile(url: URL) throws -> Set<CaskId> {
        var content = try String(contentsOf: url)
        // Strip a leading UTF-8 BOM: CharacterSet.whitespaces doesn't include U+FEFF, so a
        // BOM-prefixed first token would silently fail to resolve on import (P2-22).
        if content.hasPrefix("\u{FEFF}") { content.removeFirst() }
        var casks: Set<CaskId> = []
        // `[\w/@.-]+` matches tap-qualified tokens (`user/repo/token`) AND versioned ones
        // (`temurin@17`, `firefox@esr`) — dropping `@`/`.` silently lost those on import and broke
        // Applite's own export→import round trip (export writes fullToken).
        // Extended delimiters `#/.../#` let the `/` appear unescaped without ending the literal.
        let brewfileRegex = #/cask "([\w/@.-]+)"/#

        // Check if the file being imported is a Brewfile
        // Brewfiles store casks as cask "caskName"
        if content.contains("cask \"") {
            // Brewfile — `tap "..."` lines are intentionally ignored (brew auto-taps on install of
            // a full-token cask).
            let matches = content.matches(of: brewfileRegex)
            casks.formUnion(
                matches.map({ String($0.1) })
            )
        } else {
            // Legacy Applite txt export: one token per line, trimmed.
            casks.formUnion(
                content.components(separatedBy: .newlines)
                    .map({ $0.trimmingCharacters(in: .whitespaces) })
            )
        }

        // Remove empty elements
        casks = casks.filter({ !$0.isEmpty })

        if casks.isEmpty {
            throw CaskImportError.EmptyFile
        }

        return casks
    }
}
